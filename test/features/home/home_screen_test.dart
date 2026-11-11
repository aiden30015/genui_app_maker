import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui_app_maker/app/app.dart';
import 'package:genui_app_maker/features/home/home_screen.dart';
import 'package:genui_app_maker/features/runner/runner_screen.dart';

import '../support.dart';

void main() {
  late InMemoryRepository repository;
  late SessionHarness harness;

  setUp(() {
    repository = InMemoryRepository();
    harness = SessionHarness([notesResponse]);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      GenuiAppMaker(repository: repository, createSession: harness.create),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty or whitespace input does nothing', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('만들기'));
    await tester.pumpAndSettle();
    expect(find.byType(RunnerScreen), findsNothing);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('만들기'));
    await tester.pumpAndSettle();
    expect(find.byType(RunnerScreen), findsNothing);
    expect(harness.sessions, isEmpty);
  });

  testWidgets('typing a prompt and tapping create opens the runner', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.enterText(find.byType(TextField), '  가계부 만들어줘 ');
    await tester.tap(find.text('만들기'));
    await tester.pumpAndSettle();

    expect(find.byType(RunnerScreen), findsOneWidget);
    expect(harness.generator.requests, hasLength(1));
    expect(harness.generator.requests.single.text, '가계부 만들어줘');
  });

  testWidgets('example chip starts generation immediately', (tester) async {
    await pumpApp(tester);

    for (final String example in examplePrompts) {
      expect(find.widgetWithText(ActionChip, example), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(ActionChip, '핀볼 게임 만들어줘'));
    await tester.pumpAndSettle();

    expect(find.byType(RunnerScreen), findsOneWidget);
    expect(harness.generator.requests.single.text, '핀볼 게임 만들어줘');
  });

  testWidgets('shows the empty state when nothing is saved', (tester) async {
    await pumpApp(tester);

    expect(find.textContaining('아직 저장된 앱이 없습니다'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('lists saved apps in repository order with name and date', (
    tester,
  ) async {
    repository.apps.addAll([
      savedNotes(id: '2', name: '새 앱', createdAt: DateTime(2026, 11, 10)),
      savedNotes(id: '1', name: '옛 앱', createdAt: DateTime(2026, 1, 5)),
    ]);
    await pumpApp(tester);

    expect(find.text('2026.11.10'), findsOneWidget);
    expect(find.text('2026.01.05'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('새 앱')).dy,
      lessThan(tester.getTopLeft(find.text('옛 앱')).dy),
    );
    expect(find.textContaining('아직 저장된 앱이 없습니다'), findsNothing);
  });

  testWidgets('tapping a saved app restores it in the runner', (tester) async {
    repository.apps.add(savedNotes());
    await pumpApp(tester);

    await tester.tap(find.text('내 메모'));
    await tester.pumpAndSettle();

    expect(find.byType(RunnerScreen), findsOneWidget);
    expect(find.text('저장해 둔 메모'), findsOneWidget);
    expect(harness.generator.requests, isEmpty);
  });

  testWidgets('long-press then confirm deletes the app', (tester) async {
    repository.apps.add(savedNotes());
    await pumpApp(tester);

    await tester.longPress(find.text('내 메모'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(repository.apps, isEmpty);
    expect(find.text('내 메모'), findsNothing);
    expect(find.textContaining('아직 저장된 앱이 없습니다'), findsOneWidget);
  });

  testWidgets('long-press then cancel keeps the app', (tester) async {
    repository.apps.add(savedNotes());
    await pumpApp(tester);

    await tester.longPress(find.text('내 메모'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    expect(repository.apps, hasLength(1));
    expect(find.text('내 메모'), findsOneWidget);
  });

  testWidgets('repository failure shows an error with retry', (tester) async {
    repository.failList = true;
    await pumpApp(tester);

    expect(find.text('저장된 앱을 불러오지 못했습니다.'), findsOneWidget);

    repository
      ..failList = false
      ..apps.add(savedNotes());
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('내 메모'), findsOneWidget);
  });

  testWidgets('list refreshes after returning from the runner', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.widgetWithText(ActionChip, '메모장 만들어줘'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(RunnerScreen), findsNothing);
    expect(find.widgetWithText(ListTile, '메모장 만들어줘'), findsOneWidget);
  });
}
