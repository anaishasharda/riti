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

  group('isLineCovered point-count bar (ghost bar)', () {
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
      'a: random take (Nov 27): Sa + Ma/Ni, ghost Pa/Dha -> NOT covered',
      () {
        // Anaisha's real Nov 27 random take: Sa held + Ma and Ni briefly.
        // Sa -112 (133 pts, the Ni bucketed into Sa) and Ga +71 (120 pts,
        // the Ma bucketed into Ga) are truly covered; Pa -23 (11 pts) and
        // Dha -16 (12 pts) are ghosts she did not sing. Only 2 of 5
        // covered — the gate must fire.
        final diagnosis = [
          d('Sa', -112, 133, SwaraDiagnosis.statusWrongNote),
          ns('Re'),
          d('Ga', 71, 120, SwaraDiagnosis.statusSharp),
          d('Pa', -23, 11, SwaraDiagnosis.statusInTune),
          d('Dha', -16, 12, SwaraDiagnosis.statusInTune),
        ];
        expect(isLineCovered(diagnosis, bhopaliTable), isFalse);
      },
    );

    test('b: 14 points does not count, 15 points does (boundary)', () {
      final fourteen = [
        d('Sa', 0, 40, SwaraDiagnosis.statusInTune),
        d('Re', 0, 40, SwaraDiagnosis.statusInTune),
        d('Ga', 0, 14, SwaraDiagnosis.statusInTune),
        ns('Pa'),
        ns('Dha'),
      ];
      expect(isLineCovered(fourteen, bhopaliTable), isFalse);
      final fifteen = [
        d('Sa', 0, 40, SwaraDiagnosis.statusInTune),
        d('Re', 0, 40, SwaraDiagnosis.statusInTune),
        d('Ga', 0, 15, SwaraDiagnosis.statusInTune),
        ns('Pa'),
        ns('Dha'),
      ];
      expect(isLineCovered(fifteen, bhopaliTable), isTrue);
    });

    test('c: Nov 27 real takes: smallest genuine count 23 -> covered', () {
      // Pre-recalibration avroh: Sa -72 (41), Re -77 wrongNote (23),
      // Ga +23 (28), Pa -59 (30), Dha +69 (57).
      final before = [
        d('Sa', -72, 41, SwaraDiagnosis.statusFlat),
        d('Re', -77, 23, SwaraDiagnosis.statusWrongNote),
        d('Ga', 23, 28, SwaraDiagnosis.statusInTune),
        d('Pa', -59, 30, SwaraDiagnosis.statusFlat),
        d('Dha', 69, 57, SwaraDiagnosis.statusSharp),
      ];
      expect(isLineCovered(before, bhopaliTable), isTrue);
      // Post-recalibration avroh: Sa -33 (89), Re -36 (31), Ga -27 (30),
      // Pa -47 (29), Dha -29 (31).
      final after = [
        d('Sa', -33, 89, SwaraDiagnosis.statusFlat),
        d('Re', -36, 31, SwaraDiagnosis.statusFlat),
        d('Ga', -27, 30, SwaraDiagnosis.statusFlat),
        d('Pa', -47, 29, SwaraDiagnosis.statusFlat),
        d('Dha', -29, 31, SwaraDiagnosis.statusFlat),
      ];
      expect(isLineCovered(after, bhopaliTable), isTrue);
    });

    test('d: f-case, Sa held + 8 stray frames near Dha -> NOT covered', () {
      // Same fixture as coverage-group test b: Sa 25 pts counts, Dha 8
      // stray pts now fall under the bar too. Only 1 of 5 covered.
      final diagnosis = [
        d('Sa', 0, 25, SwaraDiagnosis.statusInTune),
        ns('Re'),
        ns('Ga'),
        ns('Pa'),
        d('Dha', 5, 8, SwaraDiagnosis.statusInTune),
      ];
      expect(isLineCovered(diagnosis, bhopaliTable), isFalse);
    });
  });

  group('isLineCovered identity check (first cut: foreign notes)', () {
    SwaraDiagnosis d(String swara, double dev, int points, String status) =>
        SwaraDiagnosis(
          swara: swara,
          medianDeviationCents: dev,
          pointCount: points,
          status: status,
        );

    SwaraDiagnosis ns(String swara) =>
        d(swara, 0.0, 0, SwaraDiagnosis.statusNotSung);

    test('a: real takes R1/R2/R3 -> covered', () {
      // R1: pre-recalibration avroh, Sa -72 (41), Re -77 wrongNote (23),
      // Ga +23 (28), Pa -59 (30), Dha +69 (57). Shift -59c: after
      // correction Ga reads as Ma and Dha as komal Ni, so it passes by
      // exactly one bucket (Sa, Re, Pa).
      final r1 = [
        d('Sa', -72, 41, SwaraDiagnosis.statusFlat),
        d('Re', -77, 23, SwaraDiagnosis.statusWrongNote),
        d('Ga', 23, 28, SwaraDiagnosis.statusInTune),
        d('Pa', -59, 30, SwaraDiagnosis.statusFlat),
        d('Dha', 69, 57, SwaraDiagnosis.statusSharp),
      ];
      expect(isLineCovered(r1, bhopaliTable), isTrue);
      // R2: post-recalibration avroh, Sa -33 (89), Re -36 (31),
      // Ga -27 (30), Pa -47 (29), Dha -29 (31).
      final r2 = [
        d('Sa', -33, 89, SwaraDiagnosis.statusFlat),
        d('Re', -36, 31, SwaraDiagnosis.statusFlat),
        d('Ga', -27, 30, SwaraDiagnosis.statusFlat),
        d('Pa', -47, 29, SwaraDiagnosis.statusFlat),
        d('Dha', -29, 31, SwaraDiagnosis.statusFlat),
      ];
      expect(isLineCovered(r2, bhopaliTable), isTrue);
      // R3: control in-tune avroh, Sa -8 (107), Re +1 (51), Ga -24 (42),
      // Pa -35 (39), Dha -16 (41).
      final r3 = [
        d('Sa', -8, 107, SwaraDiagnosis.statusInTune),
        d('Re', 1, 51, SwaraDiagnosis.statusInTune),
        d('Ga', -24, 42, SwaraDiagnosis.statusInTune),
        d('Pa', -35, 39, SwaraDiagnosis.statusFlat),
        d('Dha', -16, 41, SwaraDiagnosis.statusInTune),
      ];
      expect(isLineCovered(r3, bhopaliTable), isTrue);
    });

    test('b: random takes X1/X2 and f-case F -> NOT covered', () {
      // X1: Sa held + Ma, Ni briefly. Sa -112 (133, the Ni bucketed
      // into Sa), Ga +71 (120, the Ma bucketed into Ga), Pa -23 (11)
      // and Dha -16 (12) ghosts. No bucket's pitch is really a line
      // note: 0 of 5 covered.
      final x1 = [
        d('Sa', -112, 133, SwaraDiagnosis.statusWrongNote),
        ns('Re'),
        d('Ga', 71, 120, SwaraDiagnosis.statusSharp),
        d('Pa', -23, 11, SwaraDiagnosis.statusInTune),
        d('Dha', -16, 12, SwaraDiagnosis.statusInTune),
      ];
      expect(isLineCovered(x1, bhopaliTable), isFalse);
      // X2: Sa, Ni, Pa, Ma only. Sa -63 (140), Ga +71 (101),
      // Pa -23 (74), Dha +98 (25). Only Ga and Pa are really line
      // notes: 2 of 5 covered.
      final x2 = [
        d('Sa', -63, 140, SwaraDiagnosis.statusFlat),
        ns('Re'),
        d('Ga', 71, 101, SwaraDiagnosis.statusSharp),
        d('Pa', -23, 74, SwaraDiagnosis.statusInTune),
        d('Dha', 98, 25, SwaraDiagnosis.statusWrongNote),
      ];
      expect(isLineCovered(x2, bhopaliTable), isFalse);
      // F: harness f-case, Sa 25 pts + Dha 8 stray pts.
      final f = [
        d('Sa', 0, 25, SwaraDiagnosis.statusInTune),
        ns('Re'),
        ns('Ga'),
        ns('Pa'),
        d('Dha', 5, 8, SwaraDiagnosis.statusInTune),
      ];
      expect(isLineCovered(f, bhopaliTable), isFalse);
    });

    test('c: X1 foreign notes are Ni and Ma, most-sung first', () {
      final x1 = [
        d('Sa', -112, 133, SwaraDiagnosis.statusWrongNote),
        ns('Re'),
        d('Ga', 71, 120, SwaraDiagnosis.statusSharp),
        d('Pa', -23, 11, SwaraDiagnosis.statusInTune),
        d('Dha', -16, 12, SwaraDiagnosis.statusInTune),
      ];
      expect(foreignNoteNames(x1, bhopaliTable), ['Ni', 'Ma']);
    });

    test('d: X2 foreign notes are Ni and komal Ni', () {
      final x2 = [
        d('Sa', -63, 140, SwaraDiagnosis.statusFlat),
        ns('Re'),
        d('Ga', 71, 101, SwaraDiagnosis.statusSharp),
        d('Pa', -23, 74, SwaraDiagnosis.statusInTune),
        d('Dha', 98, 25, SwaraDiagnosis.statusWrongNote),
      ];
      expect(foreignNoteNames(x2, bhopaliTable), ['Ni', 'komal Ni']);
    });

    test('e: f-case has no foreign notes', () {
      final f = [
        d('Sa', 0, 25, SwaraDiagnosis.statusInTune),
        ns('Re'),
        ns('Ga'),
        ns('Pa'),
        d('Dha', 5, 8, SwaraDiagnosis.statusInTune),
      ];
      expect(foreignNoteNames(f, bhopaliTable), isEmpty);
    });

    test('f: R1 foreign notes are komal Ni and Ma (informational)', () {
      // R1 passes the gate (3 of 5 covered), but two of its buckets
      // read as foreign notes after shift correction — Ga as Ma (28
      // pts) and Dha as komal Ni (57 pts). This locks the
      // classification: the gate and the helper agree.
      final r1 = [
        d('Sa', -72, 41, SwaraDiagnosis.statusFlat),
        d('Re', -77, 23, SwaraDiagnosis.statusWrongNote),
        d('Ga', 23, 28, SwaraDiagnosis.statusInTune),
        d('Pa', -59, 30, SwaraDiagnosis.statusFlat),
        d('Dha', 69, 57, SwaraDiagnosis.statusSharp),
      ];
      expect(foreignNoteNames(r1, bhopaliTable), ['komal Ni', 'Ma']);
    });
  });

  group('allLineNotesSung + foreign-note decoupling', () {
    SwaraDiagnosis d(String swara, double dev, int points, String status) =>
        SwaraDiagnosis(
          swara: swara,
          medianDeviationCents: dev,
          pointCount: points,
          status: status,
        );

    SwaraDiagnosis ns(String swara) =>
        d(swara, 0.0, 0, SwaraDiagnosis.statusNotSung);

    // Mirrors the branching in _buildFeedbackCard
    // (practice_screen.dart): the screen itself cannot run in this
    // harness, so the decision is asserted here from the same three
    // inputs the screen computes — covered, foreign, allLineNotesSung.
    String cardFor(List<SwaraDiagnosis> diagnosis) {
      final covered = isLineCovered(diagnosis, bhopaliTable);
      final foreign = foreignNoteNames(diagnosis, bhopaliTable);
      if (foreign.isNotEmpty &&
          !(covered && allLineNotesSung(diagnosis, bhopaliTable))) {
        return 'notBhopali';
      }
      if (!covered) return 'coverage';
      return 'mapper';
    }

    test('a: Take 1 (Sa Ni Pa Ma) -> not-Bhopali card naming Ma', () {
      // Vishal's first phone take, Nov 28: Sa -65 (86), Re -36 (11),
      // Ga +65 (85), Pa -23 (63), Dha -29 (59). The Ma he sang is
      // detected (Ga's bucket reads as Ma, 85 pts) and the gate passes
      // at 3 of 5 — before the decoupling the card said "Ga was high".
      final take1 = [
        d('Sa', -65, 86, SwaraDiagnosis.statusFlat),
        d('Re', -36, 11, SwaraDiagnosis.statusFlat),
        d('Ga', 65, 85, SwaraDiagnosis.statusSharp),
        d('Pa', -23, 63, SwaraDiagnosis.statusInTune),
        d('Dha', -29, 59, SwaraDiagnosis.statusFlat),
      ];
      expect(foreignNoteNames(take1, bhopaliTable), ['Ma']);
      expect(isLineCovered(take1, bhopaliTable), isTrue);
      expect(allLineNotesSung(take1, bhopaliTable), isFalse);
      expect(cardFor(take1), 'notBhopali');
    });

    test('b: Take 2 (Sa Ni Pa Ma, Ni stronger) -> not-Bhopali naming Ni', () {
      // Vishal's retry, Nov 28: Sa -108 wrongNote (157), Re notSung,
      // Ga +71 (111), Pa -10 (71), Dha +69 (26). The mapper alone
      // would name Ni (Sa past the 75c wrong-note line), but Re was
      // never sung, so the whole-line message is the right card.
      final take2 = [
        d('Sa', -108, 157, SwaraDiagnosis.statusWrongNote),
        ns('Re'),
        d('Ga', 71, 111, SwaraDiagnosis.statusSharp),
        d('Pa', -10, 71, SwaraDiagnosis.statusInTune),
        d('Dha', 69, 26, SwaraDiagnosis.statusSharp),
      ];
      expect(foreignNoteNames(take2, bhopaliTable), ['Ni']);
      expect(isLineCovered(take2, bhopaliTable), isTrue);
      expect(allLineNotesSung(take2, bhopaliTable), isFalse);
      expect(cardFor(take2), 'notBhopali');
    });

    test('c: R1 genuine avroh still gets the mapper card', () {
      // Regression guard: R1 reads two foreign buckets (Ga as Ma, Dha
      // as komal Ni) but IS the line — all five notes sung with real
      // points and covered — so it must NOT get the not-Bhopali card.
      final r1 = [
        d('Sa', -72, 41, SwaraDiagnosis.statusFlat),
        d('Re', -77, 23, SwaraDiagnosis.statusWrongNote),
        d('Ga', 23, 28, SwaraDiagnosis.statusInTune),
        d('Pa', -59, 30, SwaraDiagnosis.statusFlat),
        d('Dha', 69, 57, SwaraDiagnosis.statusSharp),
      ];
      expect(foreignNoteNames(r1, bhopaliTable), ['komal Ni', 'Ma']);
      expect(isLineCovered(r1, bhopaliTable), isTrue);
      expect(allLineNotesSung(r1, bhopaliTable), isTrue);
      expect(cardFor(r1), 'mapper');
    });

    test('d: X1 (Sa held + brief Ma/Ni) -> not-Bhopali card', () {
      final x1 = [
        d('Sa', -112, 133, SwaraDiagnosis.statusWrongNote),
        ns('Re'),
        d('Ga', 71, 120, SwaraDiagnosis.statusSharp),
        d('Pa', -23, 11, SwaraDiagnosis.statusInTune),
        d('Dha', -16, 12, SwaraDiagnosis.statusInTune),
      ];
      expect(foreignNoteNames(x1, bhopaliTable), ['Ni', 'Ma']);
      expect(isLineCovered(x1, bhopaliTable), isFalse);
      expect(allLineNotesSung(x1, bhopaliTable), isFalse);
      expect(cardFor(x1), 'notBhopali');
    });

    test('e: X2 (Sa, Ni, Pa, Ma) -> not-Bhopali card', () {
      final x2 = [
        d('Sa', -63, 140, SwaraDiagnosis.statusFlat),
        ns('Re'),
        d('Ga', 71, 101, SwaraDiagnosis.statusSharp),
        d('Pa', -23, 74, SwaraDiagnosis.statusInTune),
        d('Dha', 98, 25, SwaraDiagnosis.statusWrongNote),
      ];
      expect(foreignNoteNames(x2, bhopaliTable), ['Ni', 'komal Ni']);
      expect(isLineCovered(x2, bhopaliTable), isFalse);
      expect(allLineNotesSung(x2, bhopaliTable), isFalse);
      expect(cardFor(x2), 'notBhopali');
    });

    test('f: stray-frames take -> coverage card, not not-Bhopali', () {
      final f = [
        d('Sa', 0, 25, SwaraDiagnosis.statusInTune),
        ns('Re'),
        ns('Ga'),
        ns('Pa'),
        d('Dha', 5, 8, SwaraDiagnosis.statusInTune),
      ];
      expect(foreignNoteNames(f, bhopaliTable), isEmpty);
      expect(isLineCovered(f, bhopaliTable), isFalse);
      expect(allLineNotesSung(f, bhopaliTable), isFalse);
      expect(cardFor(f), 'coverage');
    });

    test('g: clean in-tune avroh -> mapper card', () {
      final clean = [
        d('Sa', -8, 107, SwaraDiagnosis.statusInTune),
        d('Re', 1, 51, SwaraDiagnosis.statusInTune),
        d('Ga', -24, 42, SwaraDiagnosis.statusInTune),
        d('Pa', -10, 39, SwaraDiagnosis.statusInTune),
        d('Dha', -16, 41, SwaraDiagnosis.statusInTune),
      ];
      expect(foreignNoteNames(clean, bhopaliTable), isEmpty);
      expect(isLineCovered(clean, bhopaliTable), isTrue);
      expect(allLineNotesSung(clean, bhopaliTable), isTrue);
      expect(cardFor(clean), 'mapper');
    });

    test('h: a table swara with no entry at all -> not all sung', () {
      final missing = [
        d('Sa', -8, 107, SwaraDiagnosis.statusInTune),
        d('Re', 1, 51, SwaraDiagnosis.statusInTune),
        d('Ga', -24, 42, SwaraDiagnosis.statusInTune),
        d('Pa', -10, 39, SwaraDiagnosis.statusInTune),
      ];
      expect(allLineNotesSung(missing, bhopaliTable), isFalse);
    });

    test('i: 15-point boundary — 15 counts as sung, 14 does not', () {
      final atBar = [
        d('Sa', -8, 107, SwaraDiagnosis.statusInTune),
        d('Re', 1, 51, SwaraDiagnosis.statusInTune),
        d('Ga', -24, 42, SwaraDiagnosis.statusInTune),
        d('Pa', -10, 39, SwaraDiagnosis.statusInTune),
        d('Dha', -16, 15, SwaraDiagnosis.statusInTune),
      ];
      final underBar = [
        d('Sa', -8, 107, SwaraDiagnosis.statusInTune),
        d('Re', 1, 51, SwaraDiagnosis.statusInTune),
        d('Ga', -24, 42, SwaraDiagnosis.statusInTune),
        d('Pa', -10, 39, SwaraDiagnosis.statusInTune),
        d('Dha', -16, 14, SwaraDiagnosis.statusInTune),
      ];
      expect(allLineNotesSung(atBar, bhopaliTable), isTrue);
      expect(allLineNotesSung(underBar, bhopaliTable), isFalse);
    });
  });
}
