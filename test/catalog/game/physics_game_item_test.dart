import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:genui/test.dart';
import 'package:genui_app_maker/catalog/game/game_painter.dart';
import 'package:genui_app_maker/catalog/game/game_spec.dart';
import 'package:genui_app_maker/catalog/game/game_world.dart';
import 'package:genui_app_maker/catalog/game/physics_game_item.dart';

const _catalogId =
    'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';

Catalog gameCatalog() =>
    BasicCatalogItems.asNoAssetCatalog().copyWith(newItems: [physicsGameItem]);

/// genui wiring without an LLM: A2UI text goes straight into the transport.
class Harness {
  Harness() {
    controller = SurfaceController(catalogs: [gameCatalog()]);
    transport = A2uiTransportAdapter(
      onSend: (message) async => sent.add(message),
    );
    conversation = Conversation(controller: controller, transport: transport);
  }

  late final SurfaceController controller;
  late final A2uiTransportAdapter transport;
  late final Conversation conversation;

  /// Messages genui sent back toward the LLM (events, reported errors).
  final List<ChatMessage> sent = [];

  DataModel get dataModel => controller.contextFor('main').dataModel;

  void create() => _add({
    'createSurface': {'surfaceId': 'main', 'catalogId': _catalogId},
  });

  void components(List<Object?> components) => _add({
    'updateComponents': {'surfaceId': 'main', 'components': components},
  });

  void _add(Map<String, Object?> message) => transport.addChunk(
    '```json\n${jsonEncode({'version': 'v0.9', ...message})}\n```\n',
  );

  Widget widget({bool scrollable = false}) {
    final surface = Surface(surfaceContext: controller.contextFor('main'));
    return MaterialApp(
      home: Scaffold(
        body: scrollable ? SingleChildScrollView(child: surface) : surface,
      ),
    );
  }

  void dispose() {
    conversation.dispose();
    transport.dispose();
    controller.dispose();
  }
}

/// A game whose ball drops straight out of the world: 2 lives, no walls.
Map<String, Object?> drainGame({double gravity = 9.8}) => {
  'id': 'root',
  'component': 'PhysicsGame',
  'world': {'width': 10, 'height': 16, 'gravity': gravity},
  'bodies': [
    {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 15},
  ],
  'rules': {'lives': 2},
  'statePath': '/game',
};

/// Lets the ticker run for [seconds] of fake time, one frame at a time.
Future<void> play(WidgetTester tester, double seconds) async {
  final frames = (seconds * 60).round();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

/// Unmounts the game so its ticker and native world are released.
Future<void> unmount(WidgetTester tester, Harness harness) async {
  await tester.pumpWidget(const SizedBox());
  harness.dispose();
}

void main() {
  test('catalog item is named PhysicsGame and has a valid example', () async {
    expect(physicsGameItem.name, 'PhysicsGame');
    expect(physicsGameItem.exampleData, isNotEmpty);

    final errors = await validateCatalogItemExamples(
      physicsGameItem,
      gameCatalog(),
    );
    expect(errors, isEmpty);

    // The example must also be playable according to our own validation.
    final components = (jsonDecode(physicsGameItem.exampleData.first()) as List)
        .cast<Map<String, Object?>>();
    final game = components.singleWhere((c) => c['component'] == 'PhysicsGame');
    expect(GameSpec.fromJson(game).problems, isEmpty);
  });

  test('schema describes every body type and control', () {
    final schema = jsonEncode(physicsGameItem.dataSchema.value);
    for (final kind in BodyKind.values) {
      expect(schema, contains('"${kind.name}"'));
    }
    for (final key in [
      'world',
      'bodies',
      'controls',
      'rules',
      'statePath',
      'tapLeft',
      'tapRight',
      'drag',
      'launch',
      'lives',
      'loseBelow',
      'winScore',
      'winWhenNoBricks',
    ]) {
      expect(schema, contains('"$key"'));
    }
  });

  test('example table: launched ball reaches the playfield and scores', () {
    final components = (jsonDecode(pinballExample) as List)
        .cast<Map<String, Object?>>();
    final world = GameWorld(
      GameSpec.fromJson(
        components.singleWhere((c) => c['component'] == 'PhysicsGame'),
      ),
    );
    addTearDown(world.dispose);
    final ball = world.bodyById('ball')!;

    expect(world.hasHeldBall, isTrue);
    expect(world.launchBall(), isTrue);
    var leftLane = false;
    for (var i = 0; i < 120 * 20 && world.lives == 3; i++) {
      world.step(GameWorld.fixedDt);
      if (ball.x < 8.5) leftLane = true;
    }
    expect(leftLane, isTrue, reason: 'the ball must leave the launch lane');
  });

  testWidgets('renders through a genui Surface and writes state to statePath', (
    tester,
  ) async {
    final harness = Harness();
    await tester.pumpWidget(harness.widget());
    harness
      ..create()
      ..components([
        {
          'id': 'root',
          'component': 'Column',
          'children': ['score', 'game'],
        },
        {
          'id': 'score',
          'component': 'Text',
          'text': {'path': '/game/status'},
        },
        {...drainGame(), 'id': 'game'},
      ]);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(PhysicsGameView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PhysicsGameView),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
    expect(harness.dataModel.getValue<Object?>(DataPath('/game')), {
      'score': 0,
      'lives': 2,
      'status': 'playing',
    });
    // Another generated widget bound to the state sees it.
    expect(find.text('playing'), findsOneWidget);

    // The game keeps the world aspect ratio and fits inside the screen.
    final size = tester.getSize(find.byType(CustomPaint).last);
    expect(size.width / size.height, closeTo(10 / 16, 0.01));
    expect(size.height, lessThanOrEqualTo(600));

    // The ball falls out: one life is lost and written to the data model.
    await play(tester, 1);
    expect(harness.dataModel.getValue<int>(DataPath('/game/lives')), 1);
    expect(
      harness.dataModel.getValue<String>(DataPath('/game/status')),
      'playing',
    );

    // Second drain: game over, restart button appears inside the widget.
    await play(tester, 1);
    expect(harness.dataModel.getValue<Object?>(DataPath('/game')), {
      'score': 0,
      'lives': 0,
      'status': 'lost',
    });
    expect(find.text('게임 오버'), findsOneWidget);
    expect(find.text('lost'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('다시 시작'));
    await tester.pump();
    expect(find.text('게임 오버'), findsNothing);
    expect(harness.dataModel.getValue<Object?>(DataPath('/game')), {
      'score': 0,
      'lives': 2,
      'status': 'playing',
    });

    await unmount(tester, harness);
  });

  testWidgets('does not write state every frame', (tester) async {
    final writes = <GameStateSnapshot>[];
    final spec = GameSpec.fromJson({
      'bodies': [
        {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 1},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PhysicsGameView(spec: spec, onStateChanged: writes.add),
      ),
    );
    await play(tester, 0.5);
    expect(writes, hasLength(1));
    expect(writes.single.toJson(), {
      'score': 0,
      'lives': 3,
      'status': 'playing',
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sizes itself from width when height is unbounded', (
    tester,
  ) async {
    final harness = Harness();
    await tester.pumpWidget(harness.widget(scrollable: true));
    harness
      ..create()
      ..components([drainGame(gravity: 0)]);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(PhysicsGameView));
    // Test screen is 800 x 600: capped to 75% of the height, 10:16 ratio.
    expect(size.height, closeTo(450, 0.5));
    final painted = tester.getSize(find.byType(CustomPaint).last);
    expect(painted.width / painted.height, closeTo(10 / 16, 0.01));

    await unmount(tester, harness);
  });

  testWidgets('invalid config shows the error panel and reports once', (
    tester,
  ) async {
    final harness = Harness();
    await tester.pumpWidget(harness.widget());
    harness
      ..create()
      ..components([
        {
          'id': 'root',
          'component': 'PhysicsGame',
          'bodies': [
            {'id': 'b1', 'type': 'bumper', 'x': 50, 'y': 4},
          ],
        },
      ]);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(GameErrorPanel), findsOneWidget);
    expect(find.byType(PhysicsGameView), findsNothing);
    expect(find.text('게임 설정에 문제가 있어요'), findsOneWidget);
    expect(find.textContaining('outside the world'), findsOneWidget);
    expect(find.textContaining('type "ball"'), findsOneWidget);

    // The problems went back toward the LLM exactly once, even after rebuilds.
    await tester.pumpWidget(harness.widget());
    await tester.pump();
    final reports = harness.sent
        .expand((message) => message.parts)
        .whereType<DataPart>()
        .map((part) => utf8.decode(part.bytes))
        .where((text) => text.contains('Invalid PhysicsGame config'))
        .toList();
    expect(reports, hasLength(1));
    expect(reports.single, contains('VALIDATION_FAILED'));
    expect(reports.single, contains('outside the world'));
    expect(reports.single, contains('at least one body of type'));

    await unmount(tester, harness);
  });

  testWidgets('an updated config rebuilds the world', (tester) async {
    final harness = Harness();
    await tester.pumpWidget(harness.widget());
    harness
      ..create()
      ..components([drainGame()]);
    await tester.pump();
    await tester.pump();
    await play(tester, 1);
    expect(harness.dataModel.getValue<int>(DataPath('/game/lives')), 1);

    // The LLM sends a new config ("no gravity, 5 lives").
    harness.components([
      {
        ...drainGame(gravity: 0),
        'rules': {'lives': 5},
      },
    ]);
    await tester.pump();
    await tester.pump();
    expect(harness.dataModel.getValue<int>(DataPath('/game/lives')), 5);
    await play(tester, 1);
    expect(harness.dataModel.getValue<int>(DataPath('/game/lives')), 5);
    expect(tester.takeException(), isNull);

    // And an invalid update swaps in the error panel without throwing.
    harness.components([
      {'id': 'root', 'component': 'PhysicsGame', 'bodies': <Object?>[]},
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.byType(GameErrorPanel), findsOneWidget);
    expect(tester.takeException(), isNull);

    await unmount(tester, harness);
  });

  group('controls', () {
    /// Pumps a standalone game filling an 800 x 600 screen: the 375 x 600
    /// table is centred, so its left half is x < 400.
    Future<GameWorld> pumpGame(
      WidgetTester tester,
      Map<String, Object?> json,
    ) async {
      final spec = GameSpec.fromJson(json);
      expect(spec.problems, isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PhysicsGameView(spec: spec)),
        ),
      );
      await tester.pump();
      final painter =
          tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter!
              as GamePainter;
      return painter.world;
    }

    Map<String, Object?> pinball({Map<String, Object?>? controls}) => {
      'world': {'gravity': 0},
      'bodies': [
        {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
        {'id': 'fl', 'type': 'flipper', 'side': 'left', 'x': 3, 'y': 14},
        {'id': 'fr', 'type': 'flipper', 'side': 'right', 'x': 7, 'y': 14},
      ],
      'controls':
          controls ?? {'tapLeft': 'flipperLeft', 'tapRight': 'flipperRight'},
    };

    final rest = degreesToRadians(30);

    testWidgets('holding the left / right half drives that flipper', (
      tester,
    ) async {
      final world = await pumpGame(tester, pinball());
      final left = world.bodyById('fl')!;
      final right = world.bodyById('fr')!;
      await play(tester, 0.2);
      expect(left.angle, closeTo(rest, 0.05));

      final leftFinger = await tester.startGesture(
        const Offset(300, 300),
        pointer: 1,
      );
      await play(tester, 0.3);
      expect(left.angle, closeTo(-rest, 0.05), reason: 'left is up');
      expect(right.angle, closeTo(-rest, 0.05), reason: 'right is resting');

      // Multi-touch: a second finger on the right half raises the other one.
      final rightFinger = await tester.startGesture(
        const Offset(500, 300),
        pointer: 2,
      );
      await play(tester, 0.3);
      expect(left.angle, closeTo(-rest, 0.05));
      expect(right.angle, closeTo(rest, 0.05), reason: 'right is up');

      await leftFinger.up();
      await play(tester, 0.4);
      expect(left.angle, closeTo(rest, 0.05), reason: 'left fell back');
      expect(right.angle, closeTo(rest, 0.05), reason: 'right still held');

      await rightFinger.up();
      await play(tester, 0.4);
      expect(right.angle, closeTo(-rest, 0.05));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('controls that are not configured are ignored', (tester) async {
      final world = await pumpGame(
        tester,
        pinball(controls: {'tapRight': 'flipperRight'}),
      );
      final finger = await tester.startGesture(const Offset(300, 300));
      await play(tester, 0.3);
      expect(world.bodyById('fl')!.angle, closeTo(rest, 0.05));
      expect(world.bodyById('fr')!.angle, closeTo(-rest, 0.05));
      await finger.up();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tap launches a waiting ball and hides the hint', (
      tester,
    ) async {
      final world = await pumpGame(tester, {
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 14},
        ],
        'controls': {'launch': 'tap'},
      });
      final ball = world.bodyById('ball')!;
      await play(tester, 0.3);
      expect(ball.y, 14);
      expect(find.textContaining('탭해서'), findsOneWidget);

      await tester.tapAt(const Offset(400, 300));
      await play(tester, 0.3);
      expect(ball.y, lessThan(11));
      expect(find.textContaining('탭해서'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('drag moves the paddle to the finger', (tester) async {
      final world = await pumpGame(tester, {
        'world': {'gravity': 0},
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
          {'id': 'paddle', 'type': 'paddle', 'x': 5, 'y': 14},
        ],
        'controls': {'drag': 'paddle'},
      });
      final paddle = world.bodyById('paddle')!;

      // Table spans x = 212.5 .. 587.5 px (37.5 px per metre).
      final finger = await tester.startGesture(const Offset(400, 500));
      await finger.moveTo(const Offset(212.5 + 37.5 * 7, 500));
      await play(tester, 0.4);
      expect(paddle.x, closeTo(7, 0.05));

      await finger.moveTo(const Offset(0, 500));
      await play(tester, 0.5);
      expect(paddle.x, closeTo(1, 0.05), reason: 'clamped to the world');
      await finger.up();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('game does not let an ancestor scroll view steal drags', (
      tester,
    ) async {
      final spec = GameSpec.fromJson({
        'world': {'gravity': 0},
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
        ],
      });
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  PhysicsGameView(spec: spec),
                  const SizedBox(height: 1000),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.dragFrom(
        const Offset(400, 300),
        const Offset(0, -200),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(scroll.offset, 0);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
