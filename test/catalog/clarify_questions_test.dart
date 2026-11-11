import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:genui_app_maker/ai/app_session.dart';
import 'package:genui_app_maker/ai/fake_app_generator.dart';
import 'package:genui_app_maker/ai/firebase_app_generator.dart';
import 'package:genui_app_maker/catalog/clarify_questions.dart';

const clarifyResponse = '''
몇 가지만 여쭤볼게요.

```json
{"version":"v0.9","createSurface":{"surfaceId":"main","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json","sendDataModel":true}}
```

```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
 {"id":"root","component":"ClarifyQuestions","title":"어떤 게임을 만들까요?","questions":[
  {"id":"genre","text":"장르","options":["핀볼","벽돌깨기","퐁"],"allowFreeText":true},
  {"id":"difficulty","text":"난이도","options":["쉬움","어려움"],"allowFreeText":false}
 ]}
]}}
```
''';

const builtResponse = '''
```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
 {"id":"root","component":"Text","text":"핀볼 게임 완성"}
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

Catalog catalog() => BasicCatalogItems.asNoAssetCatalog().copyWith(
  newItems: [clarifyQuestionsItem],
);

Future<(AppSession, FakeAppGenerator)> pumpCard(
  WidgetTester tester, {
  List<String> more = const [],
}) async {
  final generator = FakeAppGenerator([clarifyResponse, ...more]);
  final session = AppSession(catalog: catalog(), generator: generator);
  await tester.pumpWidget(host(session));
  await session.send('게임 만들어줘');
  await tester.pumpAndSettle();
  return (session, generator);
}

Future<void> tearDownSession(WidgetTester tester, AppSession session) async {
  await tester.pumpWidget(const SizedBox());
  session.dispose();
}

bool submitEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

bool chipSelected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

void main() {
  test('item name and example data match the contract', () {
    expect(clarifyQuestionsItem.name, 'ClarifyQuestions');
    expect(clarifyQuestionsItem.exampleData, hasLength(1));
    final components =
        jsonDecode(clarifyQuestionsItem.exampleData.single()) as List;
    final root = components.cast<Map<String, Object?>>().singleWhere(
      (c) => c['id'] == 'root',
    );
    expect(root['component'], 'ClarifyQuestions');
    expect(root['title'], isA<String>());
    expect((root['questions']! as List).length, lessThanOrEqualTo(3));
  });

  testWidgets('renders title, questions, chips and free text from A2UI', (
    tester,
  ) async {
    final (session, generator) = await pumpCard(tester);

    expect(find.text('어떤 게임을 만들까요?'), findsOneWidget);
    expect(find.text('장르'), findsOneWidget);
    expect(find.text('난이도'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(5));
    // allowFreeText가 true인 문항에만 입력창이 있다.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('만들기'), findsOneWidget);
    // 스키마 검증 오류가 있었다면 오류 보고가 두 번째 요청으로 들어온다.
    expect(generator.requests, hasLength(1));

    await tearDownSession(tester, session);
  });

  testWidgets('submit is enabled only when every question is answered', (
    tester,
  ) async {
    final (session, _) = await pumpCard(tester);
    expect(submitEnabled(tester), isFalse);

    await tester.tap(find.text('핀볼'));
    await tester.pump();
    expect(chipSelected(tester, '핀볼'), isTrue);
    expect(submitEnabled(tester), isFalse);

    await tester.tap(find.text('쉬움'));
    await tester.pump();
    expect(submitEnabled(tester), isTrue);

    // 같은 문항에서 다른 칩을 고르면 하나만 선택된다.
    await tester.tap(find.text('퐁'));
    await tester.pump();
    expect(chipSelected(tester, '핀볼'), isFalse);
    expect(chipSelected(tester, '퐁'), isTrue);

    // 선택을 해제하면 다시 비활성.
    await tester.tap(find.text('쉬움'));
    await tester.pump();
    expect(submitEnabled(tester), isFalse);

    await tearDownSession(tester, session);
  });

  testWidgets('free text and chip are mutually exclusive', (tester) async {
    final (session, _) = await pumpCard(tester);

    await tester.tap(find.text('핀볼'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '테트리스');
    await tester.pump();
    expect(chipSelected(tester, '핀볼'), isFalse);

    await tester.tap(find.text('벽돌깨기'));
    await tester.pump();
    expect(chipSelected(tester, '벽돌깨기'), isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    await tearDownSession(tester, session);
  });

  testWidgets('submit sends exactly one clarify_answered event with answers', (
    tester,
  ) async {
    // 두 번째 응답이 없으므로 제출 뒤에도 카드가 화면에 남는다.
    final (session, generator) = await pumpCard(tester);

    await tester.enterText(find.byType(TextField), ' 테트리스 ');
    await tester.pump();
    await tester.tap(find.text('어려움'));
    await tester.pump();
    await tester.tap(find.text('만들기'));
    await tester.pumpAndSettle();

    expect(generator.requests, hasLength(2));
    // AppSession이 요청 끝에 덧붙이는 데이터 모델 부분은 떼고 본다.
    final String sent = chatMessageToPromptText(generator.requests[1])
        .split(kDataModelNote)
        .first;
    final action =
        (jsonDecode(sent.substring(sent.indexOf('{'))) as Map)['action'] as Map;
    expect(action['name'], 'clarify_answered');
    expect(action['sourceComponentId'], 'root');
    expect(action['context'], {
      'answers': {'genre': '테트리스', 'difficulty': '어려움'},
    });

    // 제출 뒤에는 잠긴다: 버튼, 칩, 입력창 모두 비활성.
    expect(find.text('만들기'), findsNothing);
    expect(submitEnabled(tester), isFalse);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .every((chip) => chip.onSelected == null),
      isTrue,
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(generator.requests, hasLength(2));

    await tearDownSession(tester, session);
  });

  testWidgets('the app replaces the card after answers arrive', (tester) async {
    final (session, generator) = await pumpCard(tester, more: [builtResponse]);

    await tester.tap(find.text('핀볼'));
    await tester.pump();
    await tester.tap(find.text('쉬움'));
    await tester.pump();
    await tester.tap(find.text('만들기'));
    await tester.pumpAndSettle();

    expect(generator.requests, hasLength(2));
    expect(find.text('핀볼 게임 완성'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);

    await tearDownSession(tester, session);
  });

  testWidgets('more than three questions are not shown', (tester) async {
    final generator = FakeAppGenerator([
      '''
```json
{"version":"v0.9","createSurface":{"surfaceId":"main","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json","sendDataModel":true}}
```

```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
 {"id":"root","component":"ClarifyQuestions","title":"질문","questions":[
  {"id":"a","text":"첫째","options":["1","2"]},
  {"id":"b","text":"둘째","options":["3","4"]},
  {"id":"c","text":"셋째","options":["5","6"]},
  {"id":"d","text":"넷째","options":["7","8"]}
 ]}
]}}
```
''',
    ]);
    final session = AppSession(catalog: catalog(), generator: generator);
    await tester.pumpWidget(host(session));
    await session.send('아무거나');
    await tester.pumpAndSettle();

    expect(find.text('셋째'), findsOneWidget);
    expect(find.text('넷째'), findsNothing);

    await tearDownSession(tester, session);
  });
}
