import 'package:flutter_test/flutter_test.dart';
import 'package:sargam_app/services/feedback_mapper.dart';
import 'package:sargam_app/services/sa_pitch.dart';

/// Unit tests for the feedback mapper (F1a; the teacher's seven rules,
/// 2026-10-22). Run: flutter test test/feedback_mapper_test.dart
/// (no device needed)
void main() {
  group('mapDiagnosisToFeedback (F1a)', () {
    SwaraDiagnosis d(
      String swara,
      double dev,
      int points,
      String status,
    ) =>
        SwaraDiagnosis(
          swara: swara,
          medianDeviationCents: dev,
          pointCount: points,
          status: status,
        );

    // Bhopali in table order, as diagnoseSwara produces it.
    List<SwaraDiagnosis> take(List<double> devs) {
      const swaras = ['Sa', 'Re', 'Ga', 'Pa', 'Dha'];
      return [
        for (var i = 0; i < 5; i++)
          d(
            swaras[i],
            devs[i],
            40,
            devs[i].abs() <= 25
                ? SwaraDiagnosis.statusInTune
                : devs[i] < 0
                    ? SwaraDiagnosis.statusFlat
                    : SwaraDiagnosis.statusSharp,
          ),
      ];
    }

    test('1. teacher worked example: Dha +67 is the one fix, Re+Pa praised',
        () {
      // Anaisha's real Oct 12 take: Sa -49, Re -12, Ga +42, Pa +3, Dha +67.
      final c = mapDiagnosisToFeedback(
        take([-49, -12, 42, 3, 67]),
        bhopaliTable,
      );
      expect(c.kind, FeedbackKind.tuning);
      expect(
        c.fix,
        'Your Dha was high. Listen (Sa… Dha) and sing it again.',
      );
      expect(c.hearTokens, ['Sa', 'Dha']);
      expect(c.reinforcement, 'Re and Pa were right in tune.');
    });

    test('2. all notes at -40c: one Sa message, zero per-note flags', () {
      final c = mapDiagnosisToFeedback(
        take([-40, -40, -40, -40, -40]),
        bhopaliTable,
      );
      expect(c.kind, FeedbackKind.shift);
      expect(c.fix, contains('saved Sa'));
      expect(c.fix, contains('a little low'));
      expect(c.fix, isNot(contains('Dha')));
      expect(c.fix, isNot(contains('Ga')));
      expect(
        c.reinforcement,
        'The shape of your scale was right — every note moved together.',
      );
      expect(c.hearTokens, isEmpty);
    });

    test('3. uniform +35c shift: gentle Sa message', () {
      final c = mapDiagnosisToFeedback(
        take([35, 35, 35, 35, 35]),
        bhopaliTable,
      );
      expect(c.kind, FeedbackKind.shift);
      expect(c.fix, contains('a little high'));
      expect(c.fix, isNot(contains('probably off')));
    });

    test('4. uniform -55c shift: stronger Sa message', () {
      final c = mapDiagnosisToFeedback(
        take([-55, -55, -55, -55, -55]),
        bhopaliTable,
      );
      expect(c.kind, FeedbackKind.shift);
      expect(c.fix, contains('probably off'));
      expect(c.fix, isNot(contains('a little')));
    });

    test('5. median +28c is below the shift threshold: a tuning fix', () {
      final c = mapDiagnosisToFeedback(
        take([28, 28, 28, 28, 28]),
        bhopaliTable,
      );
      expect(c.kind, FeedbackKind.tuning);
      expect(c.fix, contains('a little high'));
    });

    test('6. single flat Ga: little form, all four in-tune notes named', () {
      final c = mapDiagnosisToFeedback(
        take([0, 5, -30, -8, 10]),
        bhopaliTable,
      );
      expect(c.kind, FeedbackKind.tuning);
      expect(
        c.fix,
        'Your Ga was a little low. Listen (Sa… Ga) and sing it again.',
      );
      expect(c.hearTokens, ['Sa', 'Ga']);
      expect(
        c.reinforcement,
        'Sa, Re, Pa and Dha were right in tune.',
      );
    });

    test('7. Ga +67c: plain form, no "a little"', () {
      final c = mapDiagnosisToFeedback(
        take([0, 0, 67, 0, 0]),
        bhopaliTable,
      );
      expect(c.kind, FeedbackKind.tuning);
      expect(c.fix, 'Your Ga was high. Listen (Sa… Ga) and sing it again.');
    });

    test('8. wrong note at Ma: named, raga rule stated', () {
      final diagnosis = take([0, 0, 0, 0, 0]);
      diagnosis[2] = d(
        'Ga',
        100,
        40,
        SwaraDiagnosis.statusWrongNote,
      );
      final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
      expect(c.kind, FeedbackKind.wrongNote);
      expect(
        c.fix,
        'That went up to Ma — Bhopali doesn\'t use Ma. Listen (Sa… Ga) and sing it again.',
      );
      expect(c.hearTokens, ['Sa', 'Ga']);
      expect(
        c.reinforcement,
        'Sa, Re, Pa and Dha were right in tune.',
      );
    });

    test('9. wrong note 40c from any degree: unnamed', () {
      // Ga +140c sits at 540c — 40c from Ma, outside the 35c naming band.
      final diagnosis = take([0, 0, 0, 0, 0]);
      diagnosis[2] = d(
        'Ga',
        140,
        40,
        SwaraDiagnosis.statusWrongNote,
      );
      final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
      expect(c.kind, FeedbackKind.wrongNote);
      expect(
        c.fix,
        'One note landed outside the raga — listen (Sa… Ga) and sing it again.',
      );
      expect(c.fix, isNot(contains('Ma')));
    });

    test('10. wrong note exactly 35c from Ma: named (band edge)', () {
      // Ga +135c sits at 535c — exactly 35c from Ma, inside the band.
      final diagnosis = take([0, 0, 0, 0, 0]);
      diagnosis[2] = d(
        'Ga',
        135,
        40,
        SwaraDiagnosis.statusWrongNote,
      );
      final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
      expect(c.kind, FeedbackKind.wrongNote);
      expect(c.fix, contains('Ma'));
    });

    test('11. wrong note outranks a tuning error', () {
      final diagnosis = take([0, 0, 0, 0, 67]);
      diagnosis[2] = d(
        'Ga',
        100,
        40,
        SwaraDiagnosis.statusWrongNote,
      );
      final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
      expect(c.kind, FeedbackKind.wrongNote);
      expect(c.fix, contains('Ma'));
    });

    test('12. worst flat note too short to judge: length, not tuning', () {
      final diagnosis = take([0, 0, -30, 0, 0]);
      diagnosis[2] = d('Ga', -30, 4, SwaraDiagnosis.statusFlat);
      final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
      expect(c.kind, FeedbackKind.length);
      expect(
        c.fix,
        'Hold your Ga a little longer — it was too short to judge.',
      );
      expect(c.hearTokens, ['Sa', 'Ga']);
    });

    test('13. short in-tune note, nothing else wrong: length fix', () {
      final diagnosis = take([0, 0, 0, 0, 0]);
      diagnosis[2] = d('Ga', 5, 5, SwaraDiagnosis.statusInTune);
      final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
      expect(c.kind, FeedbackKind.length);
      expect(
        c.fix,
        'Hold your Ga a little longer — it was too short to judge.',
      );
    });

    test('14. all in tune: praise only, no fix', () {
      final c = mapDiagnosisToFeedback(take([0, 5, -8, 3, 10]), bhopaliTable);
      expect(c.kind, FeedbackKind.allInTune);
      expect(c.fix, isNull);
      expect(
        c.reinforcement,
        'Every note was in tune. Sing it once more to make it stick.',
      );
      expect(c.hearTokens, isEmpty);
    });

    test('15. Ga not sung, rest in tune: notSung fix', () {
      final diagnosis = take([0, 0, 0, 0, 0]);
      diagnosis[2] = d(
        'Ga',
        0.0,
        0,
        SwaraDiagnosis.statusNotSung,
      );
      final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
      expect(c.kind, FeedbackKind.notSung);
      expect(
        c.fix,
        'You didn\'t sing Ga this time — listen (Sa… Ga) and try it again.',
      );
      expect(c.hearTokens, ['Sa', 'Ga']);
    });

    test('16. notSung 0.0 placeholders do not hide a shift', () {
      // Two notes at -40c, three not sung: the median of the sung notes
      // is -40c. Including the 0.0 placeholders would give a median of 0.
      final diagnosis = [
        d('Sa', -40, 40, SwaraDiagnosis.statusFlat),
        d('Re', -40, 40, SwaraDiagnosis.statusFlat),
        d('Ga', 0.0, 0, SwaraDiagnosis.statusNotSung),
        d('Pa', 0.0, 0, SwaraDiagnosis.statusNotSung),
        d('Dha', 0.0, 0, SwaraDiagnosis.statusNotSung),
      ];
      final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
      expect(c.kind, FeedbackKind.shift);
      expect(c.fix, contains('a little low'));
    });

    test('17. nothing in tune: reinforcement names the closest note', () {
      final c = mapDiagnosisToFeedback(
        take([-30, 28, -45, 35, 60]),
        bhopaliTable,
      );
      expect(c.kind, FeedbackKind.tuning);
      expect(c.fix, contains('Dha'));
      expect(c.reinforcement, 'Your Re was closest — nearly there.');
    });

    test('18. shift plus a wrong note: shift wins, shape line withheld', () {
      final diagnosis = [
        d('Sa', -40, 40, SwaraDiagnosis.statusFlat),
        d('Re', -40, 40, SwaraDiagnosis.statusFlat),
        d('Ga', 100, 40, SwaraDiagnosis.statusWrongNote),
        d('Pa', -40, 40, SwaraDiagnosis.statusFlat),
        d('Dha', -40, 40, SwaraDiagnosis.statusFlat),
      ];
      final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
      expect(c.kind, FeedbackKind.shift);
      expect(c.reinforcement, isNotNull);
      expect(
        c.reinforcement,
        isNot(contains('shape of your scale')),
      );
    });

    test('19. student language: no flat/sharp/cents/Hz anywhere', () {
      const banned = ['flat', 'sharp', 'cents', 'hz'];
      final fixtures = [
        take([-49, -12, 42, 3, 67]),
        take([-40, -40, -40, -40, -40]),
        take([55, 55, 55, 55, 55]),
        take([0, 0, 0, 0, 0]),
        [
          d('Sa', 0, 40, SwaraDiagnosis.statusInTune),
          d('Re', 0, 40, SwaraDiagnosis.statusInTune),
          d('Ga', 100, 40, SwaraDiagnosis.statusWrongNote),
          d('Pa', 0, 40, SwaraDiagnosis.statusInTune),
          d('Dha', 0, 40, SwaraDiagnosis.statusInTune),
        ],
        [
          d('Sa', 0, 40, SwaraDiagnosis.statusInTune),
          d('Re', 0, 40, SwaraDiagnosis.statusInTune),
          d('Ga', -30, 4, SwaraDiagnosis.statusFlat),
          d('Pa', 0, 40, SwaraDiagnosis.statusInTune),
          d('Dha', 0, 40, SwaraDiagnosis.statusInTune),
        ],
        [
          d('Sa', 0, 40, SwaraDiagnosis.statusInTune),
          d('Re', 0, 40, SwaraDiagnosis.statusInTune),
          d('Ga', 0.0, 0, SwaraDiagnosis.statusNotSung),
          d('Pa', 0, 40, SwaraDiagnosis.statusInTune),
          d('Dha', 0, 40, SwaraDiagnosis.statusInTune),
        ],
      ];
      for (final fixture in fixtures) {
        final c = mapDiagnosisToFeedback(fixture, bhopaliTable);
        for (final text in [c.fix, c.reinforcement]) {
          if (text == null) continue;
          for (final word in banned) {
            expect(
              text.toLowerCase().contains(word),
              isFalse,
              reason: '"$word" leaked into student text: "$text"',
            );
          }
        }
      }
    });
  });

  group('isLineCovered (coverage gate)', () {
    SwaraDiagnosis d(String swara, double dev, int points, String status) =>
        SwaraDiagnosis(
          swara: swara,
          medianDeviationCents: dev,
          pointCount: points,
          status: status,
        );

    SwaraDiagnosis ns(String swara) =>
        d(swara, 0.0, 0, SwaraDiagnosis.statusNotSung);

    test(
      'a: today\'s sung take (Nov 27): all 5 sung, 23-57 pts -> covered',
      () {
        // Anaisha's real Nov 27 avroh: Sa -72 (41), Re -77 wrongNote (23),
        // Ga +23 (28), Pa -59 (30), Dha +69 (57). Median -59c: the mapper
        // correctly shows the shift card — and the take covered the line.
        final diagnosis = [
          d('Sa', -72, 41, SwaraDiagnosis.statusFlat),
          d('Re', -77, 23, SwaraDiagnosis.statusWrongNote),
          d('Ga', 23, 28, SwaraDiagnosis.statusInTune),
          d('Pa', -59, 30, SwaraDiagnosis.statusFlat),
          d('Dha', 69, 57, SwaraDiagnosis.statusSharp),
        ];
        expect(isLineCovered(diagnosis, bhopaliTable), isTrue);
      },
    );

    test('b: f-case, Sa held + 8 stray frames near Dha -> NOT covered', () {
      // The Nov 25 finding: Sa + 8 stray frames near Dha made Dha
      // "sung" (8 pts clears the notSung floor of 3) and the card praised
      // "Sa and Dha were right in tune". Only 2 of 5 covered: the gate
      // must fire instead of a tuning verdict.
      final diagnosis = [
        d('Sa', 0, 25, SwaraDiagnosis.statusInTune),
        ns('Re'),
        ns('Ga'),
        ns('Pa'),
        d('Dha', 5, 8, SwaraDiagnosis.statusInTune),
      ];
      expect(isLineCovered(diagnosis, bhopaliTable), isFalse);
    });

    test('c: exactly 3 of 5 covered -> covered (boundary)', () {
      final diagnosis = [
        d('Sa', 0, 40, SwaraDiagnosis.statusInTune),
        d('Re', 0, 40, SwaraDiagnosis.statusInTune),
        d('Ga', 0, 40, SwaraDiagnosis.statusInTune),
        ns('Pa'),
        ns('Dha'),
      ];
      expect(isLineCovered(diagnosis, bhopaliTable), isTrue);
    });

    test('d: exactly 2 of 5 covered -> NOT covered (boundary)', () {
      final diagnosis = [
        d('Sa', 0, 40, SwaraDiagnosis.statusInTune),
        d('Re', 0, 40, SwaraDiagnosis.statusInTune),
        ns('Ga'),
        ns('Pa'),
        ns('Dha'),
      ];
      expect(isLineCovered(diagnosis, bhopaliTable), isFalse);
    });

    test('e: empty diagnosis -> NOT covered', () {
      expect(isLineCovered([], bhopaliTable), isFalse);
    });

    test('f: all notSung -> NOT covered', () {
      final diagnosis = [ns('Sa'), ns('Re'), ns('Ga'), ns('Pa'), ns('Dha')];
      expect(isLineCovered(diagnosis, bhopaliTable), isFalse);
    });
  });

  group('shift fires only on uniform takes (spread check)', () {
    SwaraDiagnosis d(String swara, double dev, int points, String status) =>
        SwaraDiagnosis(
          swara: swara,
          medianDeviationCents: dev,
          pointCount: points,
          status: status,
        );

    // Bhopali in table order, as diagnoseSwara produces it.
    List<SwaraDiagnosis> take(List<double> devs) {
      const swaras = ['Sa', 'Re', 'Ga', 'Pa', 'Dha'];
      return [
        for (var i = 0; i < 5; i++)
          d(
            swaras[i],
            devs[i],
            40,
            devs[i].abs() <= 25
                ? SwaraDiagnosis.statusInTune
                : devs[i] < 0
                ? SwaraDiagnosis.statusFlat
                : SwaraDiagnosis.statusSharp,
          ),
      ];
    }

    test(
      'a: post-recalibration take (Nov 27): 20c spread -> shift, gentle',
      () {
        // Anaisha's real take after recalibrating to G#: Sa -33 (89),
        // Re -36 (31), Ga -27 (30), Pa -47 (29), Dha -29 (31).
        // Median -33c, spread 20c: genuinely uniform, the textbook
        // shift case.
        final diagnosis = [
          d('Sa', -33, 89, SwaraDiagnosis.statusFlat),
          d('Re', -36, 31, SwaraDiagnosis.statusFlat),
          d('Ga', -27, 30, SwaraDiagnosis.statusFlat),
          d('Pa', -47, 29, SwaraDiagnosis.statusFlat),
          d('Dha', -29, 31, SwaraDiagnosis.statusFlat),
        ];
        final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
        expect(c.kind, FeedbackKind.shift);
        expect(
          c.fix,
          'Everything sounds a little low against your saved Sa. Your saved Sa might be a touch off — re-check it from Profile and sing again.',
        );
        expect(
          c.reinforcement,
          'The shape of your scale was right — every note moved together.',
        );
        expect(c.hearTokens, isEmpty);
      },
    );

    test(
      'b: pre-recalibration take (Nov 27): 141c spread -> wrongNote, not shift',
      () {
        // Anaisha's real take before recalibration: Sa -72 (41),
        // Re -77 wrongNote (23), Ga +23 (28), Pa -59 (30), Dha +69 (57).
        // Median -59c but the tuning spread is 141c, so the shift
        // branch must not fire; the wrong note (komal Re) is the fix.
        final diagnosis = [
          d('Sa', -72, 41, SwaraDiagnosis.statusFlat),
          d('Re', -77, 23, SwaraDiagnosis.statusWrongNote),
          d('Ga', 23, 28, SwaraDiagnosis.statusInTune),
          d('Pa', -59, 30, SwaraDiagnosis.statusFlat),
          d('Dha', 69, 57, SwaraDiagnosis.statusSharp),
        ];
        final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
        expect(c.kind, FeedbackKind.wrongNote);
        expect(
          c.fix,
          'That went up to komal Re — Bhopali doesn\'t use komal Re. Listen (Sa… Re) and sing it again.',
        );
        expect(c.reinforcement, 'Ga was right in tune.');
        expect(c.hearTokens, ['Sa', 'Re']);
      },
    );

    test('c: spread exactly 50c -> shift (boundary)', () {
      final c = mapDiagnosisToFeedback(
        take([-60, -55, -50, -40, -10]),
        bhopaliTable,
      );
      expect(c.kind, FeedbackKind.shift);
      expect(c.fix, contains('probably off'));
    });

    test('d: spread 51c -> falls through to the worst note', () {
      final c = mapDiagnosisToFeedback(
        take([-61, -55, -50, -40, -10]),
        bhopaliTable,
      );
      expect(c.kind, FeedbackKind.tuning);
      expect(c.fix, 'Your Sa was low. Listen (Sa… Sa) and sing it again.');
      expect(c.reinforcement, 'Dha was right in tune.');
      expect(c.hearTokens, ['Sa', 'Sa']);
    });

    test('e: shift plus a wrong note: shift still wins (test 18 fixture)', () {
      // Same fixture as test 18: the non-wrongNote spread is 0, so
      // the shift fires and rule 1 still outranks the wrong note.
      final diagnosis = [
        d('Sa', -40, 40, SwaraDiagnosis.statusFlat),
        d('Re', -40, 40, SwaraDiagnosis.statusFlat),
        d('Ga', 100, 40, SwaraDiagnosis.statusWrongNote),
        d('Pa', -40, 40, SwaraDiagnosis.statusFlat),
        d('Dha', -40, 40, SwaraDiagnosis.statusFlat),
      ];
      final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
      expect(c.kind, FeedbackKind.shift);
      expect(c.reinforcement, isNotNull);
      expect(c.reinforcement, isNot(contains('shape of your scale')));
    });

    test('f: all notes wrong notes -> shift (no tuning spread)', () {
      // No non-wrongNote deviations exist, so the spread is 0 and the
      // old behaviour is preserved: the median (+100c) fires the shift.
      final diagnosis = [
        d('Sa', 100, 40, SwaraDiagnosis.statusWrongNote),
        d('Re', 100, 40, SwaraDiagnosis.statusWrongNote),
        d('Ga', 100, 40, SwaraDiagnosis.statusWrongNote),
        d('Pa', 100, 40, SwaraDiagnosis.statusWrongNote),
        d('Dha', 100, 40, SwaraDiagnosis.statusWrongNote),
      ];
      final c = mapDiagnosisToFeedback(diagnosis, bhopaliTable);
      expect(c.kind, FeedbackKind.shift);
      expect(c.fix, contains('probably off'));
    });
  });
}
