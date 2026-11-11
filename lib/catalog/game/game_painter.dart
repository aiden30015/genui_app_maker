import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'game_spec.dart';
import 'game_world.dart';

/// Maps world units (metres) onto a widget, preserving the aspect ratio.
///
/// The world is scaled uniformly to fit and centred, so the same mapping is
/// used for painting and for turning a touch position back into world x.
class GameViewport {
  GameViewport(WorldSpec world, Size size)
    : scale = math.min(size.width / world.width, size.height / world.height) {
    offset = Offset(
      (size.width - world.width * scale) / 2,
      (size.height - world.height * scale) / 2,
    );
  }

  /// Pixels per world unit.
  final double scale;

  /// Top-left corner of the world inside the widget, in pixels.
  late final Offset offset;

  /// Converts a widget-local x to world x.
  double toWorldX(double localX) =>
      scale > 0 ? (localX - offset.dx) / scale : 0;
}

/// Draws the bodies of a [GameWorld].
///
/// It repaints whenever [repaint] notifies (once per ticker frame), which
/// avoids rebuilding any widgets while the game is running.
class GamePainter extends CustomPainter {
  GamePainter({required this.world, required Listenable repaint})
    : super(repaint: repaint);

  final GameWorld world;

  static const Color background = Color(0xFF0F172A);
  static const Color _flashColor = Color(0xFFFFFFFF);

  static const Map<BodyKind, Color> defaultColors = {
    BodyKind.ball: Color(0xFFF8FAFC),
    BodyKind.wall: Color(0xFF94A3B8),
    BodyKind.bumper: Color(0xFFF97316),
    BodyKind.flipper: Color(0xFF38BDF8),
    BodyKind.paddle: Color(0xFF38BDF8),
    BodyKind.brick: Color(0xFF22C55E),
    BodyKind.target: Color(0xFFE879F9),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final spec = world.spec.world;
    final viewport = GameViewport(spec, size);
    if (viewport.scale <= 0 || !viewport.scale.isFinite) return;

    canvas
      ..save()
      ..translate(viewport.offset.dx, viewport.offset.dy)
      ..scale(viewport.scale);

    // From here on everything is drawn in world units.
    final bounds = Rect.fromLTWH(0, 0, spec.width, spec.height);
    canvas
      ..clipRect(bounds)
      ..drawRect(bounds, Paint()..color = background);

    for (final body in world.bodies) {
      _paintBody(canvas, body);
    }
    canvas.restore();
  }

  void _paintBody(Canvas canvas, GameBody body) {
    final spec = body.spec;
    final base = spec.color != null
        ? Color(spec.color!)
        : defaultColors[body.kind]!;
    final color = body.flash > 0 ? Color.lerp(base, _flashColor, 0.7)! : base;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final center = Offset(body.x, body.y);

    switch (body.kind) {
      case BodyKind.ball:
        canvas.drawCircle(center, spec.radius, fill);
      case BodyKind.bumper:
        canvas
          ..drawCircle(center, spec.radius, fill)
          ..drawCircle(
            center,
            spec.radius * 0.55,
            Paint()..color = background.withValues(alpha: 0.35),
          );
      case BodyKind.wall:
        if (spec.points.length < 2) return;
        final path = Path()..moveTo(spec.points.first.x, spec.points.first.y);
        for (final point in spec.points.skip(1)) {
          path.lineTo(point.x, point.y);
        }
        canvas.drawPath(path, _stroke(color, spec.thickness));
      case BodyKind.flipper:
        final tip = body.flipperTip;
        canvas.drawLine(
          center,
          Offset(tip.x, tip.y),
          _stroke(color, spec.thickness),
        );
      case BodyKind.paddle || BodyKind.brick:
        _paintBox(canvas, body, fill);
      case BodyKind.target:
        if (spec.isBox) {
          _paintBox(canvas, body, fill);
        } else {
          canvas.drawCircle(center, spec.radius, fill);
        }
    }
  }

  void _paintBox(Canvas canvas, GameBody body, Paint fill) {
    final rect = Rect.fromCenter(
      center: Offset(body.x, body.y),
      width: body.spec.width,
      height: body.spec.height,
    );
    final corner = Radius.circular(math.min(rect.shortestSide * 0.25, 0.12));
    canvas.drawRRect(RRect.fromRectAndRadius(rect, corner), fill);
  }

  Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  @override
  bool shouldRepaint(GamePainter oldDelegate) => oldDelegate.world != world;
}
