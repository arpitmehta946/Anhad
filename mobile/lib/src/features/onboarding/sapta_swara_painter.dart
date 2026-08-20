import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'sapta_swara.dart';

/// The seven rippling swara rings (docs/FRONTEND_GUIDELINES.md, "Sapta
/// Swara"). Each ring runs its own independent 6.4s cycle, offset by its
/// [Swara.startOffset] — since every ring shares the same period, that
/// offset holds forever, not just on the very first pass, so the staggered
/// "arising" character persists through every later loop too rather than
/// resetting into lockstep.
class SaptaSwaraPainter extends CustomPainter {
  SaptaSwaraPainter({required this.elapsedMs, this.reduceMotion = false});

  final int elapsedMs;
  final bool reduceMotion;

  static const _ringPeriodMs = 6400;
  static const _startDiameter = 18.0;
  static const _endDiameter = _startDiameter * 4.6;

  @override
  void paint(Canvas canvas, Size size) {
    // Individual rings blend against each other (BlendMode.screen) within
    // this layer, so overlaps brighten rather than just occlude — the
    // layer as a whole still composites normally onto the dark background
    // behind it.
    canvas.saveLayer(Offset.zero & size, Paint());
    for (var i = 0; i < saptaSwaras.length; i++) {
      final swara = saptaSwaras[i];
      final center = Offset(swara.x * size.width, swara.y * size.height);

      double diameter;
      double opacity;
      if (reduceMotion) {
        // A static image still needs to read as seven distinct voices, not
        // one frozen frame of the animation — varied size, flat opacity.
        diameter = _startDiameter + i * 14;
        opacity = 0.3;
      } else {
        final localMs = elapsedMs - swara.startOffset.inMilliseconds;
        if (localMs < 0) continue; // hasn't arisen yet this app open.
        final progress = (localMs % _ringPeriodMs) / _ringPeriodMs;
        final eased = _cubicBezier(progress, 0.17, 0.62, 0.31, 1.0);
        diameter = lerpDouble(_startDiameter, _endDiameter, eased)!;
        opacity = _opacityEnvelope(progress);
      }
      if (opacity <= 0) continue;

      canvas.drawCircle(
        center,
        diameter / 2,
        Paint()
          ..color = swara.color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..blendMode = BlendMode.screen,
      );
    }
    canvas.restore();
  }

  /// Keyframes: 0 at start, 0.8 at 9% through the cycle, 0.26 at 55%, back
  /// to 0 at the end — linear between each pair, matching plain CSS
  /// percentage keyframes with no easing of their own (the *size* growth
  /// carries the eased motion via [_cubicBezier]; opacity just fades).
  double _opacityEnvelope(double t) {
    if (t <= 0.09) return lerpDouble(0, 0.8, t / 0.09)!;
    if (t <= 0.55) return lerpDouble(0.8, 0.26, (t - 0.09) / 0.46)!;
    return lerpDouble(0.26, 0, (t - 0.55) / 0.45)!;
  }

  @override
  bool shouldRepaint(covariant SaptaSwaraPainter oldDelegate) =>
      oldDelegate.elapsedMs != elapsedMs ||
      oldDelegate.reduceMotion != reduceMotion;
}

/// Standard CSS-style cubic-bezier(x1,y1,x2,y2) easing: solves for the
/// bezier parameter whose x-component matches [t] (Newton-Raphson, falling
/// back to bisection if it doesn't converge), then returns the
/// corresponding y. The curve here — cubic-bezier(.17,.62,.31,1) — is a
/// quick-then-settling expansion, not a linear grow.
double _cubicBezier(double t, double x1, double y1, double x2, double y2) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;

  double bezierComponent(double p, double p1, double p2) {
    final oneMinusP = 1 - p;
    return 3 * oneMinusP * oneMinusP * p * p1 +
        3 * oneMinusP * p * p * p2 +
        p * p * p;
  }

  double bezierDerivative(double p, double p1, double p2) {
    final oneMinusP = 1 - p;
    return 3 * oneMinusP * oneMinusP * p1 +
        6 * oneMinusP * p * (p2 - p1) +
        3 * p * p * (1 - p2);
  }

  var guess = t;
  for (var i = 0; i < 8; i++) {
    final x = bezierComponent(guess, x1, x2) - t;
    final dx = bezierDerivative(guess, x1, x2);
    if (dx.abs() < 1e-6) break;
    final next = guess - x / dx;
    if (next.isNaN || next < 0 || next > 1) break;
    guess = next;
    if (x.abs() < 1e-5) break;
  }
  return bezierComponent(guess, y1, y2).clamp(0.0, 1.0);
}
