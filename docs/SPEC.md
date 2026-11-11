# genui_app_maker 기능 명세서

- 상태: **구현됨** (실제 Gemini 연동 검증은 Firebase 연결 후 진행)
- 작성일: 2026-11-10
- 대상: Android (에뮬레이터 `genui_test`), Flutter 3.47.4, `genui` 0.10.4

## 1. 목표와 비목표

### 목표

사용자가 "핀볼 게임 만들어줘", "메모장 만들어줘"처럼 한 문장을 입력하면, 그 자리에서 바로 쓸 수 있는 앱 화면을 만들어 보여 준다. 요청이 모호하거나 사용자 취향이 필요한 부분은 만들기 전에 되묻는다.

### 비목표 (1차 범위 밖)

- 임의의 Dart/Flutter 코드 생성. LLM은 **등록된 위젯 카탈로그를 조합**만 한다.
- `PhysicsGame`으로 표현할 수 없는 게임 장르(카드, 퍼즐, 3D, 멀티플레이 등).
- 계정, 클라우드 동기화, 만든 앱 공유/배포.
- iOS, Web, 데스크톱.

## 2. 사용자 흐름

```
홈 ──프롬프트 입력──▶ 실행 화면
                      ├─ (모호함) 질문 카드 ──답변──▶ 앱 생성
                      └─ (명확함) 앱 생성
실행 화면 ──수정 요청──▶ 같은 앱 갱신
실행 화면 ──저장──▶ 홈의 "내 앱" 목록 ──탭──▶ 실행 화면(복원)
```

## 3. 화면 요구사항

### 3.1 홈

| ID | 요구사항 |
|---|---|
| H-1 | 프롬프트 입력창과 만들기 버튼. 빈 입력은 전송하지 않는다. |
| H-2 | 예시 칩 3개("메모장 만들어줘", "핀볼 게임 만들어줘", "할 일 목록 만들어줘"). 탭하면 바로 생성한다. |
| H-3 | 저장된 앱 목록(이름, 만든 날짜). 탭하면 실행 화면에서 복원한다. |
| H-4 | 저장된 앱 삭제(길게 눌러 확인 후 삭제). |
| H-5 | 저장된 앱이 없으면 빈 상태 안내 문구를 보여 준다. |

### 3.2 실행 화면

| ID | 요구사항 |
|---|---|
| R-1 | 생성된 surface를 화면 전체에 표시한다. 한 번에 하나의 앱만 표시한다. |
| R-2 | LLM 응답 대기 중에는 진행 표시를 보여 준다(`ConversationState.isWaiting`). |
| R-3 | LLM이 보낸 일반 텍스트(안내, 거절 사유)는 surface 위쪽에 표시한다. |
| R-4 | 하단 입력창으로 수정 요청을 보낸다. 기존 surface가 갱신된다. |
| R-5 | 저장 버튼: 이름을 입력받아 저장한다. 기본 이름은 첫 프롬프트. |
| R-6 | 오류(`ConversationError`, 네트워크, 할당량) 시 메시지와 재시도 버튼을 보여 준다. |
| R-7 | 뒤로 가기 시 저장하지 않은 앱이면 확인을 받는다. |

## 4. 되묻기 규칙

되묻기는 별도 화면이 아니라 카탈로그 위젯 `ClarifyQuestions`로 구현한다. 질문 → 답변 제출 → LLM 재요청이 genui의 기본 루프를 그대로 탄다.

| ID | 규칙 |
|---|---|
| C-1 | **결과물이 달라지는** 모호함이 있을 때만 묻는다. 예: "게임 만들어줘"(장르), "가계부 만들어줘"(관리할 항목). |
| C-2 | 합리적 기본값이 있으면 묻지 않고 만든다. 예: "메모장 만들어줘"는 바로 생성. |
| C-3 | 한 번에 최대 3문항, 문항당 선택지 2~4개 + 직접 입력. |
| C-4 | 되묻기는 요청당 1회. 답변을 받은 뒤에는 반드시 생성한다. |
| C-5 | 지원하지 않는 요청(비목표)은 질문하지 않고, 만들 수 있는 가장 가까운 대안을 제안한다. |

`ClarifyQuestions` 데이터:

```json
{
  "component": "ClarifyQuestions",
  "title": "어떤 게임을 만들까요?",
  "questions": [
    {"id": "genre", "text": "장르", "options": ["핀볼", "벽돌깨기", "퐁"], "allowFreeText": true}
  ]
}
```

제출 시 `UserActionEvent(name: "clarify_answered", context: {answers: {genre: "핀볼"}})`를 dispatch한다.

## 5. 카탈로그

### 5.1 기본 카탈로그 (genui 제공, 소스로 확인)

`BasicCatalogItems.asNoAssetCatalog()` 사용:
Button, Card, CheckBox, ChoicePicker, Column, DateTimeInput, Divider, Icon, List, Modal, Row, Slider, Tabs, Text, TextField.
(AudioPlayer, Image, Video는 1차 범위에서 제외한다.)

### 5.2 로컬 데이터 함수 (신규 `ClientFunction`)

**배경**: 기본 카탈로그의 함수는 검증·포맷용뿐이다(`required`, `regex`, `formatString`, `openUrl` 등). Button의 `event` 액션은 매번 LLM을 호출한다. 그대로 두면 메모를 하나 추가할 때마다 LLM 왕복이 생긴다. 그래서 데이터 모델을 기기에서 바로 바꾸는 함수를 추가한다. Button의 `functionCall` 액션으로 호출된다.

| 함수 | 인자 | 동작 |
|---|---|---|
| `setValue` | `path`, `value` | 경로에 값을 쓴다. |
| `listAppend` | `path`, `item`, `clear?`(경로 목록) | 목록 끝에 항목을 추가하고, `clear`의 경로들을 비운다(입력창 초기화). |
| `listRemove` | `path?`, `index?` | 목록에서 해당 위치 항목을 삭제한다. List 행 템플릿 안에서는 인자 없이 부르면 그 행을 지운다. |
| `toggle` | `path` | 불리언 값을 뒤집는다. |
| `increment` | `path`, `by` | 숫자를 더한다(카운터, 점수판). |

이 5개로 메모장·할 일·카운터류가 LLM 왕복 없이 동작한다. 더 필요한 함수는 실제 생성 결과를 보고 추가한다.

### 5.3 `PhysicsGame` (신규)

설정형 2D 물리 게임 위젯. 물리는 `forge2d`, 그리기는 `CustomPainter`, 루프는 `Ticker`.

```json
{
  "component": "PhysicsGame",
  "world": {"width": 10, "height": 16, "gravity": 9.8},
  "bodies": [
    {"id": "ball", "type": "ball", "x": 9.2, "y": 14, "radius": 0.25, "restitution": 0.5},
    {"id": "wallL", "type": "wall", "points": [[0, 0], [0, 16]]},
    {"id": "b1", "type": "bumper", "x": 5, "y": 4, "radius": 0.6, "score": 100},
    {"id": "fl", "type": "flipper", "side": "left", "x": 3, "y": 14.5, "length": 1.8},
    {"id": "fr", "type": "flipper", "side": "right", "x": 7, "y": 14.5, "length": 1.8}
  ],
  "controls": {"tapLeft": "flipperLeft", "tapRight": "flipperRight", "launch": "tap"},
  "rules": {"lives": 3, "loseBelow": 16, "winScore": null},
  "statePath": "/game"
}
```

| 항목 | 값 |
|---|---|
| `bodies[].type` | `ball`, `wall`(선분/다각형), `bumper`(원형, 튕김+점수), `flipper`(회전 조인트), `paddle`(드래그 이동), `brick`(맞으면 사라짐+점수), `target`(맞으면 점수) |
| `controls` | `tapLeft`/`tapRight` → 플리퍼, `drag` → 패들, `launch` → 공 발사 |
| `rules` | `lives`, `loseBelow`(이 y 아래로 떨어지면 목숨 감소), `winScore`, `winWhenNoBricks` |
| `statePath` | 점수·목숨·상태(`playing`/`won`/`lost`)를 데이터 모델에 쓴다. 다른 위젯(Text)이 바인딩해 표시한다. |

- 좌표는 월드 단위(미터)이고 위젯 크기에 맞춰 비율을 유지해 축소한다.
- 게임 종료 시 다시 시작 버튼을 위젯 안에 표시한다.
- 잘못된 설정(공 없음, 범위 밖 좌표, 알 수 없는 type)은 예외 대신 `reportError`로 LLM에 알리고 오류 안내를 그린다.
- 표현 가능: 핀볼, 벽돌깨기, 퐁류. 그 밖은 C-5에 따라 대안을 제안한다.

### 5.4 그 밖의 유틸리티 위젯

1차에서는 추가하지 않는다. 기본 카탈로그 + 5.2 함수로 부족한 것이 실제로 확인되면 추가한다.

## 6. LLM 연동

| ID | 요구사항 |
|---|---|
| L-1 | Firebase AI Logic의 Gemini Developer API(`FirebaseAI.googleAI()`)를 쓴다. |
| L-2 | 시스템 프롬프트는 `PromptBuilder.custom(catalog:, allowedOperations: createAndUpdate, systemPromptFragments:)`로 만든다. `PromptBuilder.chat`은 "매번 새 surface를 만들라"는 문구가 고정이라 R-4와 충돌한다. |
| L-7 | 요청마다 현재 데이터 모델을 덧붙여 보낸다. 기기에서 바뀐 값(메모 등)을 모델이 알아야 수정 요청 때 초기화하지 않는다. |
| L-3 | 대화 이력은 `firebase_ai`의 `ChatSession`이 관리한다. `onSend`에서 스트림 청크를 `transport.addChunk()`로 넘긴다. |
| L-4 | 시스템 프롬프트에 넣을 것: 역할, 되묻기 규칙(4장), 지원 범위와 대안 제안, 로컬 함수 우선 사용, `PhysicsGame`·`ClarifyQuestions` 예시 각 1개, 한국어 응답. |
| L-5 | LLM 호출부는 `AppGenerator` 인터페이스 뒤에 둔다. 테스트는 준비된 A2UI 텍스트를 내보내는 가짜 구현을 쓴다. |
| L-6 | 모델명은 설정 상수 한 곳에 둔다. |

## 7. 저장

| ID | 요구사항 |
|---|---|
| S-1 | 저장 단위: `SavedApp { id, name, createdAt, a2uiMessages, dataSnapshot }`. |
| S-2 | `a2uiMessages`는 LLM이 보낸 A2UI 원문 텍스트를 누적한 것. 복원 시 `addChunk()`로 재생한다. |
| S-3 | `dataSnapshot`은 저장 시점의 데이터 모델. 복원 시 재생 뒤에 덮어쓴다(메모 내용 유지). |
| S-4 | 저장된 앱을 실행 중일 때 데이터 변경은 화면을 벗어나거나 앱이 백그라운드로 갈 때 자동 저장한다. |
| S-5 | 저장소는 `shared_preferences`(JSON 문자열). 앱 수가 적은 1차 범위에 충분하다. |
| S-6 | 복원한 앱에서도 수정 요청을 보낼 수 있다. 이때 LLM에는 현재 화면 정의를 문맥으로 함께 보낸다. |

## 8. 수용 기준

| # | 시나리오 | 통과 조건 |
|---|---|---|
| A-1 | "메모장 만들어줘" | 질문 없이 생성. 메모 추가·삭제가 LLM 호출 없이 즉시 반영. |
| A-2 | A-1 저장 후 앱 재시작 | 홈 목록에서 열면 메모 내용이 남아 있다. |
| A-3 | "핀볼 게임 만들어줘" | 공 발사, 좌/우 탭으로 플리퍼 동작, 범퍼 충돌 시 점수 증가, 공 이탈 시 목숨 감소, 목숨 0이면 종료. |
| A-4 | "게임 만들어줘" | 질문 카드가 먼저 나오고, 답변 후 해당 게임이 생성된다. |
| A-5 | 실행 중 "공을 더 빠르게" | 화면이 유지된 채 설정만 바뀐다. |
| A-6 | "체스 만들어줘" | 만들 수 없다는 안내와 가능한 대안 제안. |
| A-7 | 네트워크 차단 상태에서 요청 | 오류 메시지와 재시도 버튼. |
| A-8 | `flutter analyze` 경고 0, `flutter test` 통과 | — |

## 9. 모듈 구조와 담당

```
lib/
  main.dart, firebase_options.dart
  app/                   앱 위젯, 테마, 라우팅
  features/home/         홈 화면
  features/runner/       실행 화면
  ai/                    app_generator.dart(인터페이스), firebase_app_generator.dart, system_prompt.dart
  catalog/
    app_catalog.dart     카탈로그 조립 지점
    clarify_questions.dart
    data_functions.dart  5.2 함수
    game/                physics_game_item.dart, game_spec.dart, game_world.dart, game_painter.dart
  storage/               saved_app.dart, saved_app_repository.dart
test/                    lib과 같은 구조
```

| 에이전트 | 담당 범위 | 수정 가능 경로 |
|---|---|---|
| A. 앱 셸 | 3장 | `lib/app/`, `lib/features/`, `test/features/` |
| B. AI 계층 | 4장, 6장 | `lib/ai/`, `lib/catalog/clarify_questions.dart`, `test/ai/`, `test/catalog/clarify_questions_test.dart` |
| C. 게임 엔진 | 5.3 | `lib/catalog/game/`, `test/catalog/game/` |
| D. 저장·함수 | 5.2, 7장 | `lib/storage/`, `lib/catalog/data_functions.dart`, `test/storage/`, `test/catalog/data_functions_test.dart` |

공용 계약(`AppGenerator`, `SavedApp`, `SavedAppRepository` 인터페이스, `app_catalog.dart`의 등록 지점)은 병렬 작업 전에 먼저 작성하고, 통합(`main.dart`, 카탈로그 조립, 화면 연결)은 병렬 작업 뒤에 한다.

## 10. 검증된 사실과 남은 위험

### 소스와 실행으로 확인한 것 (genui 0.10.4)

- `SurfaceController(catalogs: [...])`, `A2uiTransportAdapter(onSend:)` + `addChunk()`, `Conversation(controller:, transport:)`, `Surface(surfaceContext: controller.contextFor(id))`.
- `Catalog.copyWith(newItems:, newFunctions:)`. (pub.dev README의 `CoreCatalogItems`, `Surface(host:)`는 이 버전에 없다.)
- A2UI 메시지는 응답 텍스트 안의 ```` ```json ```` 블록으로 온다. `createSurface` → `updateDataModel` → `updateComponents`.
- List는 `{"componentId", "path"}` 템플릿으로 데이터 모델의 배열에 바인딩된다.
- Button `event` 액션은 `Conversation`을 통해 자동으로 `onSend`를 다시 호출한다.
- 가짜 응답으로 메모장 화면이 위젯 테스트와 에뮬레이터 `genui_test` 양쪽에서 렌더됐다.

### 아직 확인하지 못한 것

| 위험 | 확인 방법 | 대안 |
|---|---|---|
| Gemini Developer API가 결제 계정 없이 동작하는지, 사용할 모델명 | Firebase 연결 후 실제 호출 | 모델명 교체, 필요 시 Blaze 전환 논의 |
| Gemini가 긴 `PhysicsGame` JSON을 스키마에 맞게 생성하는지 | 실제 호출 + 프롬프트 예시 조정 | 스키마 단순화, 프리셋(예: `preset: "pinball"`) + 덮어쓰기 방식 |
| `dataModel.getValue(DataPath.root)`로 전체 스냅샷을 얻을 수 있는지 | D 에이전트 착수 시 테스트 | `sendDataModel`로 전송되는 값을 가로채 저장 |
| 저장된 A2UI 원문 재생이 항상 같은 화면을 만드는지 | D 에이전트 테스트 | 원문 대신 최종 `SurfaceDefinition`을 직렬화 |
| `forge2d` 회전 조인트로 플리퍼 조작감이 충분한지 | C 에이전트 프로토타입 | 플리퍼를 키네마틱 바디로 직접 회전 |
| Firebase 플러그인의 KGP 경고(빌드 시 출력) | 현재는 경고만, 빌드 성공 | 플러그인 버전 업데이트 대기 |
