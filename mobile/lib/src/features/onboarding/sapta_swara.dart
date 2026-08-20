import 'package:flutter/material.dart';

/// One of the seven swaras (notes) of Indian classical music — the melodic
/// alphabet every bhajan, kirtan, and mantra tune is built from. This is
/// Anhad's signature arrival visual (docs/FRONTEND_GUIDELINES.md, "Sapta
/// Swara"): not a japa-specific idea, and deliberately not a devotee
/// figure — every devotional app has one of those.
class Swara {
  const Swara({
    required this.name,
    required this.x,
    required this.y,
    required this.color,
    required this.frequencyRatio,
    required this.startOffset,
  });

  final String name;

  /// Position as a fraction of the screen, following the Sangita
  /// Ratnakara's description of nada rising through the body — navel,
  /// heart, throat, tongue, nose, teeth, lips — so the seven rings arise
  /// bottom-to-top, scattered rather than in a tidy row.
  final double x;
  final double y;

  /// Sa and Pa are gold — the two *achala* (fixed) swaras every raga
  /// returns to, regardless of which raga is being sung. The other five
  /// each get their own warm, desaturated hue. Deliberately not a
  /// chakra-rainbow palette (docs/FRONTEND_GUIDELINES.md §2 rules that out
  /// as a New Age cliché).
  final Color color;

  /// Just intonation relative to Sa, not equal temperament — this is what
  /// makes the seven tones sound Indian rather than like a piano.
  final double frequencyRatio;

  /// When this ring begins its cycle, relative to the sequence start.
  final Duration startOffset;
}

const _sa = Color(0xFFE8A33D);
const _re = Color(0xFFD4826B);
const _ga = Color(0xFFC1739A);
const _ma = Color(0xFF8E86C6);
const _pa = Color(0xFFF2C46B);
const _dha = Color(0xFF7FA88C);
const _ni = Color(0xFF6FA0B8);

/// Sa's absolute pitch — the seven tones are derived from this via
/// [Swara.frequencyRatio], not hardcoded per-note. Pitched an octave below
/// the original 272.2 Hz reference — at the higher octave, even the softer
/// harmonic mix in [_synthesizeTone] carried the upper swaras (Ni's
/// harmonics in particular) into a bright, harsh register; a full octave
/// down keeps every note, including its overtones, in a warmer range.
const saptaSwaraSaHz = 136.1;

const saptaSwaras = <Swara>[
  Swara(
    name: 'Sa',
    x: 0.50,
    y: 0.84,
    color: _sa,
    frequencyRatio: 1 / 1,
    startOffset: Duration.zero,
  ),
  Swara(
    name: 'Re',
    x: 0.26,
    y: 0.73,
    color: _re,
    frequencyRatio: 9 / 8,
    startOffset: Duration(milliseconds: 900),
  ),
  Swara(
    name: 'Ga',
    x: 0.72,
    y: 0.62,
    color: _ga,
    frequencyRatio: 5 / 4,
    startOffset: Duration(milliseconds: 1800),
  ),
  Swara(
    name: 'Ma',
    x: 0.32,
    y: 0.48,
    color: _ma,
    frequencyRatio: 4 / 3,
    startOffset: Duration(milliseconds: 2700),
  ),
  Swara(
    name: 'Pa',
    x: 0.64,
    y: 0.36,
    color: _pa,
    frequencyRatio: 3 / 2,
    startOffset: Duration(milliseconds: 3600),
  ),
  Swara(
    name: 'Dha',
    x: 0.36,
    y: 0.24,
    color: _dha,
    frequencyRatio: 5 / 3,
    startOffset: Duration(milliseconds: 4500),
  ),
  Swara(
    name: 'Ni',
    x: 0.60,
    y: 0.13,
    color: _ni,
    frequencyRatio: 15 / 8,
    startOffset: Duration(milliseconds: 5400),
  ),
];
