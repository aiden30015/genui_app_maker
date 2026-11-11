import 'package:genui/genui.dart';

import '../catalog/game/physics_game_item.dart';
import 'app_generator.dart';
import 'firebase_app_generator.dart' show chatMessageToPromptText;

/// LLM 없이 정해진 응답을 내보내는 생성기.
///
/// Firebase 없이 기기에서 화면·게임·저장 흐름을 확인하는 용도다.
/// `--dart-define=DEMO_LLM=true`로 켠다. 프롬프트의 단어만 보고 고른다.
class DemoAppGenerator implements AppGenerator {
  bool _surfaceCreated = false;

  @override
  Stream<String> generate(ChatMessage message) async* {
    final String text = chatMessageToPromptText(message);
    // 스트리밍을 흉내 내 대기 표시를 볼 수 있게 한다.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final String components;
    final String data;
    final String intro;
    if (text.contains('clarify_answered') || text.contains('핀볼')) {
      (intro, data, components) = ('핀볼 게임을 만들었어요.', '{}', pinballExample);
    } else if (text.contains('게임')) {
      (intro, data, components) = ('몇 가지만 여쭤볼게요.', '{}', _clarify);
    } else if (text.contains('체스')) {
      yield '체스는 만들 수 없어요. 대신 핀볼이나 벽돌깨기는 만들 수 있어요.';
      return;
    } else {
      (intro, data, components) = ('메모장을 만들었어요.', _notesData, _notes);
    }

    yield '$intro\n\n';
    if (!_surfaceCreated) {
      _surfaceCreated = true;
      yield _block(
        '{"version":"v0.9","createSurface":{"surfaceId":"main",'
        '"catalogId":"$basicCatalogId","sendDataModel":true}}',
      );
    }
    yield _block(
      '{"version":"v0.9","updateDataModel":{"surfaceId":"main",'
      '"path":"/","value":$data}}',
    );
    yield _block(
      '{"version":"v0.9","updateComponents":{"surfaceId":"main",'
      '"components":$components}}',
    );
  }

  @override
  void primeHistory({required String prompt, required String transcript}) {
    _surfaceCreated = true;
  }

  @override
  void dispose() {}
}

String _block(String json) => '```json\n$json\n```\n\n';

const String _clarify = '''
[{"id":"root","component":"ClarifyQuestions","title":"어떤 게임을 만들까요?","questions":[
 {"id":"genre","text":"장르","options":["핀볼","벽돌깨기","퐁"],"allowFreeText":true}]}]''';

const String _notesData = '{"draft":"","notes":[{"text":"첫 메모"}]}';

const String _notes = '''
[{"id":"root","component":"Column","children":["title","input","add","notes"]},
 {"id":"title","component":"Text","text":"메모장","variant":"h2"},
 {"id":"input","component":"TextField","label":"새 메모","value":{"path":"/draft"}},
 {"id":"add","component":"Button","child":"addLabel","variant":"primary","action":{"functionCall":{"call":"listAppend","args":{"path":"/notes","item":{"text":{"path":"/draft"}},"clear":["/draft"]}}}},
 {"id":"addLabel","component":"Text","text":"추가"},
 {"id":"notes","component":"List","children":{"componentId":"noteRow","path":"/notes"}},
 {"id":"noteRow","component":"Row","children":["noteText","noteDelete"]},
 {"id":"noteText","component":"Text","text":{"path":"text"}},
 {"id":"noteDelete","component":"Button","child":"noteDeleteLabel","variant":"borderless","action":{"functionCall":{"call":"listRemove","args":{}}}},
 {"id":"noteDeleteLabel","component":"Text","text":"삭제"}]''';
