import 'dart:async';

import 'package:genui/genui.dart';
import 'package:genui_app_maker/ai/app_generator.dart';
import 'package:genui_app_maker/ai/app_session.dart';
import 'package:genui_app_maker/ai/fake_app_generator.dart';
import 'package:genui_app_maker/storage/saved_app.dart';
import 'package:genui_app_maker/storage/saved_app_repository.dart';

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

/// 제목만 바꾸는 수정 응답.
const renameResponse = '''
제목을 바꿨습니다.

```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
 {"id":"title","component":"Text","text":"내 메모장","variant":"h2"}
]}}
```
''';

/// 만들기 전에 되묻는 응답. 카탈로그에 `ClarifyQuestions`가 있어야 그려진다.
const clarifyResponse = '''
어떤 앱인지 먼저 여쭤볼게요.

```json
{"version":"v0.9","createSurface":{"surfaceId":"main","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json","sendDataModel":true}}
```

```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
 {"id":"root","component":"ClarifyQuestions","title":"어떤 앱을 만들까요?","questions":[{"id":"kind","text":"종류","options":["메모장","할 일"]}]}
]}}
```
''';

/// 되묻기 답변 뒤에 같은 surface를 앱으로 바꾸는 응답(`createSurface` 없음).
const notesAfterClarifyResponse = '''
메모장을 만들었습니다.

```json
{"version":"v0.9","updateDataModel":{"surfaceId":"main","path":"/","value":{"notes":[{"text":"첫 메모"}]}}}
```

```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
 {"id":"root","component":"Column","children":["title","notes"]},
 {"id":"title","component":"Text","text":"메모장","variant":"h2"},
 {"id":"notes","component":"List","children":{"componentId":"noteRow","path":"/notes"}},
 {"id":"noteRow","component":"Text","text":{"path":"text"}}
]}}
```
''';

/// 테스트용 메모리 저장소.
class InMemoryRepository implements SavedAppRepository {
  InMemoryRepository([List<SavedApp> initial = const []]) : apps = [...initial];

  final List<SavedApp> apps;
  final List<SavedApp> saved = [];
  bool failList = false;

  @override
  Future<List<SavedApp>> list() async {
    if (failList) throw StateError('disk');
    return [...apps];
  }

  @override
  Future<void> save(SavedApp app) async {
    saved.add(app);
    apps
      ..removeWhere((a) => a.id == app.id)
      ..insert(0, app);
  }

  @override
  Future<void> delete(String id) async {
    apps.removeWhere((a) => a.id == id);
  }
}

/// [release]를 부를 때까지 응답을 미루는 생성기.
class GatedGenerator implements AppGenerator {
  GatedGenerator(this.response);

  final String response;
  final Completer<void> _gate = Completer<void>();
  final List<ChatMessage> requests = [];

  void release() => _gate.complete();

  @override
  Stream<String> generate(ChatMessage message) async* {
    requests.add(message);
    await _gate.future;
    yield response;
  }

  @override
  void primeHistory({required String prompt, required String transcript}) {}

  @override
  void dispose() {}
}

/// 세션 팩토리와, 만들어진 세션·생성기를 테스트에서 들여다보기 위한 묶음.
class SessionHarness {
  SessionHarness(this.responses, {Catalog? catalog})
    : catalog = catalog ?? BasicCatalogItems.asNoAssetCatalog();

  final List<String> responses;
  final Catalog catalog;
  final List<FakeAppGenerator> generators = [];
  final List<AppSession> sessions = [];

  /// 다음에 만들 세션의 첫 요청을 실패시킨다.
  Object? firstError;

  FakeAppGenerator get generator => generators.last;
  AppSession get session => sessions.last;

  AppSession create() {
    final generator = FakeAppGenerator(responses)..nextError = firstError;
    final session = AppSession(catalog: catalog, generator: generator);
    generators.add(generator);
    sessions.add(session);
    return session;
  }
}

SavedApp savedNotes({
  String id = '1',
  String name = '내 메모',
  DateTime? createdAt,
  Map<String, Object?>? data,
}) => SavedApp(
  id: id,
  name: name,
  prompt: '메모장 만들어줘',
  createdAt: createdAt ?? DateTime(2026, 11, 10),
  transcript: notesResponse,
  data:
      data ??
      {
        'main': {
          'draft': '',
          'notes': [
            {'text': '첫 메모'},
            {'text': '저장해 둔 메모'},
          ],
        },
      },
);
