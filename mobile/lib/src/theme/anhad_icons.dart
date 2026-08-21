/// The five P0 renamed-interaction icons (docs/FRONTEND_GUIDELINES.md §7):
/// hand-drawn shapes via [CustomPainter], the same convention the Mala Ring
/// (japa/mala_ring_painter.dart) and Sapta Swara
/// (onboarding/sapta_swara_painter.dart) already use — not a generic
/// Material icon re-labeled, since the guidelines are explicit that the
/// icon shape itself is part of what signals "this isn't Instagram."
///
/// Every icon shares the same two-state shape: a thin outline when
/// inactive, the same path filled solid when active — mirroring how a
/// standard like/heart icon communicates state, but with Anhad's own
/// vocabulary of shapes instead. Jugalbandi (remix/duet, P1) has no icon
/// here — it isn't built yet (docs/PRD.md §7.2).
library;

import 'dart:math';

import 'package:flutter/widgets.dart';

class AnhadIconStyle {
  const AnhadIconStyle(
      {required this.color, required this.filled, this.strokeWidth = 1.6});

  final Color color;
  final bool filled;
  final double strokeWidth;

  Paint toPaint() {
    if (filled) {
      return Paint()
        ..color = color
        ..style = PaintingStyle.fill;
    }
    return Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
  }
}

/// Pranam (Like) — folded hands, drawn as two separate pill/lozenge shapes
/// standing side by side with real negative space between them (not a
/// single blob cut by a thin line — a stroke that thin disappears at rail
/// size, and a "seam" that isn't actually a gap reads as one shape, not
/// two). Each pill is rounder at the top (fingertips) than the bottom
/// (wrists), so the pair reads as two hands held up together, not two
/// identical rounded rectangles.
class PranamIcon extends StatelessWidget {
  const PranamIcon(
      {super.key, required this.filled, required this.color, this.size = 24});

  final bool filled;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PranamPainter(AnhadIconStyle(color: color, filled: filled)),
    );
  }
}

class _PranamPainter extends CustomPainter {
  _PranamPainter(this.style);
  final AnhadIconStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final gap = w * 0.10;
    final halfWidth = w * 0.32;
    final top = h * 0.10;
    final bottom = h * 0.90;
    final topRadius = Radius.circular(halfWidth);
    final bottomRadius = Radius.circular(halfWidth * 0.35);

    final left = RRect.fromRectAndCorners(
      Rect.fromLTRB(
          w * 0.5 - gap / 2 - halfWidth, top, w * 0.5 - gap / 2, bottom),
      topLeft: topRadius,
      topRight: topRadius,
      bottomLeft: bottomRadius,
      bottomRight: bottomRadius,
    );
    final right = RRect.fromRectAndCorners(
      Rect.fromLTRB(
          w * 0.5 + gap / 2, top, w * 0.5 + gap / 2 + halfWidth, bottom),
      topLeft: topRadius,
      topRight: topRadius,
      bottomLeft: bottomRadius,
      bottomRight: bottomRadius,
    );

    final paint = style.toPaint();
    canvas.drawRRect(left, paint);
    canvas.drawRRect(right, paint);
  }

  @override
  bool shouldRepaint(covariant _PranamPainter oldDelegate) =>
      oldDelegate.style.filled != style.filled ||
      oldDelegate.style.color != style.color;
}

/// Satsang (Comment) — a speech shape built from a soft lotus-petal
/// silhouette (pointed at top, rounded at the base) with a small tail, so
/// it reads as "speech bubble" at a glance without being a generic rounded
/// rectangle chat icon.
class SatsangIcon extends StatelessWidget {
  const SatsangIcon(
      {super.key, required this.filled, required this.color, this.size = 24});

  final bool filled;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SatsangPainter(AnhadIconStyle(color: color, filled: filled)),
    );
  }
}

class _SatsangPainter extends CustomPainter {
  _SatsangPainter(this.style);
  final AnhadIconStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, h * 0.04) // petal tip
      ..cubicTo(w * 0.90, h * 0.10, w * 0.94, h * 0.55, w * 0.68, h * 0.72)
      ..cubicTo(w * 0.60, h * 0.77, w * 0.50, h * 0.78, w * 0.42, h * 0.76)
      ..lineTo(w * 0.22, h * 0.92) // the small tail, like a chat bubble's
      ..lineTo(w * 0.28, h * 0.70)
      ..cubicTo(w * 0.10, h * 0.58, w * 0.10, h * 0.14, w * 0.5, h * 0.04)
      ..close();
    canvas.drawPath(path, style.toPaint());
  }

  @override
  bool shouldRepaint(covariant _SatsangPainter oldDelegate) =>
      oldDelegate.style.filled != style.filled ||
      oldDelegate.style.color != style.color;
}

/// Prasad (Share) — a single simple leaf/offering shape echoing the
/// Tulsi-leaf material FRONTEND_GUIDELINES.md §2 already grounds
/// `accent-success` in: one smooth teardrop (pointed stem at the bottom,
/// rounded crown at the top), tilted ~25° off vertical. Deliberately no
/// internal vein or asymmetric bulge — those add detail that just turns to
/// noise at rail size (~24-26px); the tilt alone is what keeps this from
/// reading as the same upright silhouette as Pranam's two pills.
class PrasadIcon extends StatelessWidget {
  const PrasadIcon(
      {super.key, required this.filled, required this.color, this.size = 24});

  final bool filled;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PrasadPainter(AnhadIconStyle(color: color, filled: filled)),
    );
  }
}

class _PrasadPainter extends CustomPainter {
  _PrasadPainter(this.style);
  final AnhadIconStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.save();
    canvas.translate(w * 0.5, h * 0.5);
    canvas.rotate(-0.44); // ~25 degrees, leaf tilted like it's mid-offering
    canvas.translate(-w * 0.5, -h * 0.5);

    // One smooth teardrop: pointed stem at the bottom, rounded crown at
    // the top — the whole shape is two mirrored cubic curves, nothing else.
    final stem = Offset(w * 0.5, h * 0.92);
    final crown = Offset(w * 0.5, h * 0.10);
    final leaf = Path()
      ..moveTo(stem.dx, stem.dy)
      ..cubicTo(w * 0.06, h * 0.70, w * 0.06, h * 0.24, crown.dx, crown.dy)
      ..cubicTo(w * 0.94, h * 0.24, w * 0.94, h * 0.70, stem.dx, stem.dy)
      ..close();
    canvas.drawPath(leaf, style.toPaint());

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PrasadPainter oldDelegate) =>
      oldDelegate.style.filled != style.filled ||
      oldDelegate.style.color != style.color;
}

/// Smaran (Save) — a single mala bead threaded on a string: a straight
/// line running the full height of the icon with one bead centered on it,
/// the thread visibly poking out above and below the bead. Simpler and
/// clearer at rail size (~24-26px) than the earlier version's disconnected
/// arc floating over the bead, which read as two unrelated marks rather
/// than "bead on a string."
class SmaranIcon extends StatelessWidget {
  const SmaranIcon(
      {super.key, required this.filled, required this.color, this.size = 24});

  final bool filled;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SmaranPainter(AnhadIconStyle(color: color, filled: filled)),
    );
  }
}

class _SmaranPainter extends CustomPainter {
  _SmaranPainter(this.style);
  final AnhadIconStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final threadPaint = Paint()
      ..color = style.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(w * 0.5, h * 0.06), Offset(w * 0.5, h * 0.94), threadPaint);

    // Drawn after the thread so a filled bead visibly interrupts it,
    // leaving the thread showing only above and below — that's what sells
    // "threaded," not the line alone.
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.27, style.toPaint());
  }

  @override
  bool shouldRepaint(covariant _SmaranPainter oldDelegate) =>
      oldDelegate.style.filled != style.filled ||
      oldDelegate.style.color != style.color;
}

/// Sevak (Follow) — a small five-petal flower mark, distinct from a
/// generic "+" or person-outline follow icon.
class SevakIcon extends StatelessWidget {
  const SevakIcon(
      {super.key, required this.filled, required this.color, this.size = 24});

  final bool filled;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SevakPainter(AnhadIconStyle(color: color, filled: filled)),
    );
  }
}

class _SevakPainter extends CustomPainter {
  _SevakPainter(this.style);
  final AnhadIconStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final petalRadius = size.shortestSide * 0.30;
    final petalDistance = size.shortestSide * 0.24;
    final paint = style.toPaint();

    for (var i = 0; i < 5; i++) {
      final angle = (-90 + i * 72) * pi / 180;
      final petalCenter = center +
          Offset(petalDistance * cos(angle), petalDistance * sin(angle));
      canvas.drawCircle(petalCenter, petalRadius, paint);
    }

    // A small center disc ties the petals together into one flower rather
    // than five separate dots, filled or outlined the same way the petals
    // are so the mark reads as one mark at small sizes.
    canvas.drawCircle(center, size.shortestSide * 0.12, style.toPaint());
  }

  @override
  bool shouldRepaint(covariant _SevakPainter oldDelegate) =>
      oldDelegate.style.filled != style.filled ||
      oldDelegate.style.color != style.color;
}
