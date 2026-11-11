import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:genui_app_maker/ai/app_session.dart';
import 'package:genui_app_maker/ai/fake_app_generator.dart';
import 'package:genui_app_maker/storage/saved_app.dart';

const notesResponse = '''
메모장을 만들었습니다.

```json
{"version":"v0.9","createSurface":{"surfaceId":"main","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json","sendDataModel":true}}
```

```json
{"version":"v0.9","updateDataModel":{"surfaceId":"main","path":"/","value":{"draft":"","notes":[{"text":"첫 메모"}]}}}
```

```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
 {"id":"root","component":"Column","children":["title","input","save","notes"]},
 {"id":"title","component":"Text","text":"메모장","variant":"h2"},
 {"id":"input","component":"TextField","label":"새 메모","value":{"path":"/draft"}},
 {"id":"save","component":"Button","child":"saveLabel","action":{"event":{"name":"save_note"}}},
 {"id":"saveLabel","component":"Text","text":"저장"},
 {"id":"notes","component":"List","children":{"componentId":"noteRow","path":"/notes"}},
 {"id":"noteRow","component":"Text","text":{"path":"text"}}
]}}
```
''';

Widget host(AppSession session) => MaterialApp(
  home: Scaffold(
    body: ValueListenableBuilder<ConversationState>(
      valueListenable: session.state,
      builder: (context, state, _) => Column(
        children: [
          for (final id in state.surfaces)
            Expanded(child: Surface(surfaceContext: session.contextFor(id))),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('send renders the generated surface and records transcript', (
    tester,
  ) async {
    final generator = FakeAppGenerator([notesResponse]);
    final session = AppSession(
      catalog: BasicCatalogItems.asNoAssetCatalog(),
      generator: generator,
    );
    await tester.pumpWidget(host(session));
    await session.send('메모장 만들어줘');
    await tester.pumpAndSettle();

    expect(find.text('메모장'), findsOneWidget);
    expect(find.text('첫 메모'), findsOneWidget);
    expect(session.transcript, contains('createSurface'));
    expect(generator.requests, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('generator failure surfaces as ConversationError', (
    tester,
  ) async {
    final generator = FakeAppGenerator([])..nextError = StateError('offline');
    final session = AppSession(
      catalog: BasicCatalogItems.asNoAssetCatalog(),
      generator: generator,
    );
    final errors = <ConversationError>[];
    session.events.listen((e) {
      if (e is ConversationError) errors.add(e);
    });
    await session.send('메모장 만들어줘');
    await tester.pump();

    expect(errors, hasLength(1));
    expect(session.state.value.isWaiting, isFalse);
    session.dispose();
  });

  testWidgets('snapshot survives JSON round trip and restore', (tester) async {
    final first = AppSession(
      catalog: BasicCatalogItems.asNoAssetCatalog(),
      generator: FakeAppGenerator([notesResponse]),
    );
    await tester.pumpWidget(host(first));
    await first.send('메모장 만들어줘');
    await tester.pumpAndSettle();

    // 사용자가 메모를 바꾼 상황.
    first.contextFor('main').dataModel.update(DataPath('/notes'), [
      {'text': '첫 메모'},
      {'text': '저장 후에도 남아야 하는 메모'},
    ]);
    await tester.pumpAndSettle();

    final saved = SavedApp(
      id: '1',
      name: '메모장',
      prompt: '메모장 만들어줘',
      createdAt: DateTime(2026, 11, 10),
      transcript: first.transcript,
      data: first.dataSnapshot(),
    );
    final restoredJson =
        jsonDecode(jsonEncode(saved.toJson())) as Map<String, Object?>;
    await tester.pumpWidget(const SizedBox());
    first.dispose();

    final generator = FakeAppGenerator([]);
    final second = AppSession(
      catalog: BasicCatalogItems.asNoAssetCatalog(),
      generator: generator,
    );
    await tester.pumpWidget(host(second));
    second.restore(SavedApp.fromJson(restoredJson));
    await tester.pumpAndSettle();

    expect(find.text('메모장'), findsOneWidget);
    expect(find.text('저장 후에도 남아야 하는 메모'), findsOneWidget);
    expect(generator.primedTranscript, contains('createSurface'));
    expect(generator.requests, isEmpty);

    await tester.pumpWidget(const SizedBox());
    second.dispose();
  });
}
