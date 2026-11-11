import 'package:flutter_test/flutter_test.dart';
import 'package:genui_app_maker/catalog/game/game_spec.dart';

/// The contract example from docs/SPEC.md section 5.3.
Map<String, Object?> specExample() => {
  'component': 'PhysicsGame',
  'world': {'width': 10, 'height': 16, 'gravity': 9.8},
  'bodies': [
    {
      'id': 'ball',
      'type': 'ball',
      'x': 9.2,
      'y': 14,
      'radius': 0.25,
      'restitution': 0.5,
    },
    {
      'id': 'wallL',
      'type': 'wall',
      'points': [
        [0, 0],
        [0, 16],
      ],
    },
    {'id': 'b1', 'type': 'bumper', 'x': 5, 'y': 4, 'radius': 0.6, 'score': 100},
    {
      'id': 'fl',
      'type': 'flipper',
      'side': 'left',
      'x': 3,
      'y': 14.5,
      'length': 1.8,
    },
    {
      'id': 'fr',
      'type': 'flipper',
      'side': 'right',
      'x': 7,
      'y': 14.5,
      'length': 1.8,
    },
  ],
  'controls': {
    'tapLeft': 'flipperLeft',
    'tapRight': 'flipperRight',
    'launch': 'tap',
  },
  'rules': {'lives': 3, 'loseBelow': 16, 'winScore': null},
  'statePath': '/game',
};

Map<String, Object?> withBodies(List<Object?> bodies) => {'bodies': bodies};

const Map<String, Object?> ball = {
  'id': 'ball',
  'type': 'ball',
  'x': 5,
  'y': 5,
};

/// Problems of a config that has a valid ball plus [extra] bodies.
List<String> problemsWith(
  List<Object?> extra, {
  Map<String, Object?> rest = const {},
}) => GameSpec.fromJson({
  'bodies': [ball, ...extra],
  ...rest,
}).problems;

void main() {
  group('parsing', () {
    test('reads the SPEC example without problems', () {
      final spec = GameSpec.fromJson(specExample());

      expect(spec.problems, isEmpty);
      expect(spec.isValid, isTrue);
      expect(spec.world.width, 10);
      expect(spec.world.height, 16);
      expect(spec.world.gravity, 9.8);
      expect(spec.world.aspectRatio, 10 / 16);
      expect(spec.bodies.map((b) => b.kind), [
        BodyKind.ball,
        BodyKind.wall,
        BodyKind.bumper,
        BodyKind.flipper,
        BodyKind.flipper,
      ]);

      final wall = spec.bodies[1];
      expect(wall.points, const [WorldPoint(0, 0), WorldPoint(0, 16)]);

      final bumper = spec.bodies[2];
      expect(bumper.radius, 0.6);
      expect(bumper.score, 100);

      expect(spec.bodies[3].side, FlipperSide.left);
      expect(spec.bodies[4].side, FlipperSide.right);
      expect(spec.bodies[4].length, 1.8);

      expect(spec.controls.tapLeft, FlipperSide.left);
      expect(spec.controls.tapRight, FlipperSide.right);
      expect(spec.controls.launchOnTap, isTrue);
      expect(spec.controls.dragPaddle, isFalse);

      expect(spec.rules.lives, 3);
      expect(spec.rules.loseBelow, 16);
      expect(spec.rules.winScore, isNull);
      expect(spec.rules.winWhenNoBricks, isFalse);
      expect(spec.statePath, '/game');
    });

    test('applies defaults when only a ball is given', () {
      final spec = GameSpec.fromJson(withBodies([ball]));

      expect(spec.problems, isEmpty);
      expect(spec.world.width, WorldSpec.defaultWidth);
      expect(spec.world.height, WorldSpec.defaultHeight);
      expect(spec.world.gravity, WorldSpec.defaultGravity);
      expect(spec.rules.lives, RulesSpec.defaultLives);
      expect(spec.rules.loseBelow, WorldSpec.defaultHeight);
      expect(spec.rules.winScore, isNull);
      expect(spec.controls.tapLeft, isNull);
      expect(spec.controls.tapRight, isNull);
      expect(spec.controls.dragPaddle, isFalse);
      expect(spec.controls.launchOnTap, isFalse);
      expect(spec.statePath, isNull);

      final parsed = spec.bodies.single;
      expect(parsed.radius, BodySpec.defaultBallRadius);
      expect(parsed.restitution, BodySpec.defaultBallRestitution);
      expect(parsed.launchSpeed, isNull);
      expect(parsed.launchAngle, 90);
      expect(parsed.color, isNull);
    });

    test('applies per-type defaults', () {
      final spec = GameSpec.fromJson(
        withBodies([
          ball,
          {'type': 'bumper', 'x': 1, 'y': 1},
          {'type': 'flipper', 'side': 'right', 'x': 2, 'y': 2},
          {'type': 'paddle', 'x': 3, 'y': 3},
          {'type': 'brick', 'x': 4, 'y': 4},
          {'type': 'target', 'x': 5, 'y': 5},
          {'type': 'target', 'x': 6, 'y': 6, 'width': 1, 'height': 0.2},
          {
            'type': 'wall',
            'points': [
              [0, 0],
              [1, 1],
            ],
          },
        ]),
      );
      expect(spec.problems, isEmpty);
      final [_, bumper, flipper, paddle, brick, target, boxTarget, wall] =
          spec.bodies;

      expect(bumper.radius, BodySpec.defaultBumperRadius);
      expect(bumper.score, BodySpec.defaultBumperScore);
      expect(bumper.restitution, BodySpec.defaultBumperRestitution);
      expect(flipper.length, BodySpec.defaultFlipperLength);
      expect(flipper.thickness, BodySpec.defaultFlipperThickness);
      expect(flipper.restAngle, BodySpec.defaultFlipperAngle);
      expect(flipper.activeAngle, BodySpec.defaultFlipperAngle);
      expect(paddle.width, BodySpec.defaultPaddleWidth);
      expect(paddle.height, BodySpec.defaultPaddleHeight);
      expect(brick.width, BodySpec.defaultBrickWidth);
      expect(brick.height, BodySpec.defaultBrickHeight);
      expect(brick.score, BodySpec.defaultBrickScore);
      expect(target.score, BodySpec.defaultTargetScore);
      expect(target.isBox, isFalse);
      expect(target.radius, BodySpec.defaultTargetRadius);
      expect(boxTarget.isBox, isTrue);
      expect(wall.thickness, BodySpec.defaultWallThickness);
      // Bodies without an id get a stable generated one.
      expect(bumper.id, 'body1');
    });

    test('accepts ints, doubles and numeric strings for numbers', () {
      final spec = GameSpec.fromJson({
        'world': {'width': 8.0, 'height': 12, 'gravity': '0'},
        'bodies': [
          {'id': 'ball', 'type': 'ball', 'x': 4, 'y': 6.5, 'radius': '0.3'},
          {'type': 'brick', 'x': 1, 'y': 1, 'score': 25.0},
        ],
        'rules': {'lives': 5.0, 'winScore': 300.0, 'winWhenNoBricks': true},
        'controls': {'drag': 'paddle', 'tapLeft': 'none'},
        'statePath': 'game/pong/',
      });

      expect(spec.problems, isEmpty);
      expect(spec.world.width, 8);
      expect(spec.world.height, 12);
      expect(spec.world.gravity, 0);
      expect(spec.bodies.first.y, 6.5);
      expect(spec.bodies.first.radius, 0.3);
      expect(spec.bodies.last.score, 25);
      expect(spec.rules.lives, 5);
      expect(spec.rules.winScore, 300);
      expect(spec.rules.winWhenNoBricks, isTrue);
      expect(spec.rules.loseBelow, 12, reason: 'defaults to world height');
      expect(spec.controls.dragPaddle, isTrue);
      expect(spec.controls.tapLeft, isNull);
      expect(spec.statePath, '/game/pong', reason: 'normalised');
    });

    test('parses colours and ignores malformed ones', () {
      final spec = GameSpec.fromJson(
        withBodies([
          {...ball, 'color': '#FF8800'},
          {'type': 'bumper', 'x': 1, 'y': 1, 'color': 'orange'},
        ]),
      );
      expect(spec.problems, isEmpty);
      expect(spec.bodies[0].color, 0xFFFF8800);
      expect(spec.bodies[1].color, isNull);
    });

    test('signature changes only when the config changes', () {
      final a = GameSpec.fromJson(specExample());
      final b = GameSpec.fromJson(specExample());
      final changed = specExample()..['world'] = {'gravity': 20};
      expect(a.signature, b.signature);
      expect(GameSpec.fromJson(changed).signature, isNot(a.signature));
    });
  });

  group('validation', () {
    test('never throws on garbage and reports it instead', () {
      final spec = GameSpec.fromJson({
        'world': 'big',
        'bodies': 'ball',
        'controls': 3,
        'rules': [1],
        'statePath': 7,
      });
      expect(spec.isValid, isFalse);
      expect(spec.problems, contains(contains('world must be an object')));
      expect(spec.problems, contains(contains('controls must be an object')));
      expect(spec.problems, contains(contains('rules must be an object')));
      expect(spec.problems, contains(contains('statePath must be a string')));
      expect(spec.problems, contains(contains('bodies must be a non-empty')));
    });

    test('missing or empty bodies', () {
      expect(
        GameSpec.fromJson({}).problems,
        contains(contains('bodies must be a non-empty list')),
      );
      expect(
        GameSpec.fromJson(withBodies([])).problems,
        contains(contains('bodies must be a non-empty list')),
      );
    });

    test('no ball', () {
      final spec = GameSpec.fromJson(
        withBodies([
          {'type': 'bumper', 'x': 5, 'y': 5},
        ]),
      );
      expect(spec.problems, [contains('at least one body of type "ball"')]);
    });

    test('unknown type', () {
      final problems = problemsWith([
        {'id': 'x', 'type': 'spinner', 'x': 1, 'y': 1},
        {'id': 'y', 'x': 1, 'y': 1},
      ]);
      expect(problems, hasLength(2));
      expect(problems[0], contains('unknown type "spinner"'));
      expect(problems[0], contains('"x"'));
      expect(problems[0], contains('ball, wall, bumper'));
      expect(problems[1], contains('unknown type "null"'));
    });

    test('body entry that is not an object', () {
      expect(problemsWith(['ball']), [contains('must be an object')]);
    });

    test('duplicate ids', () {
      expect(
        problemsWith([
          {'id': 'ball', 'type': 'bumper', 'x': 1, 'y': 1},
        ]),
        [contains('duplicate id "ball"')],
      );
    });

    test('coordinates outside the world', () {
      final problems = problemsWith([
        {'id': 'far', 'type': 'bumper', 'x': 12, 'y': 4},
        {'id': 'neg', 'type': 'brick', 'x': 3, 'y': -1},
        {'id': 'low', 'type': 'target', 'x': 3, 'y': 16.5},
      ]);
      expect(problems, hasLength(3));
      expect(problems, everyElement(contains('outside the world')));
      expect(problems[0], contains('"far"'));
      expect(problems[0], contains('0..10.0 x 0..16.0'));
    });

    test('coordinates on the world edge are allowed', () {
      expect(
        problemsWith([
          {'type': 'bumper', 'x': 0, 'y': 16},
          {'type': 'bumper', 'x': 10, 'y': 0},
        ]),
        isEmpty,
      );
    });

    test('missing coordinates', () {
      final problems = problemsWith([
        {'id': 'b', 'type': 'bumper', 'y': 4},
      ]);
      expect(problems, [contains('"x" is required')]);
    });

    test('non-numeric values', () {
      final problems = problemsWith([
        {'id': 'b', 'type': 'bumper', 'x': 'left', 'y': 4, 'score': 'many'},
      ]);
      expect(problems, hasLength(2));
      expect(problems[0], contains('x must be a number'));
      expect(problems[1], contains('score must be a number'));
    });

    test('non-positive sizes', () {
      final problems = problemsWith([
        {'id': 'a', 'type': 'bumper', 'x': 1, 'y': 1, 'radius': 0},
        {'id': 'b', 'type': 'brick', 'x': 1, 'y': 1, 'width': -1},
        {
          'id': 'c',
          'type': 'flipper',
          'side': 'left',
          'x': 1,
          'y': 1,
          'length': 0,
        },
        {'id': 'd', 'type': 'bumper', 'x': 1, 'y': 1, 'restitution': -0.5},
      ]);
      expect(problems, hasLength(4));
      expect(problems[0], contains('radius must be greater than 0'));
      expect(problems[1], contains('width must be greater than 0'));
      expect(problems[2], contains('length must be greater than 0'));
      expect(problems[3], contains('restitution must not be negative'));
    });

    test('wall without enough points, bad points, points out of bounds', () {
      expect(
        problemsWith([
          {'id': 'w', 'type': 'wall'},
        ]),
        [contains('at least two [x, y] pairs')],
      );
      expect(
        problemsWith([
          {
            'id': 'w',
            'type': 'wall',
            'points': [
              [0, 0],
            ],
          },
        ]),
        [contains('at least two [x, y] pairs')],
      );
      final bad = problemsWith([
        {
          'id': 'w',
          'type': 'wall',
          'points': [
            [0, 0],
            [5],
            'x',
            [3, 3],
            [3, 40],
          ],
        },
      ]);
      expect(bad, hasLength(3));
      expect(bad[0], contains('points[1] must be an [x, y] pair'));
      expect(bad[1], contains('points[2] must be an [x, y] pair'));
      expect(bad[2], contains('points[4]'));
      expect(bad[2], contains('outside the world'));
    });

    test('flipper side and angles', () {
      final problems = problemsWith([
        {'id': 'a', 'type': 'flipper', 'x': 1, 'y': 1},
        {'id': 'b', 'type': 'flipper', 'side': 'middle', 'x': 1, 'y': 1},
        {
          'id': 'c',
          'type': 'flipper',
          'side': 'left',
          'x': 1,
          'y': 1,
          'restAngle': 120,
        },
      ]);
      expect(problems, hasLength(3));
      expect(problems[0], contains('"side" must be "left" or "right"'));
      expect(problems[1], contains('"side" must be "left" or "right"'));
      expect(problems[2], contains('restAngle must be between 0 and 80'));
    });

    test('ball speed limits', () {
      final spec = GameSpec.fromJson(
        withBodies([
          {...ball, 'minSpeed': 9, 'maxSpeed': 3},
        ]),
      );
      expect(spec.problems, [contains('minSpeed must not be greater')]);
    });

    test('world size', () {
      final spec = GameSpec.fromJson({
        'world': {'width': 0, 'height': -4},
        'bodies': [ball],
      });
      expect(spec.problems, hasLength(2));
      expect(spec.problems[0], contains('world.width must be greater than 0'));
      expect(spec.problems[1], contains('world.height must be greater than 0'));
      // Falls back to usable defaults so nothing downstream divides by zero.
      expect(spec.world.aspectRatio, 10 / 16);
    });

    test('rules', () {
      final problems = problemsWith(
        const [],
        rest: {
          'rules': {
            'lives': 0,
            'winScore': -5,
            'winWhenNoBricks': 'yes',
            'loseBelow': 'bottom',
          },
        },
      );
      expect(problems, hasLength(4));
      expect(problems, contains(contains('rules.lives must be at least 1')));
      expect(problems, contains(contains('rules.winScore must be greater')));
      expect(problems, contains(contains('winWhenNoBricks must be true or')));
      expect(problems, contains(contains('rules.loseBelow must be a number')));
    });

    test('winWhenNoBricks without bricks', () {
      final problems = problemsWith(
        const [],
        rest: {
          'rules': {'winWhenNoBricks': true},
        },
      );
      expect(problems, [contains('there is no body of type "brick"')]);
    });

    test('controls with unknown values', () {
      final problems = problemsWith(
        const [],
        rest: {
          'controls': {
            'tapLeft': 'jump',
            'tapRight': 'flipperLeft',
            'drag': 'ball',
            'launch': 'swipe',
          },
        },
      );
      expect(problems, hasLength(3));
      expect(problems[0], contains('controls.tapLeft'));
      expect(problems[1], contains('controls.drag must be "paddle"'));
      expect(problems[2], contains('controls.launch must be "tap"'));
    });

    test('statePath without a key', () {
      expect(problemsWith(const [], rest: {'statePath': '/'}), [
        contains('statePath must name a key'),
      ]);
    });

    test('GameConfigException lists every problem', () {
      final text = GameConfigException(['first', 'second']).toString();
      expect(text, contains('- first'));
      expect(text, contains('- second'));
    });
  });
}
