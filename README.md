# genui_app_maker

"메모장 만들어줘", "핀볼 게임 만들어줘"처럼 한 문장을 입력하면 그 자리에서 쓸 수 있는 앱 화면을 만들어 주는 Flutter 앱입니다. Flutter [`genui`](https://pub.dev/packages/genui) 패키지와 Gemini(Firebase AI Logic)를 사용합니다.

- LLM은 코드를 생성하지 않고, 등록된 위젯 카탈로그를 조합합니다.
- 요청이 모호하면 만들기 전에 질문 카드로 되묻습니다.
- 게임은 설정형 2D 물리 게임 위젯 `PhysicsGame`으로 만듭니다(핀볼, 벽돌깨기, 퐁류).
- 메모 추가·삭제 같은 조작은 LLM 호출 없이 기기에서 처리합니다.
- 만든 앱은 저장해 두었다가 다시 열 수 있습니다.

자세한 요구사항과 설계는 [docs/SPEC.md](docs/SPEC.md)에 있습니다.

## 실행

대상 플랫폼은 Android입니다. (`genui`는 Windows·Linux 데스크톱을 지원하지 않습니다.)

### Firebase 없이 (데모 모드)

정해진 응답을 내보내는 생성기로 화면과 게임, 저장 흐름을 확인할 수 있습니다.

```
flutter run --dart-define=DEMO_LLM=true
```

`lib/firebase_options.dart`가 없으면 컴파일되지 않으므로, 데모 모드만 쓰더라도 아래 1~2단계는 필요합니다.

### 실제 Gemini 사용

Firebase 설정 파일(`lib/firebase_options.dart`, `android/app/google-services.json`)은 저장소에 포함하지 않습니다. 직접 생성해야 합니다.

1. Firebase 프로젝트를 만들고 [Firebase CLI](https://firebase.google.com/docs/cli)로 로그인합니다.
2. FlutterFire CLI로 설정 파일을 생성합니다.
   ```
   dart pub global activate flutterfire_cli
   flutterfire configure --platforms=android
   ```
3. Firebase 콘솔의 AI Logic에서 **Gemini Developer API**를 활성화합니다. 반영에 몇 분 걸릴 수 있습니다.
4. `flutter run`

모델 이름은 `lib/ai/firebase_app_generator.dart`의 `kGeminiModel`에서 바꿉니다.

## 테스트

```
flutter analyze
flutter test
```

## 구조

```
lib/
  main.dart               의존성 조립
  app/                    앱 위젯, 테마
  features/home/          프롬프트 입력, 저장된 앱 목록
  features/runner/        생성된 앱 실행 화면
  ai/                     LLM 경계(AppGenerator), genui 배선(AppSession), 시스템 프롬프트
  catalog/                LLM이 쓸 수 있는 위젯과 함수
    game/                 PhysicsGame (forge2d)
  storage/                저장된 앱
```
