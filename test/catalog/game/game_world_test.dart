import 'package:flutter_test/flutter_test.dart';
import 'package:genui_app_maker/catalog/game/game_spec.dart';
import 'package:genui_app_maker/catalog/game/game_world.dart';

/// Builds a world from a config and disposes it when the test ends.
GameWorld worldOf(Map<String, Object?> json) {
  final spec = GameSpec.fromJson(json);
  expect(spec.problems, isEmpty);
  final world = GameWorld(spec);
  addTearDown(world.dispose);
  return world;
}

void stepFor(GameWorld world, double seconds) {
  final steps = (seconds / GameWorld.fixedDt).round();
  for (var i = 0; i < steps; i++) {
    world.step(GameWorld.fixedDt);
  }
}

/// A closed 10 x 16 box.
const Map<String, Object?> border = {
  'id': 'border',
  'type': 'wall',
  'points': [
    [0, 0],
    [10, 0],
    [10, 16],
    [0, 16],
    [0, 0],
  ],
};

void main() {
  test('invalid spec is rejected with the validation problems', () {
    final spec = GameSpec.fromJson({'bodies': <Object?>[]});
    expect(() => GameWorld(spec), throwsA(isA<GameConfigException>()));
  });

  test('ball falls under gravity', () {
    final world = worldOf({
      'bodies': [
        {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
      ],
    });
    final ball = world.bodyById('ball')!;
    stepFor(world, 0.5);
    // y = 2 + g t² / 2 ≈ 3.2
    expect(ball.y, closeTo(3.2, 0.15));
    expect(ball.x, closeTo(5, 1e-3));
    expect(world.status, GameStatus.playing);
  });

  test('ball stays put without gravity', () {
    final world = worldOf({
      'world': {'gravity': 0},
      'bodies': [
        {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
      ],
    });
    stepFor(world, 0.5);
    expect(world.bodyById('ball')!.y, closeTo(2, 1e-3));
  });

  test('ball rests on a wall instead of tunnelling through it', () {
    final world = worldOf({
      'bodies': [
        {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 1, 'restitution': 0},
        border,
      ],
    });
    stepFor(world, 4);
    final ball = world.bodyById('ball')!;
    expect(ball.y, lessThan(16));
    expect(ball.y, greaterThan(15));
    expect(world.lives, 3);
  });

  group('losing', () {
    test('ball below loseBelow costs a life and respawns', () {
      final world = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 15},
        ],
        'rules': {'lives': 3, 'loseBelow': 16},
      });
      final ball = world.bodyById('ball')!;
      stepFor(world, 0.7);
      expect(world.lives, 2);
      expect(world.status, GameStatus.playing);
      // Respawned near the start, already falling again.
      expect(ball.y, lessThan(16));
      expect(ball.y, greaterThanOrEqualTo(15));
    });

    test('status becomes lost at 0 lives and the world stops', () {
      final world = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 15},
        ],
        'rules': {'lives': 2, 'loseBelow': 16},
      });
      stepFor(world, 3);
      expect(world.lives, 0);
      expect(world.status, GameStatus.lost);

      final y = world.bodyById('ball')!.y;
      stepFor(world, 0.5);
      world.advance(0.05);
      expect(world.bodyById('ball')!.y, y);
    });

    test('ball that escapes sideways also costs a life', () {
      final world = worldOf({
        'world': {'gravity': 0},
        'bodies': [
          {
            'id': 'ball',
            'type': 'ball',
            'x': 9,
            'y': 8,
            'launchSpeed': 20,
            'launchAngle': 0,
          },
        ],
      });
      // 20 m/s from x = 9 leaves the 2 m safety margin after 0.15 s.
      stepFor(world, 0.2);
      expect(world.lives, 2);
    });

    test('restart resets score, lives and status', () {
      final world = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 15},
        ],
        'rules': {'lives': 1},
      });
      stepFor(world, 1);
      expect(world.status, GameStatus.lost);
      world.restart();
      expect(world.status, GameStatus.playing);
      expect(world.lives, 1);
      expect(world.score, 0);
      expect(world.bodyById('ball')!.y, 15);
    });
  });

  group('scoring', () {
    test('bumper adds score on every hit and bounces the ball away', () {
      final world = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
          {
            'id': 'bumper',
            'type': 'bumper',
            'x': 5,
            'y': 6,
            'radius': 0.6,
            'score': 100,
          },
          border,
        ],
      });
      final ball = world.bodyById('ball')!;
      var minYAfterHit = double.infinity;
      for (var i = 0; i < 600 && world.score < 200; i++) {
        world.step(GameWorld.fixedDt);
        if (world.score >= 100 && ball.y < minYAfterHit) minYAfterHit = ball.y;
      }
      expect(world.score, 200, reason: 'the ball should bounce and hit twice');
      // Restitution 1.2 sends it back up above the bumper's top (y = 5.4).
      expect(minYAfterHit, lessThan(4.5));
      expect(world.bodyById('bumper'), isNotNull);
    });

    test('a ball dropped dead centre does not farm one bumper forever', () {
      final world = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
          {
            'id': 'bumper',
            'type': 'bumper',
            'x': 5,
            'y': 6,
            'radius': 0.6,
            'score': 100,
          },
          border,
        ],
      });
      final ball = world.bodyById('ball')!;
      var maxOffset = 0.0;
      for (var i = 0; i < 1200 && world.score < 500; i++) {
        world.step(GameWorld.fixedDt);
        final offset = (ball.x - 5).abs();
        if (offset > maxOffset) maxOffset = offset;
      }
      // Without the sideways kick the ball stays on x = 5 and keeps scoring.
      expect(maxOffset, greaterThan(0.6));
      expect(world.score, lessThan(500));
    });

    test('target adds score and stays', () {
      final world = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
          {'id': 't', 'type': 'target', 'x': 5, 'y': 5, 'score': 50},
          {
            'id': 'box',
            'type': 'target',
            'x': 2,
            'y': 5,
            'width': 1,
            'height': 0.3,
          },
          border,
        ],
      });
      stepFor(world, 1);
      expect(world.score, greaterThanOrEqualTo(50));
      expect(world.score % 50, 0);
      expect(world.bodyById('t'), isNotNull);
      expect(world.bodyById('t')!.flash, greaterThanOrEqualTo(0));
    });

    test('brick adds score once and is removed', () {
      final world = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2, 'restitution': 0.2},
          {'id': 'brick', 'type': 'brick', 'x': 5, 'y': 5, 'score': 10},
          {'id': 'other', 'type': 'brick', 'x': 1, 'y': 1},
          border,
        ],
      });
      expect(world.remainingBricks, 2);
      stepFor(world, 3);
      expect(world.score, 10);
      expect(world.bodyById('brick'), isNull);
      expect(world.remainingBricks, 1);
      // With the brick gone the ball falls through to the floor.
      expect(world.bodyById('ball')!.y, greaterThan(15));
      expect(world.status, GameStatus.playing);
    });
  });

  group('winning', () {
    test('winWhenNoBricks', () {
      final world = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
          {'id': 'brick', 'type': 'brick', 'x': 5, 'y': 5},
          border,
        ],
        'rules': {'winWhenNoBricks': true},
      });
      stepFor(world, 0.2);
      expect(world.status, GameStatus.playing);
      stepFor(world, 2);
      expect(world.status, GameStatus.won);
      expect(world.score, 10);
    });

    test('winScore', () {
      final world = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
          {'id': 'bumper', 'type': 'bumper', 'x': 5, 'y': 6, 'score': 100},
          border,
        ],
        'rules': {'winScore': 200},
      });
      stepFor(world, 0.2);
      expect(world.status, GameStatus.playing);
      stepFor(world, 4);
      expect(world.status, GameStatus.won);
      expect(world.score, 200);
    });
  });

  group('flippers', () {
    GameWorld table() => worldOf({
      'bodies': [
        {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 1},
        {'id': 'fl', 'type': 'flipper', 'side': 'left', 'x': 3, 'y': 14},
        {'id': 'fr', 'type': 'flipper', 'side': 'right', 'x': 7, 'y': 14},
        border,
      ],
      'world': {'gravity': 0},
    });

    final rest = degreesToRadians(30);

    test('rest below horizontal with tips pointing at each other', () {
      final world = table();
      stepFor(world, 0.3);
      final left = world.bodyById('fl')!;
      final right = world.bodyById('fr')!;
      expect(left.angle, closeTo(rest, 0.05));
      expect(right.angle, closeTo(-rest, 0.05));
      expect(left.flipperTip.x, greaterThan(3));
      expect(left.flipperTip.y, greaterThan(14));
      expect(right.flipperTip.x, lessThan(7));
      expect(right.flipperTip.y, greaterThan(14));
    });

    test('press swings to the upper limit and release returns', () {
      final world = table();
      final left = world.bodyById('fl')!;
      final right = world.bodyById('fr')!;

      world.pressLeftFlipper();
      stepFor(world, 0.3);
      expect(left.angle, closeTo(-rest, 0.05));
      expect(left.flipperTip.y, lessThan(14), reason: 'tip is raised');
      expect(right.angle, closeTo(-rest, 0.05), reason: 'right is untouched');

      world.pressRightFlipper();
      stepFor(world, 0.3);
      expect(right.angle, closeTo(rest, 0.05));
      expect(right.flipperTip.y, lessThan(14));

      world
        ..releaseLeftFlipper()
        ..releaseRightFlipper();
      stepFor(world, 0.4);
      expect(left.angle, closeTo(rest, 0.05));
      expect(right.angle, closeTo(-rest, 0.05));
    });

    test('a pressed flipper kicks a landing ball upward', () {
      final world = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 4, 'y': 13},
          {'id': 'fl', 'type': 'flipper', 'side': 'left', 'x': 3, 'y': 14},
          border,
        ],
      });
      final ball = world.bodyById('ball')!;
      // Let the ball drop until it is about to land on the flipper.
      for (var i = 0; i < 240 && ball.y < 14; i++) {
        world.step(GameWorld.fixedDt);
      }
      final restingY = ball.y;
      expect(restingY, greaterThanOrEqualTo(14));
      world.pressLeftFlipper();
      var highest = restingY;
      for (var i = 0; i < 120; i++) {
        world.step(GameWorld.fixedDt);
        if (ball.y < highest) highest = ball.y;
      }
      expect(highest, lessThan(restingY - 2));
    });
  });

  group('launch', () {
    Map<String, Object?> config() => {
      'bodies': [
        {'id': 'ball', 'type': 'ball', 'x': 9, 'y': 14},
      ],
      'controls': {'launch': 'tap'},
      'rules': {'lives': 2},
    };

    test('ball waits at its start position until launched', () {
      final world = worldOf(config());
      final ball = world.bodyById('ball')!;
      stepFor(world, 1);
      expect(ball.held, isTrue);
      expect(world.hasHeldBall, isTrue);
      expect(ball.y, 14);

      expect(world.launchBall(), isTrue);
      expect(world.hasHeldBall, isFalse);
      stepFor(world, 0.5);
      expect(ball.y, lessThan(8), reason: 'launched upward');
      expect(world.launchBall(), isFalse, reason: 'already in flight');
    });

    test('lost ball is held again at the start position', () {
      final world = worldOf(config());
      final ball = world.bodyById('ball')!;
      world.launchBall();
      stepFor(world, 6);
      expect(world.lives, 1);
      expect(ball.held, isTrue);
      expect(ball.y, 14);
      stepFor(world, 0.5);
      expect(ball.y, 14);
      expect(world.launchBall(), isTrue);
    });

    test('without the launch control an explicit launchSpeed is applied', () {
      final world = worldOf({
        'world': {'gravity': 0},
        'bodies': [
          {
            'id': 'ball',
            'type': 'ball',
            'x': 5,
            'y': 8,
            'launchSpeed': 4,
            'launchAngle': 90,
          },
          border,
        ],
      });
      stepFor(world, 0.5);
      expect(world.bodyById('ball')!.y, closeTo(6, 0.1));
    });
  });

  group('paddle', () {
    GameWorld breakout() => worldOf({
      'world': {'gravity': 0},
      'bodies': [
        {
          'id': 'ball',
          'type': 'ball',
          'x': 5,
          'y': 10,
          'restitution': 1,
          'launchSpeed': 6,
          'launchAngle': 270,
          'minSpeed': 6,
          'maxSpeed': 6,
        },
        {'id': 'paddle', 'type': 'paddle', 'x': 5, 'y': 14, 'width': 2},
        border,
      ],
      'controls': {'drag': 'paddle'},
    });

    test('moves toward the drag position and stays inside the world', () {
      final world = breakout();
      final paddle = world.bodyById('paddle')!;
      world.movePaddleTo(8);
      stepFor(world, 0.05);
      expect(paddle.x, greaterThan(5));
      stepFor(world, 0.3);
      expect(paddle.x, closeTo(8, 0.01));
      expect(paddle.y, 14);

      world.movePaddleTo(-50);
      stepFor(world, 0.5);
      expect(paddle.x, closeTo(1, 0.01));
    });

    test('bounces the ball back and keeps its speed clamped', () {
      final world = breakout();
      final ball = world.bodyById('ball')!;
      stepFor(world, 1);
      final yAfterBounce = ball.y;
      stepFor(world, 0.25);
      expect(ball.y, lessThan(yAfterBounce), reason: 'moving up again');
      expect(yAfterBounce - ball.y, closeTo(1.5, 0.1), reason: '6 m/s');
      expect(world.lives, 3);
    });

    test('an off-centre hit steers the ball sideways', () {
      final world = breakout();
      final ball = world.bodyById('ball')!;
      world.movePaddleTo(4.4);
      stepFor(world, 1.5);
      expect(ball.x, greaterThan(5.3));
    });
  });

  group('advance', () {
    test('runs fixed steps and carries the remainder', () {
      final a = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
        ],
      });
      final b = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
        ],
      });
      // 30 frames of 1/60 s == 60 fixed steps.
      for (var i = 0; i < 30; i++) {
        a.advance(1 / 60);
      }
      stepFor(b, 0.5);
      expect(a.bodyById('ball')!.y, closeTo(b.bodyById('ball')!.y, 0.05));
    });

    test('clamps a long pause instead of replaying it', () {
      final world = worldOf({
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
        ],
      });
      world.advance(30);
      // At most maxFrameTime (0.1 s) was simulated: ~5 cm of free fall.
      expect(world.bodyById('ball')!.y, lessThan(2.1));
      expect(world.lives, 3);
    });
  });

  test('dispose is idempotent and makes input a no-op', () {
    final spec = GameSpec.fromJson({
      'bodies': [
        {'id': 'ball', 'type': 'ball', 'x': 5, 'y': 2},
        {'id': 'fl', 'type': 'flipper', 'side': 'left', 'x': 3, 'y': 14},
      ],
    });
    final world = GameWorld(spec)
      ..dispose()
      ..dispose();
    world
      ..pressLeftFlipper()
      ..movePaddleTo(3)
      ..step(GameWorld.fixedDt)
      ..advance(0.1);
    expect(world.launchBall(), isFalse);
    expect(world.bodies, isEmpty);
  });
}
