import 'package:genui/genui.dart';

import 'app_generator.dart';

/// 준비된 응답을 순서대로 내보내는 테스트용 [AppGenerator].
class FakeAppGenerator implements AppGenerator {
  FakeAppGenerator(List<String> responses) : _responses = [...responses];

  final List<String> _responses;

  /// 지금까지 받은 요청.
  final List<ChatMessage> requests = [];

  /// [primeHistory]로 받은 원문.
  String? primedTranscript;

  /// null이 아니면 다음 [generate]가 이 오류로 실패한다.
  Object? nextError;

  @override
  Stream<String> generate(ChatMessage message) async* {
    requests.add(message);
    final Object? error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    if (_responses.isEmpty) return;
    yield _responses.removeAt(0);
  }

  @override
  void primeHistory({required String prompt, required String transcript}) {
    primedTranscript = transcript;
  }

  @override
  void dispose() {}
}
