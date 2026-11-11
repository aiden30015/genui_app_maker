import 'package:genui/genui.dart';

/// LLM 호출을 감추는 경계.
///
/// 구현체는 대화 이력을 스스로 관리하고, 응답 텍스트(A2UI JSON 블록 포함)를
/// 청크 단위로 내보낸다. 실제 구현은 Firebase AI Logic, 테스트는 가짜 구현을 쓴다.
abstract interface class AppGenerator {
  /// [message]를 LLM에 보내고 응답 텍스트를 스트리밍한다.
  ///
  /// [message]는 사용자가 입력한 프롬프트이거나, 생성된 UI에서 발생한
  /// 사용자 액션(버튼 이벤트, 되묻기 답변)이다.
  /// 실패는 스트림 오류로 전달한다.
  Stream<String> generate(ChatMessage message);

  /// 저장된 앱을 복원했을 때, 이전에 모델이 보낸 응답 원문을 이력에 넣는다.
  ///
  /// 이후의 수정 요청이 현재 화면을 문맥으로 갖게 하기 위함이다.
  /// 첫 [generate] 호출 전에만 부른다.
  void primeHistory({required String prompt, required String transcript});

  void dispose();
}
