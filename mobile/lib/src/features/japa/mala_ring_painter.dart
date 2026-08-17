import 'dart:math';

import 'package:flutter/material.dart';

/// The Mala Ring (docs/FRONTEND_GUIDELINES.md §5): a circular ring of
/// [totalBeads] beads, split into quarters with a small gap between each —
/// "readable at a glance" groups rather than a smooth arc — filling one at
/// a time in [filledColor] as taps come in.
class MalaRingPainter extends CustomPainter {
  MalaRingPainter({
    required this.totalBeads,
    required this.filledCount,
    required this.pulseBeadIndex,
    required this.pulseScale,
    required this.filledColor,
    required this.unfilledColor,
  });

  final int totalBeads;
  final int filledCount;
  final int? pulseBeadIndex;
  final double pulseScale;
  final Color filledColor;
  final Color unfilledColor;

  static const _groupSize = 27;
  static const _groupGapRadians = 0.09;

  /// Fraction of the center-to-center arc spacing a bead's diameter fills —
  /// the rest is the visible gap between adjacent beads. Below ~0.7 the
  /// beads read as a continuous ring instead of distinct beads.
  static const _beadFillRatio = 0.62;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 14;

    final groupCount = (totalBeads / _groupSize).ceil();
    final anglePerBead = (2 * pi - groupCount * _groupGapRadians) / totalBeads;
    // The arc length between adjacent bead centers is what actually bounds
    // how big a bead can be without overlapping its neighbor — not an
    // arbitrary fraction of the canvas size.
    final arcSpacing = radius * anglePerBead;
    final beadRadius = (arcSpacing * _beadFillRatio) / 2;

    var angle = -pi / 2; // start at the top, like a clock face
    for (var i = 0; i < totalBeads; i++) {
      if (i > 0 && i % _groupSize == 0) {
        angle += _groupGapRadians;
      }

      final isFilled = i < filledCount;
      final scale = i == pulseBeadIndex ? pulseScale : 1.0;
      final offset = center + Offset(cos(angle), sin(angle)) * radius;

      if (isFilled) {
        final paint = Paint()..color = filledColor;
        canvas.drawCircle(offset, beadRadius * scale, paint);
      } else {
        final paint = Paint()
          ..color = unfilledColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(offset, beadRadius * scale, paint);
      }

      angle += anglePerBead;
    }
  }

  @override
  bool shouldRepaint(covariant MalaRingPainter oldDelegate) {
    return oldDelegate.filledCount != filledCount ||
        oldDelegate.pulseBeadIndex != pulseBeadIndex ||
        oldDelegate.pulseScale != pulseScale ||
        oldDelegate.filledColor != filledColor ||
        oldDelegate.unfilledColor != unfilledColor;
  }
}
