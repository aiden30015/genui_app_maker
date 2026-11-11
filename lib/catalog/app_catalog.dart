import 'package:genui/genui.dart';

import 'clarify_questions.dart';
import 'data_functions.dart';
import 'game/physics_game_item.dart';

/// LLM이 쓸 수 있는 전체 어휘. (SPEC 5장)
///
/// 기본 카탈로그(이미지·오디오·비디오 제외)에 되묻기 카드, 게임 위젯,
/// 로컬 데이터 함수를 더한다. `copyWith`는 catalogId를 유지하므로 모델은
/// 기본 카탈로그의 id를 그대로 쓴다.
Catalog buildAppCatalog() => BasicCatalogItems.asNoAssetCatalog().copyWith(
  newItems: [clarifyQuestionsItem, physicsGameItem],
  newFunctions: dataFunctions,
);
