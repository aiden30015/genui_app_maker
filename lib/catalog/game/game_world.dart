/// Pure-Dart simulation of a `PhysicsGame`, built on forge2d (Box2D v3).
///
/// Nothing here depends on Flutter widgets, so the rules can be unit tested
/// by calling [GameWorld.step] directly.
///
/// Coordinates are world units (metres) with the origin at the top-left and
/// y growing downward, exactly like the JSON config and like a Flutter
/// canvas. Gravity is therefore a positive y acceleration, and a positive
/// angle is a clockwise rotation on screen.
library;

import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import 'game_spec.dart';

/// Lifecycle of a game.
enum GameStatus { playing, won, lost }

/// A body in the running game: its config plus its current transform.
///
/// The transform is copied out of the physics engine after every step so the
/// painter can read it without calling into native code.
class GameBody {
  GameBody._(this.spec) : x = spec.x, y = spec.y;

  final BodySpec spec;

  /// Current position of the body origin in world units.
  double x;
  double y;

  /// Current rotation in radians (clockwise on screen).
  double angle = 0;

  /// Ball only: waiting at its start position for a launch.
  bool held = false;

  /// Seconds left of the "just hit" highlight (bumpers, targets).
  double flash = 0;

  Body? _body;
  RevoluteJoint? _joint;
  double _restAngle = 0;
  double _activeAngle = 0;
  double _paddleTargetX = 0;
  bool _removed = false;

  BodyKind get kind => spec.kind;

  /// Tip position of a flipper in world units.
  ({double x, double y}) get flipperTip {
    final direction = spec.side == FlipperSide.left ? 1.0 : -1.0;
    return (
      x: x + math.cos(angle) * spec.length * direction,
      y: y + math.sin(angle) * spec.length * direction,
    );
  }
}

/// The simulation. Create one per game; call [dispose] when done because the
/// underlying Box2D world is native memory.
class GameWorld {
  /// Builds the world described by [spec].
  ///
  /// Throws [GameConfigException] when [spec] has validation problems.
  GameWorld(this.spec) {
    if (!spec.isValid) throw GameConfigException(spec.problems);
    _build();
  }

  /// Physics step used by [advance].
  static const double fixedDt = 1 / 120;

  /// Largest wall-clock gap [advance] will simulate. Anything longer (app
  /// was in the background, debugger pause) is dropped instead of replayed.
  static const double maxFrameTime = 0.1;

  static const int _subSteps = 4;
  static const double _flipperUpSpeed = 15; // rad/s
  static const double _flipperDownSpeed = 10; // rad/s
  static const double _paddleMaxSpeed = 40; // m/s
  static const double _escapeMargin = 2; // m outside the world
  static const double _flashSeconds = 0.15;

  // Collision categories: flippers only ever touch balls, so they can
  // overlap walls without jamming.
  static const int _categoryDefault = 0x1;
  static const int _categoryBall = 0x2;
  static const int _categoryFlipper = 0x4;

  final GameSpec spec;

  late World _world;
  final List<GameBody> _bodies = [];
  double _accumulator = 0;
  bool _disposed = false;
  bool _leftPressed = false;
  bool _rightPressed = false;

  int _score = 0;
  int _lives = 0;
  GameStatus _status = GameStatus.playing;

  int get score => _score;
  int get lives => _lives;
  GameStatus get status => _status;

  /// Live bodies, in config order. Destroyed bricks are not included.
  List<GameBody> get bodies => List.unmodifiable(_bodies);

  /// Looks up a live body by its config id.
  GameBody? bodyById(String id) =>
      _bodies.where((body) => body.spec.id == id).firstOrNull;

  int get remainingBricks =>
      _bodies.where((body) => body.kind == BodyKind.brick).length;

  /// Whether a ball is waiting to be launched.
  bool get hasHeldBall => _bodies.any((body) => body.held);

  // --- input --------------------------------------------------------------

  void pressLeftFlipper() => _setFlippers(FlipperSide.left, true);
  void releaseLeftFlipper() => _setFlippers(FlipperSide.left, false);
  void pressRightFlipper() => _setFlippers(FlipperSide.right, true);
  void releaseRightFlipper() => _setFlippers(FlipperSide.right, false);

  /// Moves every paddle toward world x = [x]. The paddle is driven by
  /// velocity (not teleported) so it still pushes the ball correctly.
  void movePaddleTo(double x) {
    for (final body in _bodies) {
      if (body.kind != BodyKind.paddle) continue;
      final half = body.spec.width / 2;
      final low = math.min(half, spec.world.width / 2);
      final high = math.max(spec.world.width - half, spec.world.width / 2);
      body._paddleTargetX = x.clamp(low, high);
    }
  }

  /// Launches every ball that is waiting at its start position.
  ///
  /// Returns whether a ball was launched. A ball that rolled back and came
  /// to rest at its start position counts as waiting.
  bool launchBall() {
    if (_status != GameStatus.playing || _disposed) return false;
    var launched = false;
    for (final ball in _bodies) {
      if (ball.kind != BodyKind.ball) continue;
      final body = ball._body!;
      if (!ball.held) {
        final offset = math.sqrt(
          math.pow(ball.x - ball.spec.x, 2) + math.pow(ball.y - ball.spec.y, 2),
        );
        final resting =
            body.linearVelocity.length < 0.3 &&
            offset < math.max(ball.spec.radius * 2, 0.5);
        if (!resting) continue;
      }
      ball.held = false;
      body.type = BodyType.dynamic;
      body.linearVelocity = _launchVelocity(ball.spec);
      body.isAwake = true;
      launched = true;
    }
    return launched;
  }

  // --- simulation ---------------------------------------------------------

  /// Advances the game by [elapsed] wall-clock seconds using fixed
  /// [fixedDt] steps. Leftover time is carried over to the next call.
  void advance(double elapsed) {
    if (_disposed || _status != GameStatus.playing) return;
    if (elapsed.isNaN || elapsed <= 0) return;
    _accumulator += math.min(elapsed, maxFrameTime);
    // The epsilon keeps 12 * (1/120) from being treated as 11 steps.
    while (_accumulator >= fixedDt - 1e-9 && _status == GameStatus.playing) {
      step(fixedDt);
      _accumulator -= fixedDt;
    }
    if (_status != GameStatus.playing) _accumulator = 0;
  }

  /// Runs exactly one physics step of [dt] seconds and applies the rules.
  void step(double dt) {
    if (_disposed || _status != GameStatus.playing || dt <= 0) return;
    _drivePaddles(dt);
    _world.step(dt, subStepCount: _subSteps);
    _syncTransforms(dt);
    _handleContacts();
    _clampBallSpeeds();
    _checkWin();
    if (_status == GameStatus.playing) _checkLostBalls();
  }

  /// Starts the same game again from the beginning.
  void restart() {
    if (_disposed) return;
    _world.destroy();
    _build();
  }

  /// Frees the native world. The instance must not be used afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _world.destroy();
    _bodies.clear();
  }

  // --- construction -------------------------------------------------------

  void _build() {
    _bodies.clear();
    _accumulator = 0;
    _score = 0;
    _lives = spec.rules.lives;
    _status = GameStatus.playing;
    _world = World(gravity: Vector2(0, spec.world.gravity));
    final ground = _world.createBody();

    for (final bodySpec in spec.bodies) {
      final body = GameBody._(bodySpec);
      switch (bodySpec.kind) {
        case BodyKind.wall:
          _buildWall(body, ground);
        case BodyKind.ball:
          _buildBall(body);
        case BodyKind.flipper:
          _buildFlipper(body, ground);
        case BodyKind.paddle:
          _buildBox(body, BodyType.kinematic);
          body._paddleTargetX = bodySpec.x;
        case BodyKind.brick:
          _buildBox(body, BodyType.static);
        case BodyKind.bumper:
          _buildCircle(body);
        case BodyKind.target:
          bodySpec.isBox
              ? _buildBox(body, BodyType.static)
              : _buildCircle(body);
      }
      _bodies.add(body);
    }
    _setFlippers(FlipperSide.left, _leftPressed);
    _setFlippers(FlipperSide.right, _rightPressed);
  }

  ShapeDef _shapeDef(
    GameBody owner, {
    double density = 1,
    double friction = 0.2,
    int category = _categoryDefault,
    int mask = Filter.allCategories,
  }) => ShapeDef(
    density: density,
    material: SurfaceMaterial(
      friction: friction,
      restitution: owner.spec.restitution,
    ),
    filter: Filter(categoryBits: category, maskBits: mask),
    userData: owner,
    enableContactEvents: true,
  );

  void _buildWall(GameBody wall, Body ground) {
    // Capsules rather than a Box2D chain: chains are one-sided, capsules
    // collide from both sides and their round ends give smooth corners.
    final points = wall.spec.points;
    final radius = wall.spec.thickness / 2;
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i];
      final b = points[i + 1];
      if ((a.x - b.x).abs() < 1e-4 && (a.y - b.y).abs() < 1e-4) continue;
      ground.createShape(
        Capsule(
          center1: Vector2(a.x, a.y),
          center2: Vector2(b.x, b.y),
          radius: radius,
        ),
        _shapeDef(wall),
      );
    }
  }

  void _buildBall(GameBody ball) {
    final spec = ball.spec;
    final hold = this.spec.controls.launchOnTap;
    final body = _world.createBody(
      BodyDef(
        // A waiting ball is static so gravity and flippers cannot move it.
        type: hold ? BodyType.static : BodyType.dynamic,
        position: Vector2(spec.x, spec.y),
        // Continuous collision against moving bodies (flippers, paddles) so
        // a fast ball cannot tunnel through them.
        isBullet: true,
        linearVelocity: !hold && spec.launchSpeed != null
            ? _launchVelocity(spec)
            : null,
      ),
    );
    body.createShape(
      Circle(radius: spec.radius),
      _shapeDef(ball, friction: 0.05, category: _categoryBall),
    );
    ball
      .._body = body
      ..held = hold;
  }

  void _buildCircle(GameBody owner) {
    final body = _world.createBody(
      BodyDef(position: Vector2(owner.spec.x, owner.spec.y)),
    );
    body.createShape(Circle(radius: owner.spec.radius), _shapeDef(owner));
    owner._body = body;
  }

  void _buildBox(GameBody owner, BodyType type) {
    final body = _world.createBody(
      BodyDef(type: type, position: Vector2(owner.spec.x, owner.spec.y)),
    );
    body.createShape(
      Polygon.box(owner.spec.width / 2, owner.spec.height / 2),
      _shapeDef(owner),
    );
    owner._body = body;
  }

  void _buildFlipper(GameBody flipper, Body ground) {
    final spec = flipper.spec;
    final isLeft = spec.side == FlipperSide.left;
    // The left flipper points right from its pivot and the right flipper
    // points left. With y down, a positive angle lowers the left tip and
    // raises the right tip, so the two sides use mirrored angles.
    final rest = degreesToRadians(spec.restAngle) * (isLeft ? 1 : -1);
    final active = degreesToRadians(spec.activeAngle) * (isLeft ? -1 : 1);
    final pivot = Vector2(spec.x, spec.y);

    final body = _world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: pivot,
        rotation: Rot.fromAngle(rest),
        enableSleep: false,
      ),
    );
    body.createShape(
      Capsule(
        center1: Vector2.zero(),
        center2: Vector2(isLeft ? spec.length : -spec.length, 0),
        radius: spec.thickness / 2,
      ),
      _shapeDef(
        flipper,
        density: 5,
        category: _categoryFlipper,
        mask: _categoryBall,
      ),
    );

    // Inertia about the pivot (parallel axis theorem); the motor torque is
    // scaled from it so flippers of any size accelerate equally hard.
    final inertia =
        body.rotationalInertia + body.mass * math.pow(spec.length / 2, 2);
    final joint = _world.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: ground,
        bodyB: body,
        localAnchorA: pivot,
        // The reference angle makes "joint angle 0" mean "horizontal", so
        // the limits below are the flipper's absolute angles.
        referenceAngle: 0,
        enableLimit: true,
        lowerAngle: math.min(rest, active),
        upperAngle: math.max(rest, active),
        enableMotor: true,
        maxMotorTorque: inertia * 1500,
      ),
    );

    flipper
      .._body = body
      .._joint = joint
      .._restAngle = rest
      .._activeAngle = active
      ..angle = rest;
  }

  // --- per-step helpers ---------------------------------------------------

  void _setFlippers(FlipperSide side, bool pressed) {
    if (side == FlipperSide.left) {
      _leftPressed = pressed;
    } else {
      _rightPressed = pressed;
    }
    if (_disposed) return;
    for (final flipper in _bodies) {
      if (flipper.kind != BodyKind.flipper || flipper.spec.side != side) {
        continue;
      }
      final towardActive = (flipper._activeAngle - flipper._restAngle).sign;
      flipper._joint!
        ..motorSpeed = pressed
            ? towardActive * _flipperUpSpeed
            : -towardActive * _flipperDownSpeed
        ..wakeBodies();
    }
  }

  void _drivePaddles(double dt) {
    for (final paddle in _bodies) {
      if (paddle.kind != BodyKind.paddle) continue;
      final velocity = ((paddle._paddleTargetX - paddle.x) / dt).clamp(
        -_paddleMaxSpeed,
        _paddleMaxSpeed,
      );
      paddle._body!.linearVelocity = Vector2(velocity, 0);
    }
  }

  void _syncTransforms(double dt) {
    for (final body in _bodies) {
      if (body.flash > 0) body.flash = math.max(0, body.flash - dt);
      final physics = body._body;
      if (physics == null) continue;
      switch (body.kind) {
        case BodyKind.ball || BodyKind.paddle:
          final position = physics.position;
          body
            ..x = position.x
            ..y = position.y;
        case BodyKind.flipper:
          body.angle = physics.angle;
        default:
          break;
      }
    }
  }

  void _handleContacts() {
    for (final event in _world.contactEvents.begin) {
      final a = event.shapeA.userData;
      final b = event.shapeB.userData;
      if (a is! GameBody || b is! GameBody) continue;
      if (a.kind == BodyKind.ball) {
        _onBallHit(a, b);
      } else if (b.kind == BodyKind.ball) {
        _onBallHit(b, a);
      }
    }
  }

  /// The bumper the ball hit last, and how many times in a row. Walls do not
  /// break the streak: the usual endless loop is bumper <-> ceiling.
  GameBody? _lastBumper;
  int _sameBumperHits = 0;

  void _onBallHit(GameBody ball, GameBody other) {
    if (other._removed) return;
    if (other.kind != BodyKind.wall && !identical(other, _lastBumper)) {
      _lastBumper = other.kind == BodyKind.bumper ? other : null;
      _sameBumperHits = 0;
    }
    switch (other.kind) {
      case BodyKind.bumper:
        _score += other.spec.score;
        other.flash = _flashSeconds;
        _sameBumperHits++;
        if (_sameBumperHits >= 3) _kickOffBumper(ball, other);
      case BodyKind.target:
        _score += other.spec.score;
        other.flash = _flashSeconds;
      case BodyKind.brick:
        _score += other.spec.score;
        other._removed = true;
        other._body?.destroy();
        _bodies.remove(other);
      case BodyKind.paddle:
        _steerOffPaddle(ball, other);
      default:
        break;
    }
  }

  /// Breaks an endless bounce on one bumper. A ball dropped exactly above a
  /// bumper (restitution > 1) otherwise bounces straight up and down forever,
  /// farming score. From the third hit in a row it gets a sideways push,
  /// alternating direction when it sits dead centre.
  void _kickOffBumper(GameBody ball, GameBody bumper) {
    final body = ball._body!;
    final velocity = body.linearVelocity;
    final dx = ball.x - bumper.x;
    final side = dx.abs() > 1e-3
        ? dx.sign
        : (_sameBumperHits.isEven ? 1.0 : -1.0);
    body.linearVelocity = Vector2(
      velocity.x + side * math.max(velocity.length * 0.4, 1.5),
      velocity.y,
    );
  }

  /// Classic breakout steering: where the ball lands on the paddle decides
  /// the outgoing direction, so the player can aim and the ball cannot get
  /// stuck bouncing straight up and down.
  void _steerOffPaddle(GameBody ball, GameBody paddle) {
    final body = ball._body!;
    final speed = body.linearVelocity.length;
    if (speed < 1e-3) return;
    final offset = ((ball.x - paddle.x) / (paddle.spec.width / 2)).clamp(
      -1.0,
      1.0,
    );
    final angle = offset * degreesToRadians(60);
    final away = ball.y <= paddle.y ? -1.0 : 1.0;
    body.linearVelocity = Vector2(
      math.sin(angle) * speed,
      math.cos(angle) * speed * away,
    );
  }

  void _clampBallSpeeds() {
    for (final ball in _bodies) {
      if (ball.kind != BodyKind.ball || ball.held) continue;
      final min = ball.spec.minSpeed;
      final max = ball.spec.maxSpeed;
      if (min == null && max == null) continue;
      final body = ball._body!;
      final velocity = body.linearVelocity;
      final speed = velocity.length;
      if (max != null && speed > max) {
        body.linearVelocity = velocity..scale(max / speed);
      } else if (min != null && min > 0 && speed < min) {
        body.linearVelocity = speed < 1e-6
            ? Vector2(0, -min)
            : (velocity..scale(min / speed));
        body.isAwake = true;
      }
    }
  }

  void _checkWin() {
    final rules = spec.rules;
    final winScore = rules.winScore;
    if ((winScore != null && _score >= winScore) ||
        (rules.winWhenNoBricks && remainingBricks == 0)) {
      _status = GameStatus.won;
    }
  }

  void _checkLostBalls() {
    final world = spec.world;
    for (final ball in _bodies) {
      if (ball.kind != BodyKind.ball || ball.held) continue;
      final fellOut = ball.y - ball.spec.radius > spec.rules.loseBelow;
      // Safety net for tables without a full border: a ball that flies off
      // any other side would otherwise leave the game stuck.
      final escaped =
          ball.x < -_escapeMargin ||
          ball.x > world.width + _escapeMargin ||
          ball.y < -_escapeMargin;
      if (!fellOut && !escaped) continue;

      _lives -= 1;
      if (_lives <= 0) {
        _lives = 0;
        _status = GameStatus.lost;
        return;
      }
      _respawn(ball);
    }
  }

  void _respawn(GameBody ball) {
    final spec = ball.spec;
    final hold = this.spec.controls.launchOnTap;
    final body = ball._body!;
    // Zero the motion while the body is still dynamic, then switch type.
    body
      ..setTransform(Vector2(spec.x, spec.y), const Rot.identity())
      ..angularVelocity = 0
      ..linearVelocity = !hold && spec.launchSpeed != null
          ? _launchVelocity(spec)
          : Vector2.zero();
    if (hold) {
      body.type = BodyType.static;
    } else {
      body.isAwake = true;
    }
    ball
      ..x = spec.x
      ..y = spec.y
      ..held = hold;
  }

  Vector2 _launchVelocity(BodySpec ball) {
    final gravity = spec.world.gravity;
    // Default: just enough to climb from the start position to the top of
    // the world (v² = 2gh), plus a little so it arrives still moving.
    final speed =
        ball.launchSpeed ??
        (gravity > 0
            ? math.max(5, math.sqrt(2 * gravity * math.max(ball.y, 1)) * 1.1)
            : 8.0);
    final angle = degreesToRadians(ball.launchAngle);
    return Vector2(math.cos(angle) * speed, -math.sin(angle) * speed);
  }
}
