import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'game_painter.dart';
import 'game_spec.dart';
import 'game_world.dart';

final Schema _bodySchema = S.object(
  description:
      'One physical object. Which properties apply depends on "type". '
      'All positions and sizes are in world units (metres).',
  properties: {
    'id': S.string(description: 'Unique id of the body.'),
    'type': S.string(
      description:
          'ball: the moving ball (at least one is required). '
          'wall: static polyline given by "points". '
          'bumper: static circle that bounces the ball away and gives '
          '"score". '
          'flipper: pinball flipper hinged at (x, y); needs "side". '
          'paddle: horizontal bar the player drags left/right. '
          'brick: box that disappears when hit and gives "score". '
          'target: static shape that gives "score" on every hit and stays.',
      enumValues: BodyKind.values.map((kind) => kind.name).toList(),
    ),
    'x': S.number(
      description:
          'Centre x (for a flipper: the pivot). 0 is the left edge. Required '
          'for every type except wall. Must be inside 0..world.width.',
    ),
    'y': S.number(
      description:
          'Centre y (for a flipper: the pivot). 0 is the TOP edge and y '
          'grows downward. Required for every type except wall. Must be '
          'inside 0..world.height.',
    ),
    'radius': S.number(
      description:
          'Radius of a ball (default 0.25), bumper (default 0.5) or round '
          'target (default 0.3).',
    ),
    'width': S.number(
      description:
          'Width of a paddle (default 2) or brick (default 1). Give a target '
          'width and height to make it a box instead of a circle.',
    ),
    'height': S.number(
      description: 'Height of a paddle (default 0.3) or brick (default 0.4).',
    ),
    'points': S.list(
      description:
          'wall only: the polyline as [[x, y], [x, y], ...] with at least two '
          'points. Repeat the first point at the end to close a shape.',
      items: S.list(items: S.number(), minItems: 2, maxItems: 2),
    ),
    'thickness': S.number(
      description:
          'Thickness of a wall (default 0.1) or flipper (default 0.3).',
    ),
    'side': S.string(
      description:
          'flipper only (required). "left": pivot on the left, tip points '
          'right. "right": pivot on the right, tip points left. Place the '
          'two pivots apart so the tips nearly meet in the middle.',
      enumValues: FlipperSide.values.map((side) => side.name).toList(),
    ),
    'length': S.number(
      description: 'flipper only: pivot-to-tip length (default 1.8).',
    ),
    'restAngle': S.number(
      description:
          'flipper only: degrees the tip hangs below horizontal when '
          'released (default 30).',
    ),
    'activeAngle': S.number(
      description:
          'flipper only: degrees the tip rises above horizontal when '
          'pressed (default 30).',
    ),
    'score': S.number(
      description: 'Points per hit. Defaults: bumper 100, brick 10, target 50.',
    ),
    'restitution': S.number(
      description:
          'Bounciness, 0 (dead) to about 1.5. The larger value of the two '
          'touching bodies is used. Defaults: ball 0.5, bumper 1.2, others '
          '0. Use ball restitution 1 with gravity 0 for breakout/pong.',
    ),
    'launchSpeed': S.number(
      description:
          'ball only: launch speed in m/s. Default: just enough to reach the '
          'top of the world. Applied on tap when controls.launch is "tap", '
          'otherwise immediately when the ball (re)spawns. Without it and '
          'without controls.launch the ball simply drops.',
    ),
    'launchAngle': S.number(
      description:
          'ball only: launch direction in degrees. 90 = straight up '
          '(default), 0 = right, 180 = left, 270 = down.',
    ),
    'minSpeed': S.number(
      description:
          'ball only: keep the ball at least this fast (m/s). Set minSpeed '
          'and maxSpeed to the same value for constant-speed breakout/pong.',
    ),
    'maxSpeed': S.number(description: 'ball only: speed limit in m/s.'),
    'color': S.string(description: 'Optional colour as "#RRGGBB".'),
  },
  required: ['type'],
);

final Schema _schema = S.object(
  description:
      'A playable 2D physics game (pinball, breakout, pong-like) described '
      'entirely by data. Coordinates are in metres with the origin at the '
      'TOP-LEFT; y grows downward. The world is scaled to fit the widget. '
      'Always enclose the play field with walls on the left, right and top, '
      'otherwise the ball flies out and a life is lost.',
  properties: {
    'world': S.object(
      description: 'Size of the play field and gravity.',
      properties: {
        'width': S.number(description: 'World width in metres. Default 10.'),
        'height': S.number(description: 'World height in metres. Default 16.'),
        'gravity': S.number(
          description:
              'Downward acceleration in m/s². Default 9.8 (pinball). Use 0 '
              'for breakout and pong.',
        ),
      },
    ),
    'bodies': S.list(
      description: 'Everything in the world. Must contain at least one ball.',
      items: _bodySchema,
      minItems: 1,
    ),
    'controls': S.object(
      description:
          'How touches are mapped to the game. Controls that are left out '
          'are disabled.',
      properties: {
        'tapLeft': S.string(
          description:
              'What touching and holding the LEFT half of the game does. '
              '"flipperLeft" raises every flipper with side "left".',
          enumValues: ['flipperLeft', 'flipperRight'],
        ),
        'tapRight': S.string(
          description:
              'What touching and holding the RIGHT half of the game does. '
              '"flipperRight" raises every flipper with side "right".',
          enumValues: ['flipperLeft', 'flipperRight'],
        ),
        'drag': S.string(
          description: '"paddle": dragging horizontally moves the paddle.',
          enumValues: ['paddle'],
        ),
        'launch': S.string(
          description:
              '"tap": the ball waits frozen at its start position and a tap '
              'anywhere launches it (also after losing a life).',
          enumValues: ['tap'],
        ),
      },
    ),
    'rules': S.object(
      description: 'Lives and win/lose conditions.',
      properties: {
        'lives': S.number(
          description: 'Number of balls (whole number). Default 3.',
        ),
        'loseBelow': S.number(
          description:
              'A ball falling below this y costs a life and respawns at its '
              'start position. Default: world.height.',
        ),
        'winScore': S.combined(
          type: ['number', 'null'],
          description:
              'Reaching this score wins the game. null/omitted: no score '
              'goal.',
        ),
        'winWhenNoBricks': S.boolean(
          description:
              'true: destroying every brick wins the game. Default false.',
        ),
      },
    ),
    'statePath': S.string(
      description:
          'Data model path, e.g. "/game". The game writes {score, lives, '
          'status} there ("status" is "playing", "won" or "lost"), so a Text '
          'can show the score with {"path": "/game/score"}.',
    ),
  },
  required: ['bodies'],
);

/// A complete small pinball table, also used as the LLM-facing example.
const String pinballExample = '''
[
  {"id": "root", "component": "Column", "children": ["hud", "game"]},
  {"id": "hud", "component": "Row", "justify": "spaceBetween", "children": ["scoreText", "livesText"]},
  {"id": "scoreText", "component": "Text", "text": {"path": "/game/score"}, "variant": "h4"},
  {"id": "livesText", "component": "Text", "text": {"path": "/game/lives"}, "variant": "h4"},
  {
    "id": "game",
    "component": "PhysicsGame",
    "world": {"width": 10, "height": 16, "gravity": 9.8},
    "bodies": [
      {"id": "ball", "type": "ball", "x": 9.4, "y": 14.6, "radius": 0.25, "restitution": 0.5},
      {"id": "border", "type": "wall", "points": [[0, 16], [0, 0], [8, 0], [10, 2], [10, 16]]},
      {"id": "lane", "type": "wall", "points": [[8.8, 16], [8.8, 4]]},
      {"id": "laneFloor", "type": "wall", "points": [[8.8, 15], [10, 15]]},
      {"id": "slopeL", "type": "wall", "points": [[0, 12], [2.6, 14]]},
      {"id": "slopeR", "type": "wall", "points": [[8.8, 12], [6.2, 14]]},
      {"id": "b1", "type": "bumper", "x": 3, "y": 4.5, "radius": 0.6, "score": 100},
      {"id": "b2", "type": "bumper", "x": 6, "y": 4.5, "radius": 0.6, "score": 100},
      {"id": "b3", "type": "bumper", "x": 4.5, "y": 7, "radius": 0.6, "score": 100},
      {"id": "t1", "type": "target", "x": 1, "y": 8.5, "radius": 0.3, "score": 50},
      {"id": "t2", "type": "target", "x": 7.8, "y": 8.5, "radius": 0.3, "score": 50},
      {"id": "fl", "type": "flipper", "side": "left", "x": 2.6, "y": 14, "length": 1.6},
      {"id": "fr", "type": "flipper", "side": "right", "x": 6.2, "y": 14, "length": 1.6}
    ],
    "controls": {"tapLeft": "flipperLeft", "tapRight": "flipperRight", "launch": "tap"},
    "rules": {"lives": 3, "loseBelow": 16, "winScore": null},
    "statePath": "/game"
  }
]
''';

/// Catalog item for the configurable 2D physics game.
///
/// `isImplicitlyFlexible` makes genui's Column/Row wrap the game in a loose
/// `Flexible`: inside a bounded Column the game gets the remaining height and
/// shrinks to fit it, instead of overflowing.
final CatalogItem physicsGameItem = CatalogItem(
  name: 'PhysicsGame',
  dataSchema: _schema,
  isImplicitlyFlexible: true,
  widgetBuilder: (CatalogItemContext itemContext) {
    final Object data = itemContext.data;
    final spec = GameSpec.fromJson(
      data is Map ? Map<String, Object?>.from(data) : const {},
    );

    // genui only forwards the message of an A2uiValidationException to the
    // LLM; any other error type is reduced to a generic "INTERNAL_ERROR".
    void report(List<String> problems) => itemContext.reportError(
      A2uiValidationException(
        GameConfigException(problems).toString(),
        surfaceId: itemContext.surfaceId,
        path: itemContext.id,
      ),
      StackTrace.current,
    );

    if (!spec.isValid) {
      return GameErrorPanel(problems: spec.problems, onReport: report);
    }

    final statePath = spec.statePath;
    return PhysicsGameView(
      spec: spec,
      onReport: report,
      onStateChanged: statePath == null
          ? null
          : (GameStateSnapshot state) {
              itemContext.dataContext.update(
                DataPath(statePath),
                state.toJson(),
              );
            },
    );
  },
  exampleData: [() => pinballExample],
);

/// The values shared with the rest of the generated UI through `statePath`.
@immutable
class GameStateSnapshot {
  const GameStateSnapshot({
    required this.score,
    required this.lives,
    required this.status,
  });

  GameStateSnapshot.of(GameWorld world)
    : score = world.score,
      lives = world.lives,
      status = world.status;

  final int score;
  final int lives;
  final GameStatus status;

  Map<String, Object?> toJson() => {
    'score': score,
    'lives': lives,
    'status': status.name,
  };

  @override
  bool operator ==(Object other) =>
      other is GameStateSnapshot &&
      other.score == score &&
      other.lives == lives &&
      other.status == status;

  @override
  int get hashCode => Object.hash(score, lives, status);
}

/// Runs and renders one game.
class PhysicsGameView extends StatefulWidget {
  const PhysicsGameView({
    super.key,
    required this.spec,
    this.onStateChanged,
    this.onReport,
  });

  /// A valid spec ([GameSpec.isValid]).
  final GameSpec spec;

  /// Called when score, lives or status change (never per frame).
  final ValueChanged<GameStateSnapshot>? onStateChanged;

  /// Called once per failure when the world cannot be built.
  final ValueChanged<List<String>>? onReport;

  @override
  State<PhysicsGameView> createState() => _PhysicsGameViewState();
}

class _PhysicsGameViewState extends State<PhysicsGameView>
    with SingleTickerProviderStateMixin {
  /// Notifies the painter once per frame without rebuilding widgets.
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  /// Which half each active pointer went down on (true = left).
  final Map<int, bool> _pointers = {};

  late final Ticker _ticker;
  GameWorld? _world;
  List<String> _buildProblems = const [];
  Duration _lastTick = Duration.zero;
  GameStateSnapshot? _published;
  bool _showLaunchHint = false;
  bool _publishScheduled = false;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _createWorld();
  }

  @override
  void didUpdateWidget(PhysicsGameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The LLM sent a new config: rebuild the simulation from scratch.
    if (oldWidget.spec.signature != widget.spec.signature) {
      _ticker.stop();
      _world?.dispose();
      _pointers.clear();
      _createWorld();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _world?.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _createWorld() {
    _published = null;
    try {
      final world = GameWorld(widget.spec);
      _world = world;
      _buildProblems = const [];
      _showLaunchHint = world.hasHeldBall;
      _startTicker();
    } catch (error) {
      // Physics construction failed (e.g. degenerate geometry). Show the
      // error panel instead of throwing out of build.
      _world = null;
      _buildProblems = error is GameConfigException
          ? error.problems
          : ['Could not build the game world: $error'];
    }
    _schedulePublish();
  }

  void _startTicker() {
    _lastTick = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final world = _world;
    if (world == null) return;
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    world.advance(dt);
    _frame.value++;
    _syncState();
    // Nothing moves after the game ends; stop burning frames.
    if (world.status != GameStatus.playing) _ticker.stop();
  }

  /// Publishes the first state after the frame, because writing to the data
  /// model during build would rebuild widgets that are being built.
  void _schedulePublish() {
    if (_publishScheduled) return;
    _publishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishScheduled = false;
      if (mounted) _syncState();
    });
  }

  /// Pushes score/lives/status outward and rebuilds the overlay, but only
  /// when something actually changed.
  void _syncState() {
    final world = _world;
    if (world == null) return;
    final snapshot = GameStateSnapshot.of(world);
    final hint = world.hasHeldBall;
    final stateChanged = snapshot != _published;
    if (!stateChanged && hint == _showLaunchHint) return;
    setState(() {
      _published = snapshot;
      _showLaunchHint = hint;
    });
    if (stateChanged) {
      try {
        widget.onStateChanged?.call(snapshot);
      } catch (error) {
        widget.onReport?.call([
          'Could not write game state to statePath: $error',
        ]);
      }
    }
  }

  void _restart() {
    final world = _world;
    if (world == null) return;
    world.restart();
    _pointers.clear();
    _startTicker();
    _frame.value++;
    _syncState();
  }

  // --- input --------------------------------------------------------------

  void _onPointerDown(PointerDownEvent event) {
    final world = _world;
    if (world == null || world.status != GameStatus.playing) return;
    final controls = widget.spec.controls;
    _pointers[event.pointer] = event.localPosition.dx < _size.width / 2;
    _applyFlippers();
    if (controls.launchOnTap && world.launchBall()) _syncState();
    _movePaddle(event.localPosition);
  }

  void _onPointerMove(PointerMoveEvent event) =>
      _movePaddle(event.localPosition);

  void _onPointerUp(PointerEvent event) {
    if (_pointers.remove(event.pointer) != null) _applyFlippers();
  }

  void _movePaddle(Offset local) {
    final world = _world;
    if (world == null || !widget.spec.controls.dragPaddle) return;
    final viewport = GameViewport(widget.spec.world, _size);
    world.movePaddleTo(viewport.toWorldX(local.dx));
  }

  /// A flipper side is pressed while at least one finger is down on a half
  /// that is mapped to it, so two fingers can drive both sides at once.
  void _applyFlippers() {
    final world = _world;
    if (world == null) return;
    final controls = widget.spec.controls;
    final leftHalfDown = _pointers.containsValue(true);
    final rightHalfDown = _pointers.containsValue(false);
    bool pressed(FlipperSide side) =>
        (leftHalfDown && controls.tapLeft == side) ||
        (rightHalfDown && controls.tapRight == side);

    pressed(FlipperSide.left)
        ? world.pressLeftFlipper()
        : world.releaseLeftFlipper();
    pressed(FlipperSide.right)
        ? world.pressRightFlipper()
        : world.releaseRightFlipper();
  }

  // --- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final world = _world;
    if (world == null) {
      return GameErrorPanel(
        problems: _buildProblems,
        onReport: widget.onReport,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _size = _fit(context, constraints, widget.spec.world.aspectRatio);
        return Align(
          alignment: Alignment.topCenter,
          widthFactor: constraints.hasBoundedWidth ? null : 1,
          heightFactor: 1,
          child: SizedBox.fromSize(
            size: _size,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The no-op drag handlers claim drags so that a scrollable
                  // ancestor does not scroll while the player is playing.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (_) {},
                    onHorizontalDragUpdate: (_) {},
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerUp,
                      onPointerCancel: _onPointerUp,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: GamePainter(world: world, repaint: _frame),
                        ),
                      ),
                    ),
                  ),
                  if (_showLaunchHint && world.status == GameStatus.playing)
                    const IgnorePointer(
                      child: Align(
                        alignment: Alignment(0, 0.4),
                        child: _Hint(text: '화면을 탭해서 공을 발사하세요'),
                      ),
                    ),
                  if (world.status != GameStatus.playing)
                    _GameOverOverlay(
                      won: world.status == GameStatus.won,
                      score: world.score,
                      onRestart: _restart,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Picks the largest size with the world's aspect ratio that fits.
  ///
  /// With unbounded height (inside a scroll view or a shrink-wrapping
  /// Column) the height is derived from the width, capped so the whole table
  /// stays visible on screen.
  static Size _fit(
    BuildContext context,
    BoxConstraints constraints,
    double aspectRatio,
  ) {
    final screen = MediaQuery.maybeSizeOf(context) ?? const Size(360, 640);
    final maxHeight = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : screen.height * 0.75;
    final maxWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : screen.width;
    final width = math.min(maxWidth, maxHeight * aspectRatio);
    return Size(width, width / aspectRatio);
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  const _GameOverOverlay({
    required this.won,
    required this.score,
    required this.onRestart,
  });

  final bool won;
  final int score;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  won ? '클리어!' : '게임 오버',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '점수 $score',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.refresh),
                  label: const Text('다시 시작'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the game when the config is not playable.
///
/// Reports the problems once (and again only if they change), after the
/// frame, so the LLM gets feedback without a report on every rebuild.
class GameErrorPanel extends StatefulWidget {
  const GameErrorPanel({super.key, required this.problems, this.onReport});

  final List<String> problems;
  final ValueChanged<List<String>>? onReport;

  @override
  State<GameErrorPanel> createState() => _GameErrorPanelState();
}

class _GameErrorPanelState extends State<GameErrorPanel> {
  String? _reported;

  @override
  void initState() {
    super.initState();
    _scheduleReport();
  }

  @override
  void didUpdateWidget(GameErrorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleReport();
  }

  void _scheduleReport() {
    final text = widget.problems.join('\n');
    if (text == _reported) return;
    _reported = text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReport?.call(widget.problems);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '게임 설정에 문제가 있어요',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final problem in widget.problems.take(6))
            Text(
              '• $problem',
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
            ),
          if (widget.problems.length > 6)
            Text(
              '… 외 ${widget.problems.length - 6}건',
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
            ),
        ],
      ),
    );
  }
}
