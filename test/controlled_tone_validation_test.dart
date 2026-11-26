// Controlled tone validation for Riti's Bhopali diagnosis (2026-11-25).
//
// Clean synthetic input through diagnoseSwara + mapDiagnosisToFeedback
// (cases a-f). No shipped lib file is modified; this is new test code
// only. Nothing here uses the Oct 12 take (circular as reference data).
// The detector cases (g: extractor on sine PCM) stay in the local
// harness only: they need verbatim copies of the extractor, and g1
// fails by design until the YIN fix lands.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:sargam_app/services/feedback_mapper.dart';
import 'package:sargam_app/services/normalized_compare.dart';
import 'package:sargam_app/services/sa_pitch.dart';

const double saHz = 220.0;
const int pointsPerSwara = 25;

/// Exact Hz for [cents] above the stored Sa.
double hzAt(double cents) => saHz * math.pow(2.0, cents / 1200.0);

List<double> _note(double cents, int n) =>
    List<double>.filled(n, hzAt(cents));

/// Avroh contour in table order; [centsBySwara] maps swara -> cents above Sa.
List<double> _line(Map<String, double> centsBySwara) {
  const order = ['Sa', 'Re', 'Ga', 'Pa', 'Dha'];
  final out = <double>[];
  for (final s in order) {
    out.addAll(_note(centsBySwara[s]!, pointsPerSwara));
  }
  return out;
}

String _report(
  String label,
  List<SwaraDiagnosis> d,
  FeedbackCardContent c,
) {
  final b = StringBuffer()..writeln('--- $label ---');
  for (final x in d) {
    b.writeln('  ${x.swara}: ${x.status} '
        'median ${x.medianDeviationCents.toStringAsFixed(1)}c, '
        '${x.pointCount} pts');
  }
  b.writeln('  card: kind=${c.kind}');
  b.writeln('  fix: ${c.fix}');
  b.writeln('  praise: ${c.reinforcement}');
  b.writeln('  hear: ${c.hearTokens}');
  return b.toString();
}

/// Diagnose + map + print one contour. Returns the pair for expects.
(List<SwaraDiagnosis>, FeedbackCardContent) _run(
  String label,
  List<double> contour,
) {
  final d = diagnoseSwara(contour, saHz, bhopaliTable);
  final c = mapDiagnosisToFeedback(d, bhopaliTable);
  print(_report(label, d, c));
  return (d, c);
}

void main() {
  group('controlled tone validation (stored Sa 220 Hz, Bhopali)', () {
    test('a: in-tune avroh', () {
      final (d, c) = _run(
        'a in-tune avroh',
        _line({'Sa': 0, 'Re': 200, 'Ga': 400, 'Pa': 700, 'Dha': 900}),
      );
      expect(d.every((x) => x.status == SwaraDiagnosis.statusInTune),
          isTrue);
      expect(c.kind, FeedbackKind.allInTune);
      expect(c.fix, isNull);
    });

    test('b: Ga flat 40c', () {
      final (d, c) = _run(
        'b Ga flat 40c',
        _line({'Sa': 0, 'Re': 200, 'Ga': 360, 'Pa': 700, 'Dha': 900}),
      );
      final ga = d.firstWhere((x) => x.swara == 'Ga');
      expect(ga.status, SwaraDiagnosis.statusFlat);
      expect(ga.medianDeviationCents, closeTo(-40.0, 0.5));
      expect(
          d
              .where((x) => x.swara != 'Ga')
              .every((x) => x.status == SwaraDiagnosis.statusInTune),
          isTrue);
      expect(c.kind, FeedbackKind.tuning);
      expect(c.fix, contains('Your Ga was a little low'));
      expect(c.hearTokens, ['Sa', 'Ga']);
    });

    test('c: Dha flat 40c', () {
      final (d, c) = _run(
        'c Dha flat 40c',
        _line({'Sa': 0, 'Re': 200, 'Ga': 400, 'Pa': 700, 'Dha': 860}),
      );
      final dha = d.firstWhere((x) => x.swara == 'Dha');
      expect(dha.status, SwaraDiagnosis.statusFlat);
      expect(dha.medianDeviationCents, closeTo(-40.0, 0.5));
      expect(
          d
              .where((x) => x.swara != 'Dha')
              .every((x) => x.status == SwaraDiagnosis.statusInTune),
          isTrue);
      expect(c.kind, FeedbackKind.tuning);
      expect(c.fix, contains('Your Dha was a little low'));
      expect(c.hearTokens, ['Sa', 'Dha']);
    });

    test('d: Ma sung where Ga belongs', () {
      final (d, c) = _run(
        'd Ma (500c) in place of Ga',
        _line({'Sa': 0, 'Re': 200, 'Ga': 500, 'Pa': 700, 'Dha': 900}),
      );
      final ga = d.firstWhere((x) => x.swara == 'Ga');
      expect(ga.status, SwaraDiagnosis.statusWrongNote);
      expect(ga.medianDeviationCents, closeTo(100.0, 0.5));
      expect(c.kind, FeedbackKind.wrongNote);
      expect(c.fix, contains('Ma'));
      expect(c.hearTokens, ['Sa', 'Ga']);
    });

    test('e: whole line shifted +40c', () {
      final (d, c) = _run(
        'e whole line +40c',
        _line({'Sa': 40, 'Re': 240, 'Ga': 440, 'Pa': 740, 'Dha': 940}),
      );
      expect(c.kind, FeedbackKind.shift);
      expect(c.fix, contains('saved Sa'));
      expect(c.hearTokens, isEmpty);
    });

    test('f: Sa held + 8 stray frames near Dha (phone observation repro)',
        () {
      // KNOWN GAP (plan section 6): 8 stray frames make Dha "sung" and
      // "in tune" even though the line was never sung. These expects lock
      // the current behaviour; the coverage-check fix must update them.
      final contour = <double>[
        ..._note(0, 25),
        ..._note(905, 8), // a few frames 5c sharp of Dha
      ];
      final (d, c) = _run('f Sa + 8 stray frames at Dha+5c', contour);
      final dha = d.firstWhere((x) => x.swara == 'Dha');
      expect(dha.status, SwaraDiagnosis.statusInTune);
      expect(dha.pointCount, 8);
      expect(dha.medianDeviationCents, closeTo(5.0, 0.5));
      expect(c.kind, FeedbackKind.notSung);
      expect(c.reinforcement, contains('Dha'));
    });

    test('f2: Sa held + 2 stray frames near Dha (below 3-point floor)', () {
      // Boundary check: the notSung floor is max(3, ceil(2% of voiced)).
      final contour = <double>[
        ..._note(0, 25),
        ..._note(905, 2),
      ];
      final (d, c) = _run('f2 Sa + 2 stray frames at Dha+5c', contour);
      final dha = d.firstWhere((x) => x.swara == 'Dha');
      expect(dha.status, SwaraDiagnosis.statusNotSung);
      expect(dha.pointCount, 2);
      expect(c.reinforcement, isNot(contains('Dha')));
    });
  });
}
