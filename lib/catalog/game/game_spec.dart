/// Immutable, validated description of a `PhysicsGame` component.
///
/// The LLM sends loosely typed JSON. [GameSpec.fromJson] never throws: it
/// applies defaults, accepts ints where doubles are expected and collects
/// every problem it finds in [GameSpec.problems] so the caller can report
/// them back to the LLM instead of crashing the widget tree.
library;

import 'dart:convert';
import 'dart:math' as math;

/// The kinds of bodies a game can contain (`bodies[].type`).
enum BodyKind { ball, wall, bumper, flipper, paddle, brick, target }

/// Which side a flipper is mounted on.
enum FlipperSide { left, right }

/// A point in world coordinates (metres, origin top-left, y grows downward).
class WorldPoint {
  const WorldPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is WorldPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// World size and gravity.
class WorldSpec {
  const WorldSpec({
    this.width = defaultWidth,
    this.height = defaultHeight,
    this.gravity = defaultGravity,
  });

  static const double defaultWidth = 10;
  static const double defaultHeight = 16;
  static const double defaultGravity = 9.8;

  final double width;
  final double height;

  /// Downward acceleration in m/s². Zero gives a breakout/pong style world.
  final double gravity;

  double get aspectRatio => width / height;
}

/// One entry of `bodies`.
///
/// A single class is used for every [BodyKind]; fields that do not apply to a
/// kind keep their defaults and are ignored by the simulation.
class BodySpec {
  const BodySpec({
    required this.id,
    required this.kind,
    this.x = 0,
    this.y = 0,
    this.radius = 0,
    this.width = 0,
    this.height = 0,
    this.length = 0,
    this.thickness = 0,
    this.side = FlipperSide.left,
    this.points = const [],
    this.score = 0,
    this.restitution = 0,
    this.restAngle = defaultFlipperAngle,
    this.activeAngle = defaultFlipperAngle,
    this.launchSpeed,
    this.launchAngle = 90,
    this.minSpeed,
    this.maxSpeed,
    this.color,
  });

  static const double defaultBallRadius = 0.25;
  static const double defaultBallRestitution = 0.5;
  static const double defaultBumperRadius = 0.5;
  static const double defaultBumperRestitution = 1.2;
  static const int defaultBumperScore = 100;
  static const double defaultFlipperLength = 1.8;
  static const double defaultFlipperThickness = 0.3;
  static const double defaultFlipperAngle = 30;
  static const double defaultPaddleWidth = 2;
  static const double defaultPaddleHeight = 0.3;
  static const double defaultBrickWidth = 1;
  static const double defaultBrickHeight = 0.4;
  static const int defaultBrickScore = 10;
  static const double defaultTargetRadius = 0.3;
  static const int defaultTargetScore = 50;
  static const double defaultWallThickness = 0.1;

  final String id;
  final BodyKind kind;

  /// Centre of the body. For a flipper this is the pivot.
  final double x;
  final double y;

  /// Radius of a ball, bumper or round target.
  final double radius;

  /// Size of a paddle, brick or rectangular target. A target with zero
  /// width/height is round and uses [radius].
  final double width;
  final double height;

  /// Flipper length from pivot to tip.
  final double length;

  /// Flipper or wall thickness.
  final double thickness;

  final FlipperSide side;

  /// Wall polyline.
  final List<WorldPoint> points;

  /// Points awarded when a ball hits this body.
  final int score;

  /// Bounciness. Box2D uses the larger value of the two touching bodies.
  final double restitution;

  /// Flipper: degrees below horizontal while released.
  final double restAngle;

  /// Flipper: degrees above horizontal while pressed.
  final double activeAngle;

  /// Ball: launch speed in m/s. Null lets the simulation pick a speed that
  /// reaches the top of the world.
  final double? launchSpeed;

  /// Ball: launch direction in degrees. 90 = up, 0 = right, 180 = left.
  final double launchAngle;

  /// Ball: optional speed clamp in m/s.
  final double? minSpeed;
  final double? maxSpeed;

  /// Optional ARGB colour.
  final int? color;

  /// Whether a target is drawn and simulated as a box.
  bool get isBox => width > 0 && height > 0;
}

/// `controls`: which gestures are wired to which bodies.
class ControlsSpec {
  const ControlsSpec({
    this.tapLeft,
    this.tapRight,
    this.dragPaddle = false,
    this.launchOnTap = false,
  });

  /// Flippers driven by touching the left half of the widget.
  final FlipperSide? tapLeft;

  /// Flippers driven by touching the right half of the widget.
  final FlipperSide? tapRight;

  /// Whether a horizontal drag moves the paddles.
  final bool dragPaddle;

  /// Whether a tap launches a ball waiting at its start position.
  final bool launchOnTap;
}

/// `rules`: lives and win/lose conditions.
class RulesSpec {
  const RulesSpec({
    this.lives = defaultLives,
    required this.loseBelow,
    this.winScore,
    this.winWhenNoBricks = false,
  });

  static const int defaultLives = 3;

  final int lives;

  /// A ball whose top edge passes this y is lost.
  final double loseBelow;

  final int? winScore;
  final bool winWhenNoBricks;
}

/// Thrown/reported when a config cannot be played.
class GameConfigException implements Exception {
  GameConfigException(this.problems);

  final List<String> problems;

  @override
  String toString() =>
      'Invalid PhysicsGame config:\n${problems.map((p) => '- $p').join('\n')}';
}

/// The parsed `PhysicsGame` component.
class GameSpec {
  const GameSpec({
    required this.world,
    required this.bodies,
    required this.controls,
    required this.rules,
    required this.statePath,
    required this.problems,
    required this.signature,
  });

  /// Parses [json] tolerantly. Never throws; check [isValid] / [problems].
  factory GameSpec.fromJson(Map<String, Object?> json) {
    final problems = <String>[];
    String signature;
    try {
      signature = jsonEncode(json);
    } catch (_) {
      signature = json.toString();
    }
    try {
      return _Parser(problems).parse(json, signature);
    } catch (error) {
      // Defensive: the parser is written not to throw, but a malformed
      // payload must never take the widget tree down.
      problems.add('Could not read the game config: $error');
      return GameSpec(
        world: const WorldSpec(),
        bodies: const [],
        controls: const ControlsSpec(),
        rules: const RulesSpec(loseBelow: WorldSpec.defaultHeight),
        statePath: null,
        problems: List.unmodifiable(problems),
        signature: signature,
      );
    }
  }

  final WorldSpec world;
  final List<BodySpec> bodies;
  final ControlsSpec controls;
  final RulesSpec rules;

  /// Absolute data model path (e.g. `/game`) or null when state is not shared.
  final String? statePath;

  /// Human-readable validation problems. Empty when the game is playable.
  final List<String> problems;

  /// Canonical text of the source JSON, used to detect config changes.
  final String signature;

  bool get isValid => problems.isEmpty;

  Iterable<BodySpec> ofKind(BodyKind kind) =>
      bodies.where((body) => body.kind == kind);
}

class _Parser {
  _Parser(this.problems);

  final List<String> problems;

  GameSpec parse(Map<String, Object?> json, String signature) {
    final world = _world(_map(json['world'], 'world'));
    final bodies = _bodies(json['bodies'], world);
    final controls = _controls(_map(json['controls'], 'controls'));
    final rules = _rules(_map(json['rules'], 'rules'), world);

    if (!bodies.any((b) => b.kind == BodyKind.ball) &&
        json['bodies'] is List &&
        (json['bodies']! as List).isNotEmpty) {
      problems.add('bodies must contain at least one body of type "ball".');
    }
    if (rules.winWhenNoBricks && !bodies.any((b) => b.kind == BodyKind.brick)) {
      problems.add(
        'rules.winWhenNoBricks is true but there is no body of type "brick".',
      );
    }

    return GameSpec(
      world: world,
      bodies: List.unmodifiable(bodies),
      controls: controls,
      rules: rules,
      statePath: _statePath(json['statePath']),
      problems: List.unmodifiable(problems),
      signature: signature,
    );
  }

  // --- sections -----------------------------------------------------------

  WorldSpec _world(Map<Object?, Object?> json) {
    var width = _number(json, 'width', 'world.width', WorldSpec.defaultWidth);
    var height = _number(
      json,
      'height',
      'world.height',
      WorldSpec.defaultHeight,
    );
    final gravity = _number(
      json,
      'gravity',
      'world.gravity',
      WorldSpec.defaultGravity,
    );
    if (width <= 0) {
      problems.add('world.width must be greater than 0 (got $width).');
      width = WorldSpec.defaultWidth;
    }
    if (height <= 0) {
      problems.add('world.height must be greater than 0 (got $height).');
      height = WorldSpec.defaultHeight;
    }
    return WorldSpec(width: width, height: height, gravity: gravity);
  }

  List<BodySpec> _bodies(Object? json, WorldSpec world) {
    if (json is! List || json.isEmpty) {
      problems.add(
        'bodies must be a non-empty list containing at least one "ball".',
      );
      return const [];
    }
    final bodies = <BodySpec>[];
    final ids = <String>{};
    for (var i = 0; i < json.length; i++) {
      final entry = json[i];
      if (entry is! Map) {
        problems.add('bodies[$i] must be an object.');
        continue;
      }
      final rawId = entry['id'];
      final id = rawId is String && rawId.isNotEmpty ? rawId : 'body$i';
      if (!ids.add(id)) {
        problems.add('bodies[$i]: duplicate id "$id".');
      }
      final body = _body(entry, id, 'bodies[$i] ("$id")', world);
      if (body != null) bodies.add(body);
    }
    return bodies;
  }

  BodySpec? _body(
    Map<Object?, Object?> json,
    String id,
    String where,
    WorldSpec world,
  ) {
    final type = json['type'];
    final kind = BodyKind.values.where((k) => k.name == type).firstOrNull;
    if (kind == null) {
      problems.add(
        '$where: unknown type "$type". Use one of '
        '${BodyKind.values.map((k) => k.name).join(', ')}.',
      );
      return null;
    }

    final color = _color(json['color']);
    double restitution(double fallback) =>
        _nonNegative(json, 'restitution', where, fallback);
    int score(int fallback) =>
        _number(json, 'score', '$where.score', fallback.toDouble()).round();

    switch (kind) {
      case BodyKind.wall:
        final points = _points(json['points'], where, world);
        if (points.length < 2) {
          problems.add(
            '$where: a wall needs "points" with at least two [x, y] pairs.',
          );
        }
        return BodySpec(
          id: id,
          kind: kind,
          points: List.unmodifiable(points),
          thickness: _positive(
            json,
            'thickness',
            where,
            BodySpec.defaultWallThickness,
          ),
          restitution: restitution(0),
          color: color,
        );
      case BodyKind.ball:
        final position = _position(json, where, world);
        final minSpeed = _optionalNumber(json, 'minSpeed', where);
        final maxSpeed = _optionalNumber(json, 'maxSpeed', where);
        if (minSpeed != null && maxSpeed != null && minSpeed > maxSpeed) {
          problems.add('$where: minSpeed must not be greater than maxSpeed.');
        }
        return BodySpec(
          id: id,
          kind: kind,
          x: position.x,
          y: position.y,
          radius: _positive(json, 'radius', where, BodySpec.defaultBallRadius),
          restitution: restitution(BodySpec.defaultBallRestitution),
          launchSpeed: _optionalNumber(json, 'launchSpeed', where),
          launchAngle: _number(json, 'launchAngle', '$where.launchAngle', 90),
          minSpeed: minSpeed,
          maxSpeed: maxSpeed,
          color: color,
        );
      case BodyKind.bumper:
        final position = _position(json, where, world);
        return BodySpec(
          id: id,
          kind: kind,
          x: position.x,
          y: position.y,
          radius: _positive(
            json,
            'radius',
            where,
            BodySpec.defaultBumperRadius,
          ),
          score: score(BodySpec.defaultBumperScore),
          restitution: restitution(BodySpec.defaultBumperRestitution),
          color: color,
        );
      case BodyKind.flipper:
        final position = _position(json, where, world);
        final side = json['side'];
        final parsedSide = FlipperSide.values
            .where((s) => s.name == side)
            .firstOrNull;
        if (parsedSide == null) {
          problems.add('$where: flipper "side" must be "left" or "right".');
        }
        return BodySpec(
          id: id,
          kind: kind,
          x: position.x,
          y: position.y,
          side: parsedSide ?? FlipperSide.left,
          length: _positive(
            json,
            'length',
            where,
            BodySpec.defaultFlipperLength,
          ),
          thickness: _positive(
            json,
            'thickness',
            where,
            BodySpec.defaultFlipperThickness,
          ),
          restAngle: _angle(json, 'restAngle', where),
          activeAngle: _angle(json, 'activeAngle', where),
          restitution: restitution(0),
          color: color,
        );
      case BodyKind.paddle:
      case BodyKind.brick:
        final position = _position(json, where, world);
        final isPaddle = kind == BodyKind.paddle;
        return BodySpec(
          id: id,
          kind: kind,
          x: position.x,
          y: position.y,
          width: _positive(
            json,
            'width',
            where,
            isPaddle ? BodySpec.defaultPaddleWidth : BodySpec.defaultBrickWidth,
          ),
          height: _positive(
            json,
            'height',
            where,
            isPaddle
                ? BodySpec.defaultPaddleHeight
                : BodySpec.defaultBrickHeight,
          ),
          score: isPaddle ? 0 : score(BodySpec.defaultBrickScore),
          restitution: restitution(0),
          color: color,
        );
      case BodyKind.target:
        final position = _position(json, where, world);
        final hasBox = json['width'] != null || json['height'] != null;
        return BodySpec(
          id: id,
          kind: kind,
          x: position.x,
          y: position.y,
          width: hasBox ? _positive(json, 'width', where, 0.6) : 0,
          height: hasBox ? _positive(json, 'height', where, 0.6) : 0,
          radius: _positive(
            json,
            'radius',
            where,
            BodySpec.defaultTargetRadius,
          ),
          score: score(BodySpec.defaultTargetScore),
          restitution: restitution(0),
          color: color,
        );
    }
  }

  ControlsSpec _controls(Map<Object?, Object?> json) {
    FlipperSide? flipper(String key) {
      final value = json[key];
      switch (value) {
        case null || 'none':
          return null;
        case 'flipperLeft':
          return FlipperSide.left;
        case 'flipperRight':
          return FlipperSide.right;
        default:
          problems.add(
            'controls.$key must be "flipperLeft" or "flipperRight" '
            '(got "$value").',
          );
          return null;
      }
    }

    bool flag(String key, String expected) {
      final value = json[key];
      if (value == null || value == 'none' || value == false) return false;
      if (value == expected || value == true) return true;
      problems.add('controls.$key must be "$expected" (got "$value").');
      return false;
    }

    return ControlsSpec(
      tapLeft: flipper('tapLeft'),
      tapRight: flipper('tapRight'),
      dragPaddle: flag('drag', 'paddle'),
      launchOnTap: flag('launch', 'tap'),
    );
  }

  RulesSpec _rules(Map<Object?, Object?> json, WorldSpec world) {
    var lives = _number(
      json,
      'lives',
      'rules.lives',
      RulesSpec.defaultLives.toDouble(),
    ).round();
    if (lives < 1) {
      problems.add('rules.lives must be at least 1 (got $lives).');
      lives = RulesSpec.defaultLives;
    }
    final winScore = _optionalNumber(json, 'winScore', 'rules');
    if (winScore != null && winScore <= 0) {
      problems.add('rules.winScore must be greater than 0 or null.');
    }
    final winWhenNoBricks = json['winWhenNoBricks'];
    if (winWhenNoBricks != null && winWhenNoBricks is! bool) {
      problems.add('rules.winWhenNoBricks must be true or false.');
    }
    return RulesSpec(
      lives: lives,
      loseBelow: _number(json, 'loseBelow', 'rules.loseBelow', world.height),
      winScore: winScore?.round(),
      winWhenNoBricks: winWhenNoBricks == true,
    );
  }

  String? _statePath(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      problems.add('statePath must be a string like "/game".');
      return null;
    }
    final segments = value.split('/').where((s) => s.isNotEmpty);
    if (segments.isEmpty) {
      if (value.trim().isNotEmpty) {
        problems.add('statePath must name a key, for example "/game".');
      }
      return null;
    }
    return '/${segments.join('/')}';
  }

  // --- primitives ---------------------------------------------------------

  Map<Object?, Object?> _map(Object? value, String name) {
    if (value == null) return const {};
    if (value is Map) return value;
    problems.add('$name must be an object.');
    return const {};
  }

  double? _toDouble(Object? value) {
    final double? result = switch (value) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s.trim()),
      _ => null,
    };
    return result != null && result.isFinite ? result : null;
  }

  double _number(
    Map<Object?, Object?> json,
    String key,
    String label,
    double fallback,
  ) {
    final value = json[key];
    if (value == null) return fallback;
    final parsed = _toDouble(value);
    if (parsed == null) {
      problems.add('$label must be a number (got "$value").');
      return fallback;
    }
    return parsed;
  }

  double? _optionalNumber(
    Map<Object?, Object?> json,
    String key,
    String where,
  ) {
    final value = json[key];
    if (value == null) return null;
    final parsed = _toDouble(value);
    if (parsed == null) {
      problems.add('$where.$key must be a number or null (got "$value").');
    }
    return parsed;
  }

  double _positive(
    Map<Object?, Object?> json,
    String key,
    String where,
    double fallback,
  ) {
    final value = _number(json, key, '$where.$key', fallback);
    if (value <= 0) {
      problems.add('$where: $key must be greater than 0 (got $value).');
      return fallback;
    }
    return value;
  }

  double _nonNegative(
    Map<Object?, Object?> json,
    String key,
    String where,
    double fallback,
  ) {
    final value = _number(json, key, '$where.$key', fallback);
    if (value < 0) {
      problems.add('$where: $key must not be negative (got $value).');
      return fallback;
    }
    return value;
  }

  double _angle(Map<Object?, Object?> json, String key, String where) {
    final value = _number(
      json,
      key,
      '$where.$key',
      BodySpec.defaultFlipperAngle,
    );
    if (value < 0 || value > 80) {
      problems.add(
        '$where: $key must be between 0 and 80 degrees (got $value).',
      );
      return BodySpec.defaultFlipperAngle;
    }
    return value;
  }

  WorldPoint _position(
    Map<Object?, Object?> json,
    String where,
    WorldSpec world,
  ) {
    for (final key in const ['x', 'y']) {
      if (json[key] == null) problems.add('$where: "$key" is required.');
    }
    final point = WorldPoint(
      _number(json, 'x', '$where.x', world.width / 2),
      _number(json, 'y', '$where.y', world.height / 2),
    );
    _checkBounds(point, where, world);
    return point;
  }

  List<WorldPoint> _points(Object? json, String where, WorldSpec world) {
    if (json is! List) return const [];
    final points = <WorldPoint>[];
    for (var i = 0; i < json.length; i++) {
      final pair = json[i];
      final x = pair is List && pair.length >= 2 ? _toDouble(pair[0]) : null;
      final y = pair is List && pair.length >= 2 ? _toDouble(pair[1]) : null;
      if (x == null || y == null) {
        problems.add('$where: points[$i] must be an [x, y] pair of numbers.');
        continue;
      }
      final point = WorldPoint(x, y);
      _checkBounds(point, '$where points[$i]', world);
      points.add(point);
    }
    return points;
  }

  void _checkBounds(WorldPoint point, String where, WorldSpec world) {
    const epsilon = 1e-6;
    final inside =
        point.x >= -epsilon &&
        point.x <= world.width + epsilon &&
        point.y >= -epsilon &&
        point.y <= world.height + epsilon;
    if (!inside) {
      problems.add(
        '$where: position $point is outside the world '
        '(0..${world.width} x 0..${world.height}).',
      );
    }
  }

  int? _color(Object? value) {
    if (value is! String) return null;
    final hex = value.trim().replaceFirst('#', '');
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return switch (hex.length) {
      6 => 0xFF000000 | parsed,
      8 => parsed,
      _ => null,
    };
  }
}

/// Converts [degrees] to radians.
double degreesToRadians(double degrees) => degrees * math.pi / 180;
