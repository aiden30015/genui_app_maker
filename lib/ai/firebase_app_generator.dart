import 'dart:convert';

// firebase_ai와 genui(genai_primitives)가 둘 다 TextPart, Part를 내보내므로
// firebase 쪽에 접두사를 붙인다.
import 'package:firebase_ai/firebase_ai.dart' as fai;
import 'package:genui/genui.dart';

import 'app_generator.dart';

/// 사용할 Gemini 모델(SPEC L-6). 모델을 바꿀 때는 여기만 고친다.
///
/// Flutter 공식 genui 문서의 예제가 쓰는 모델이다. `gemini-3.5-flash-lite`는
/// 되묻기 답변 뒤에 화면 JSON 없이 말로만 답하는 경우가 있어 쓰지 않는다
/// (2026-11 기기 시험).
const String kGeminiModel = 'gemini-3.5-flash';

/// 대화 이력의 한 턴. [isModel]이 false면 사용자 턴.
typedef HistoryTurn = ({bool isModel, String text});

/// 텍스트 한 건을 보내고 응답 텍스트 조각을 스트리밍하는 함수.
typedef ChatSend = Stream<String> Function(String text);

/// [history]로 시작하는 대화를 열고, 그 대화에 메시지를 보내는 함수를 돌려준다.
///
/// 테스트에서 Firebase 없이 [FirebaseAppGenerator]를 돌리기 위한 주입 지점.
typedef ChatStarter = ChatSend Function({
  required String systemPrompt,
  required String model,
  required List<HistoryTurn> history,
});

/// genui의 [ChatMessage]를 Gemini에 보낼 텍스트로 바꾼다.
///
/// 사용자 프롬프트는 텍스트 그대로, UI 이벤트(버튼, 되묻기 답변)와 클라이언트
/// 오류는 genui가 만든 A2UI JSON 원문을 머리말과 함께 넣는다. 모델이 이벤트
/// 이름과 context를 그대로 볼 수 있어야 하기 때문이다.
String chatMessageToPromptText(ChatMessage message) {
  final sections = <String>[];
  for (final StandardPart part in message.parts) {
    final String? section = switch (part) {
      TextPart(:final text) => text,
      DataPart() => _dataPartToText(part),
      LinkPart(:final url) => '[link] $url',
      ToolPart() => '[tool] ${jsonEncode(part.toJson())}',
      // 모델 자신의 사고 과정은 다시 보내지 않는다.
      ThinkingPart() => null,
    };
    if (section != null && section.trim().isNotEmpty) {
      sections.add(section.trim());
    }
  }
  return sections.join('\n\n');
}

String _dataPartToText(DataPart part) {
  if (part.isUiInteractionPart) {
    final String interaction = part.asUiInteractionPart!.interaction;
    return '${_interactionHeader(interaction)}\n$interaction';
  }
  if (part.mimeType == UiPartConstants.uiMimeType) {
    return '[UI definition]\n${utf8.decode(part.bytes)}';
  }
  // 이 앱은 첨부를 보내지 않는다. 내용을 지어내지 않고 존재만 알린다.
  return '[attachment omitted: ${part.mimeType}]';
}

/// `SurfaceController`는 사용자 액션을 `{"version", "action"}`으로, 클라이언트
/// 오류를 `{"version", "error"}`로 보낸다. 둘을 모델이 구분하게 머리말을 단다.
String _interactionHeader(String interaction) {
  Object? decoded;
  try {
    decoded = jsonDecode(interaction);
  } on FormatException {
    decoded = null;
  }
  if (decoded is Map && decoded.containsKey('error')) {
    return '[UI error] The client could not apply your last A2UI output. '
        'Fix it and resend:';
  }
  return '[UI event] The user triggered an action in the generated UI:';
}

/// Firebase AI Logic(Gemini Developer API)로 응답을 받는 [AppGenerator].
///
/// 모델과 `ChatSession`은 첫 [generate]에서 만든다. 그래서 이 객체를 만드는
/// 것만으로는 Firebase가 초기화되어 있을 필요가 없고, 그 전에 [primeHistory]로
/// 이력을 채울 수 있다.
class FirebaseAppGenerator implements AppGenerator {
  FirebaseAppGenerator({
    required this.systemPrompt,
    this.model = kGeminiModel,
    ChatStarter? chatStarter,
  }) : _chatStarter = chatStarter ?? _startFirebaseChat;

  final String systemPrompt;
  final String model;
  final ChatStarter _chatStarter;

  final List<HistoryTurn> _primedHistory = [];
  ChatSend? _send;

  @override
  Stream<String> generate(ChatMessage message) async* {
    final String text = chatMessageToPromptText(message);
    // 빈 요청은 API가 거절하므로 보내지 않는다.
    if (text.isEmpty) return;
    final ChatSend send = _send ??= _chatStarter(
      systemPrompt: systemPrompt,
      model: model,
      history: List.unmodifiable(_primedHistory),
    );
    yield* send(text);
  }

  @override
  void primeHistory({required String prompt, required String transcript}) {
    if (_send != null) {
      throw StateError('primeHistory는 첫 generate 호출 전에만 쓸 수 있습니다.');
    }
    _primedHistory
      ..add((isModel: false, text: prompt))
      ..add((isModel: true, text: transcript));
  }

  @override
  void dispose() {
    _send = null;
  }
}

/// 실제 Firebase 연결. `Firebase.initializeApp()`이 끝난 뒤에만 호출된다.
ChatSend _startFirebaseChat({
  required String systemPrompt,
  required String model,
  required List<HistoryTurn> history,
}) {
  final fai.GenerativeModel generativeModel = fai.FirebaseAI.googleAI()
      .generativeModel(
        model: model,
        systemInstruction: fai.Content.system(systemPrompt),
      );
  final fai.ChatSession chat = generativeModel.startChat(
    history: [
      for (final HistoryTurn turn in history)
        turn.isModel
            ? fai.Content.model([fai.TextPart(turn.text)])
            : fai.Content.text(turn.text),
    ],
  );
  return (String text) async* {
    await for (final fai.GenerateContentResponse chunk
        in chat.sendMessageStream(fai.Content.text(text))) {
      final String? piece = chunk.text;
      if (piece != null && piece.isNotEmpty) yield piece;
    }
  };
}
