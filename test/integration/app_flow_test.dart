// 통합 검증: 실제 카탈로그 + 앱 셸 + 데모 생성기로 SPEC 8장의 흐름을 확인한다.
// (실제 Gemini 호출은 여기서 검증하지 않는다.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:genui_app_maker/ai/app_session.dart';
import 'package:genui_app_maker/ai/demo_app_generator.dart';
import 'package:genui_app_maker/ai/system_prompt.dart';
import 'package:genui_app_maker/app/app.dart';
import 'package:genui_app_maker/catalog/app_catalog.dart';
import 'package:genui_app_maker/catalog/game/physics_game_item.dart';
import 'package:genui_app_maker/storage/in_memory_saved_app_repository.dart';

void main() {
  late InMemorySavedAppRepository repository;
  late List<DemoAppGenerator> generators;

  Widget app() {
    final Catalog catalog = buildAppCatalog();
    return GenuiAppMaker(
      repository: repository,
      createSession: () {
        final generator = DemoAppGenerator();
        generators.add(generator);
        return AppSession(catalog: catalog, generator: generator);
      },
    );
  }

  /// 게임이 돌면 Ticker 때문에 pumpAndSettle이 끝나지 않아 시간을 직접 흘린다.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  setUp(() {
    repository = InMemorySavedAppRepository();
    generators = [];
  });

  test('catalog and system prompt include the custom vocabulary', () {
    final Catalog catalog = buildAppCatalog();
    final names = catalog.items.map((i) => i.name).toSet();
    expect(names, containsAll(['ClarifyQuestions', 'PhysicsGame', 'Button']));
    expect(names, isNot(contains('Video')));
    expect(
      catalog.functions.map((f) => f.name),
      containsAll([
        'setValue',
        'listAppend',
        'listRemove',
        'toggle',
        'increment',
      ]),
    );

    final String prompt = buildSystemPrompt(catalog);
    for (final word in ['PhysicsGame', 'ClarifyQuestions', 'listAppend']) {
      expect(prompt, contains(word));
    }
    // 프롬프트 크기를 기록해 둔다(토큰이 아니라 문자 수).
    printOnFailure('system prompt chars: ${prompt.length}');
    expect(prompt.length, lessThan(120000));
  });

  testWidgets('A-1/A-2: notes app works locally, saves and restores', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('메모장 만들어줘'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('첫 메모'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '새 메모'), '우유 사기');
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();
    expect(find.text('우유 사기'), findsOneWidget);

    await tester.tap(find.byTooltip('저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect((await repository.list()).single.transcript, contains('메모장'));

    // 저장 뒤에 바꾼 내용은 앱이 백그라운드로 갈 때 자동 저장된다(S-4).
    await tester.tap(find.text('삭제').first);
    await tester.pumpAndSettle();
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(
      (await repository.list()).single.data.toString(),
      isNot(contains('첫 메모')),
    );
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 저장 이름이 예시 칩과 같은 문구라 목록 쪽(뒤에 그려진 것)을 고른다.
    await tester.tap(find.text((await repository.list()).single.name).last);
    await tester.pumpAndSettle();
    expect(find.text('우유 사기'), findsOneWidget);
    expect(find.text('첫 메모'), findsNothing);
  });

  testWidgets('A-3: pinball prompt renders a running PhysicsGame', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('핀볼 게임 만들어줘'));
    await settle(tester);

    expect(find.byType(PhysicsGameView), findsOneWidget);
    final Size size = tester.getSize(find.byType(PhysicsGameView));
    expect(size.height, greaterThan(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('A-4: ambiguous prompt asks first, then builds', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '게임 만들어줘');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    if (find.text('어떤 게임을 만들까요?').evaluate().isEmpty) {
      // 입력창이 done 액션으로 전송하지 않는 경우 버튼으로 보낸다.
      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
    expect(find.text('어떤 게임을 만들까요?'), findsOneWidget);
    expect(find.byType(PhysicsGameView), findsNothing);

    await tester.tap(find.text('핀볼'));
    await tester.pump();
    await tester.tap(find.text('만들기'));
    await settle(tester);

    expect(find.byType(PhysicsGameView), findsOneWidget);
    expect(find.text('어떤 게임을 만들까요?'), findsNothing);
  });
}
