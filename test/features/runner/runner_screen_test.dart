import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:genui_app_maker/ai/app_session.dart';
import 'package:genui_app_maker/features/runner/error_message.dart';
import 'package:genui_app_maker/features/runner/runner_screen.dart';
import 'package:genui_app_maker/features/runner/surface_view.dart';
import 'package:genui_app_maker/storage/saved_app.dart';

import '../support.dart';

/// 실행 화면을 "열기" 버튼 뒤에 둬서 뒤로 가기를 시험할 수 있게 한다.
Widget host(RunnerScreen screen) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => screen)),
          child: const Text('열기'),
        ),
      ),
    ),
  ),
);

void main() {
  late InMemoryRepository repository;
  late SessionHarness harness;

  setUp(() {
    repository = InMemoryRepository();
    harness = SessionHarness([notesResponse, renameResponse]);
  });

  Future<void> open(WidgetTester tester, RunnerScreen screen) async {
    await tester.pumpWidget(host(screen));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Future<void> openNew(WidgetTester tester) => open(
    tester,
    RunnerScreen.create(
      prompt: '메모장 만들어줘',
      repository: repository,
      createSession: harness.create,
    ),
  );

  Future<void> openSaved(WidgetTester tester, SavedApp app) => open(
    tester,
    RunnerScreen.restore(
      savedApp: app,
      repository: repository,
      createSession: harness.create,
    ),
  );

  Finder inputField() => find.widgetWithText(TextField, '수정할 내용을 입력하세요');

  testWidgets('new prompt renders the generated notes surface', (tester) async {
    await openNew(tester);

    expect(find.byType(Surface), findsOneWidget);
    expect(find.text('메모장'), findsOneWidget);
    expect(find.text('첫 메모'), findsOneWidget);
    expect(harness.generator.requests.single.text, '메모장 만들어줘');
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the model text in a dismissible banner', (tester) async {
    await openNew(tester);

    expect(find.text('메모장을 만들었습니다.'), findsOneWidget);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('메모장을 만들었습니다.'), findsNothing);
  });

  testWidgets('shows progress while waiting and disables input and save', (
    tester,
  ) async {
    final generator = GatedGenerator(notesResponse);
    await tester.pumpWidget(
      MaterialApp(
        home: RunnerScreen.create(
          prompt: '메모장 만들어줘',
          repository: repository,
          createSession: () => AppSession(
            catalog: BasicCatalogItems.asNoAssetCatalog(),
            generator: generator,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('만드는 중…'), findsOneWidget);
    expect(tester.widget<TextField>(inputField()).enabled, isFalse);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.save_outlined),
          )
          .onPressed,
      isNull,
    );

    generator.release();
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('만드는 중…'), findsNothing);
    expect(find.text('첫 메모'), findsOneWidget);
    expect(tester.widget<TextField>(inputField()).enabled, isTrue);
  });

  testWidgets('modification request sends a second request', (tester) async {
    await openNew(tester);

    await tester.enterText(inputField(), '제목을 내 메모장으로 바꿔줘');
    await tester.tap(find.byTooltip('보내기'));
    await tester.pumpAndSettle();

    expect(harness.generator.requests, hasLength(2));
    // 요청 끝에는 AppSession이 현재 데이터 모델을 덧붙인다.
    expect(harness.generator.requests.last.text, startsWith('제목을 내 메모장으로 바꿔줘'));
    expect(find.text('내 메모장'), findsOneWidget);
    expect(find.text('첫 메모'), findsOneWidget);
    expect(find.text('제목을 바꿨습니다.'), findsOneWidget);
    expect(tester.widget<TextField>(inputField()).controller!.text, isEmpty);
  });

  testWidgets('empty modification request is not sent', (tester) async {
    await openNew(tester);

    await tester.enterText(inputField(), '   ');
    await tester.tap(find.byTooltip('보내기'));
    await tester.pumpAndSettle();

    expect(harness.generator.requests, hasLength(1));
  });

  testWidgets('error shows a Korean message and retry succeeds', (
    tester,
  ) async {
    harness.firstError = StateError('offline');
    await openNew(tester);

    expect(find.text(describeError(StateError('offline'))), findsOneWidget);
    expect(find.textContaining('네트워크'), findsOneWidget);
    expect(find.byType(Surface), findsNothing);
    expect(harness.generator.requests, hasLength(1));

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(harness.generator.requests, hasLength(2));
    expect(harness.generator.requests.last.text, '메모장 만들어줘');
    expect(find.text('다시 시도'), findsNothing);
    expect(find.text('첫 메모'), findsOneWidget);
  });

  testWidgets('save asks for a name and stores transcript and data', (
    tester,
  ) async {
    await openNew(tester);

    await tester.tap(find.byTooltip('저장'));
    await tester.pumpAndSettle();
    final Finder nameField = find.widgetWithText(TextField, '앱 이름');
    expect(tester.widget<TextField>(nameField).controller!.text, '메모장 만들어줘');
    await tester.enterText(nameField, '내 메모');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final SavedApp saved = repository.saved.single;
    expect(saved.name, '내 메모');
    expect(saved.prompt, '메모장 만들어줘');
    expect(saved.id, isNotEmpty);
    expect(saved.transcript, contains('createSurface'));
    expect(saved.data['main'], {
      'draft': '',
      'notes': [
        {'text': '첫 메모'},
      ],
    });
    expect(find.text('내 메모'), findsOneWidget);

    // 두 번째 저장은 이름을 묻지 않고 같은 id를 덮어쓴다.
    await tester.tap(find.byTooltip('저장'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.saved, hasLength(2));
    expect(repository.saved.last.id, saved.id);
    expect(repository.saved.last.name, '내 메모');
    expect(repository.saved.last.createdAt, saved.createdAt);
    expect(repository.apps, hasLength(1));
  });

  testWidgets('cancelling the name dialog saves nothing', (tester) async {
    await openNew(tester);

    await tester.tap(find.byTooltip('저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    expect(repository.saved, isEmpty);
  });

  testWidgets('opening a saved app restores UI and data without requests', (
    tester,
  ) async {
    await openSaved(tester, savedNotes());

    expect(find.text('메모장'), findsOneWidget);
    expect(find.text('저장해 둔 메모'), findsOneWidget);
    expect(find.text('내 메모'), findsOneWidget);
    expect(harness.generator.requests, isEmpty);
    expect(harness.generator.primedTranscript, contains('createSurface'));
    // 재생된 예전 응답의 안내 텍스트는 다시 띄우지 않는다.
    expect(find.text('메모장을 만들었습니다.'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a restored app still accepts modification requests', (
    tester,
  ) async {
    harness = SessionHarness([renameResponse]);
    await openSaved(tester, savedNotes());

    await tester.enterText(inputField(), '제목을 바꿔줘');
    await tester.tap(find.byTooltip('보내기'));
    await tester.pumpAndSettle();

    expect(harness.generator.requests.single.text, startsWith('제목을 바꿔줘'));
    expect(find.text('내 메모장'), findsOneWidget);
    expect(find.text('저장해 둔 메모'), findsOneWidget);
  });

  testWidgets('leaving a saved app auto-saves changed data', (tester) async {
    final SavedApp original = savedNotes();
    repository.apps.add(original);
    await openSaved(tester, original);

    harness.session.contextFor('main').dataModel.update(DataPath('/notes'), [
      {'text': '첫 메모'},
      {'text': '나가기 전에 쓴 메모'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('나가기 전에 쓴 메모'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(RunnerScreen), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    final SavedApp saved = repository.saved.single;
    expect(saved.id, original.id);
    expect(saved.name, original.name);
    expect(saved.createdAt, original.createdAt);
    expect(saved.transcript, contains('createSurface'));
    expect((saved.data['main']! as Map)['notes'], [
      {'text': '첫 메모'},
      {'text': '나가기 전에 쓴 메모'},
    ]);
  });

  testWidgets('leaving an unsaved generated app asks for confirmation', (
    tester,
  ) async {
    await openNew(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('저장하지 않고 나갈까요?'), findsOneWidget);

    await tester.tap(find.text('계속 사용'));
    await tester.pumpAndSettle();
    expect(find.byType(RunnerScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('나가기'));
    await tester.pumpAndSettle();

    expect(find.byType(RunnerScreen), findsNothing);
    expect(repository.saved, isEmpty);
  });

  testWidgets('leaving with nothing generated does not ask', (tester) async {
    harness.firstError = StateError('offline');
    await openNew(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(RunnerScreen), findsNothing);
  });

  testWidgets('a form taller than the screen scrolls instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final notes = [
      for (var i = 0; i < 30; i++) {'text': '메모 $i'},
    ];
    await openSaved(
      tester,
      savedNotes(
        data: {
          'main': {'draft': '', 'notes': notes},
        },
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('메모 0'), findsOneWidget);
    await tester.drag(find.byType(SurfaceView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomLeft(find.text('메모 29')).dy,
      lessThanOrEqualTo(tester.getTopLeft(inputField()).dy),
    );
  });

  test('needsBoundedHeight picks bounded layout for games and weights', () {
    SurfaceDefinition definition(Map<String, Object?> extra) =>
        SurfaceDefinition.fromJson({
          'surfaceId': 'main',
          'components': {
            'root': {
              'id': 'root',
              'component': 'Column',
              'children': ['child'],
            },
            'child': {'id': 'child', ...extra},
          },
        });

    expect(needsBoundedHeight(null), isFalse);
    expect(
      needsBoundedHeight(definition({'component': 'Text', 'text': 'a'})),
      isFalse,
    );
    expect(
      needsBoundedHeight(definition({'component': 'PhysicsGame'})),
      isTrue,
    );
    expect(
      needsBoundedHeight(
        definition({'component': 'Text', 'text': 'a', 'weight': 1}),
      ),
      isTrue,
    );
  });
}
