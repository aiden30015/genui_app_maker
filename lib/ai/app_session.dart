import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';

import '../catalog/clarify_questions.dart';
import '../storage/saved_app.dart';
import 'app_generator.dart';

/// 요청 끝에 현재 데이터 모델을 덧붙일 때 쓰는 머리말.
const String kDataModelNote =
    '[Current data model per surface. Preserve user data unless asked to '
    'change it]';

/// 앱 하나를 만들고 실행하는 동안의 genui 배선.
///
/// 흐름: [send] → Conversation → transport.onSend → [AppGenerator.generate]
/// → transport.addChunk → SurfaceController → Surface 위젯.
/// 생성된 UI의 버튼 이벤트도 같은 onSend 경로로 다시 들어온다.
class AppSession {
  AppSession({required Catalog catalog, required this.generator}) {
    controller = SurfaceController(catalogs: [catalog]);
    _transport = A2uiTransportAdapter(onSend: _onSend);
    _conversation = Conversation(controller: controller, transport: _transport);
  }

  final AppGenerator generator;
  late final SurfaceController controller;
  late final A2uiTransportAdapter _transport;
  late final Conversation _conversation;

  /// 모델이 보낸 응답 원문 누적. 저장과 복원에 쓴다.
  final StringBuffer _transcript = StringBuffer();

  /// 대기 여부, 살아 있는 surface 목록, 최근 텍스트.
  ValueListenable<ConversationState> get state => _conversation.state;

  /// 오류([ConversationError])와 surface 추가/삭제 이벤트.
  Stream<ConversationEvent> get events => _conversation.events;

  String get transcript => _transcript.toString();

  /// `Surface(surfaceContext: session.contextFor(id))`로 렌더한다.
  SurfaceContext contextFor(String surfaceId) =>
      controller.contextFor(surfaceId);

  /// 사용자의 프롬프트나 수정 요청을 보낸다.
  Future<void> send(String text) =>
      _conversation.sendRequest(ChatMessage.user(text));

  /// 마지막으로 모델에 보낸 요청(데이터를 덧붙이기 전 원본).
  ///
  /// 입력창에서 보낸 문장뿐 아니라 되묻기 답변처럼 화면 버튼에서 나간 요청도
  /// 같은 [_onSend]를 지나므로 여기에 남는다.
  ChatMessage? _lastRequest;

  bool get canRetry => _lastRequest != null;

  /// 마지막 요청을 그대로 다시 보낸다.
  ///
  /// 실패한 요청은 생성기 대화 이력에 남지 않으므로 다시 보내도 중복되지 않는다.
  /// 데이터 모델은 [_onSend]에서 지금 값으로 다시 덧붙는다.
  Future<void> retryLast() {
    final ChatMessage? last = _lastRequest;
    if (last == null) return Future<void>.value();
    return _conversation.sendRequest(last);
  }

  /// 화면이 아직 앱이 아니라 질문 카드(`ClarifyQuestions`)인지.
  bool get isAskingQuestions => state.value.surfaces.any(
    (id) =>
        controller.contextFor(id).definition.value?.components['root']?.type ==
        clarifyQuestionsItem.name,
  );

  /// 현재 surface별 데이터 모델 스냅샷.
  Map<String, Object?> dataSnapshot() => {
    for (final String id in state.value.surfaces)
      id: controller.contextFor(id).dataModel.getValue<Object?>(DataPath.root),
  };

  /// 저장된 앱을 다시 띄운다.
  ///
  /// 원문을 재생하고, 저장된 데이터는 `updateDataModel` 메시지로 만들어 그 뒤에
  /// 이어 보낸다. 타이밍에 기대지 않고 메시지 순서로 "화면 → 데이터"를 보장한다.
  void restore(SavedApp app) {
    _transcript.write(app.transcript);
    generator.primeHistory(prompt: app.prompt, transcript: app.transcript);
    final replay = StringBuffer(app.transcript);
    for (final MapEntry<String, Object?> entry in app.data.entries) {
      final String message = jsonEncode({
        'version': 'v0.9',
        'updateDataModel': {
          'surfaceId': entry.key,
          'path': '/',
          'value': entry.value,
        },
      });
      replay.write('\n```json\n$message\n```\n');
    }
    _transport.addChunk(replay.toString());
  }

  Future<void> _onSend(ChatMessage message) async {
    _lastRequest = message;
    final ChatMessage request = _withData(message);
    final response = StringBuffer();
    await for (final String chunk in generator.generate(request)) {
      // 응답이 오는 중에 화면을 나가면 transport는 이미 닫혀 있다.
      if (_disposed) return;
      response.write(chunk);
      _transcript.write(chunk);
      _transport.addChunk(chunk);
    }
    if (_disposed) return;
    // 프롬프트를 다듬을 때 모델이 실제로 무엇을 보냈는지 봐야 한다.
    if (kDebugMode) {
      debugPrint('[llm request] ${request.text}', wrapWidth: 800);
      debugPrint('[llm response] $response', wrapWidth: 800);
    }
    // 다음 응답의 JSON 블록이 앞 응답 텍스트에 붙지 않게 구분한다.
    _transcript.write('\n');
    _transport.addChunk('\n');
  }

  /// 사용자가 기기에서 바꾼 데이터(메모 등)를 요청에 덧붙인다.
  ///
  /// 로컬 함수로 바뀐 값은 모델이 알 길이 없어서, 알려 주지 않으면 수정 요청 때
  /// 모델이 처음 값으로 데이터를 되돌릴 수 있다.
  ChatMessage _withData(ChatMessage message) {
    final Map<String, Object?> data = dataSnapshot()
      ..removeWhere((_, value) => value == null);
    if (data.isEmpty) return message;
    return message.copyWith(
      parts: [
        ...message.parts,
        TextPart('\n\n$kDataModelNote\n${jsonEncode(data)}'),
      ],
    );
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _conversation.dispose();
    _transport.dispose();
    controller.dispose();
    generator.dispose();
  }
}
