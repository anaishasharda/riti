// Feedback mapper (F1a, plan 1.5-lite; the teacher's seven rules, 2026-10-22).
//
// Pure function: a per-swara diagnosis in, one student-language card out.
// Deterministic — the same diagnosis always yields the same sentences, so
// the pilot's teacher-agreement metric can be scored against it. No
// numbers, no cents, no "flat"/"sharp" ever reach the student (rule 4).
//
// The teacher's rules, as implemented here:
//  1. A uniform whole-scale shift gets ONE Sa message, never per-note
//     errors. The app never plays a drone during recording, so the message
//     is always framed against the saved Sa, which is named as possibly
//     wrong. Strength scales: gentle up to 40c, stronger beyond it.
//  2. Priority: shift, then wrong note, then low/high, then length.
//     A note too short to judge gets "hold that note longer", never a
//     tuning verdict — even when it would otherwise be the fix.
//  3. Exactly ONE fix plus ONE thing that went well, then retry.
//  4. "A little low / a little high" (never flat/sharp). The "a little"
//     tier runs to 50c; beyond that the plain form.
//  5. Wrong notes are mostly unnamed — the student copies the right note
//     from the Hear sound. Named only for a clear raga-rule break: the
//     note's median sits within 35c of a real degree outside the raga
//     (e.g. Ma in Bhopali).
//  6. The retry sound is Sa first, then the note (Sa… Ga), never the note
//     alone. [FeedbackCardContent.hearTokens] carries exactly that.
//  7. One actionable fix plus the sound to copy. If Sa itself was off,
//     that is the message.
//
// Tunable at §6 validation: [_shiftThresholdCents],
// [_strongShiftThresholdCents], [_littleTierCents], [_minPointsToJudge],
// [_wrongNoteNamingBandCents].
import 'sa_pitch.dart';

/// What kind of card this is. F1b renders on it: the shift kind can offer
/// a "Re-check Sa" action to Profile, the other kinds a Hear button.
enum FeedbackKind {
  /// The whole scale moved together: one Sa message, not per-note errors.
  shift,

  /// A note landed on a different pitch class.
  wrongNote,

  /// One note low or high.
  tuning,

  /// The note was too short to judge.
  length,

  /// The note was not sung at all.
  notSung,

  /// Every note in tune: praise only, no fix.
  allInTune,
}

/// The content of one feedback card: exactly one fix (rules 3/7) plus one
/// thing that went well, plus the sound to copy (rule 6).
class FeedbackCardContent {
  final FeedbackKind kind;

  /// The one fix, in student language. Null only when [kind] is
  /// [FeedbackKind.allInTune].
  final String? fix;

  /// The one thing that went well. Null when nothing specific went well.
  final String? reinforcement;

  /// Tokens for ToneSynthService.playPattern, always Sa first (rule 6).
  /// Empty when there is no sound to copy (shift, all-in-tune).
  final List<String> hearTokens;

  const FeedbackCardContent({
    required this.kind,
    required this.fix,
    required this.reinforcement,
    required this.hearTokens,
  });
}

/// Uniform shift at or beyond this is one Sa message, not per-note errors.
const double _shiftThresholdCents = 30.0;

/// Beyond this the Sa message takes its stronger form.
const double _strongShiftThresholdCents = 40.0;

/// A low/high fix at or below this is "a little low/high"; beyond it the
/// plain form ("was high", as in the teacher's worked example at +67c).
const double _littleTierCents = 50.0;

/// A sung note with fewer voiced points than this is too short to judge.
const int _minPointsToJudge = 8;

/// A wrong note is named only when its median sits within this of a real
/// degree outside the raga.
const double _wrongNoteNamingBandCents = 35.0;

/// The twelve chromatic degrees, in semitone order from Sa, with their
/// swara names. Used only to name a clear raga-rule break (rule 5).
const List<String> _chromaticSwaraNames = [
  'Sa', // 0
  'komal Re', // 100
  'Re', // 200
  'komal Ga', // 300
  'Ga', // 400
  'Ma', // 500
  'teevra Ma', // 600
  'Pa', // 700
  'komal Dha', // 800
  'Dha', // 900
  'komal Ni', // 1000
  'Ni', // 1100
];

/// Map a per-swara diagnosis to one feedback card, per the teacher's rules.
///
/// [diagnosis] is the list [diagnoseSwara] produces, in table order.
/// [table] is the raga's swara table, needed to place a wrong note on the
/// chromatic scale for rule-5 naming.
FeedbackCardContent mapDiagnosisToFeedback(
  List<SwaraDiagnosis> diagnosis,
  RagaSwaraTable table,
) {
  assert(diagnosis.isNotEmpty, 'mapDiagnosisToFeedback needs a diagnosis');

  final sung = diagnosis
      .where((d) => d.status != SwaraDiagnosis.statusNotSung)
      .toList();

  // 1. Uniform shift (rule 1): the median of the sung deviations. notSung
  // is excluded — its 0.0 deviation is a placeholder, not a measurement.
  if (sung.isNotEmpty) {
    final shift = _median(
      sung.map((d) => d.medianDeviationCents).toList(),
    );
    if (shift.abs() >= _shiftThresholdCents) {
      final direction = shift > 0 ? 'high' : 'low';
      final strong = shift.abs() > _strongShiftThresholdCents;
      final fix = strong
          ? 'Everything sounds $direction against your saved Sa — your saved Sa is probably off. Re-check it from Profile before your next take.'
          : 'Everything sounds a little $direction against your saved Sa. Your saved Sa might be a touch off — re-check it from Profile and sing again.';
      // The shape line is the honest praise for a shift — the intervals
      // were right, only the Sa moved. It does not hold when a note also
      // went wrong, so then fall back to the usual reinforcement.
      final hasWrongNote = sung.any(
        (d) => d.status == SwaraDiagnosis.statusWrongNote,
      );
      final reinforcement = hasWrongNote
          ? _reinforcementFor(diagnosis, null)
          : 'The shape of your scale was right — every note moved together.';
      return FeedbackCardContent(
        kind: FeedbackKind.shift,
        fix: fix,
        reinforcement: reinforcement,
        hearTokens: const [],
      );
    }
  }

  // 2. Fix candidate (rule 2): a wrong note first, then the worst low/high.
  SwaraDiagnosis? candidate;
  final wrongNotes = sung
      .where((d) => d.status == SwaraDiagnosis.statusWrongNote)
      .toList();
  if (wrongNotes.isNotEmpty) {
    candidate = _worstByAbsDev(wrongNotes);
  } else {
    final offTune = sung
        .where(
          (d) =>
              d.status == SwaraDiagnosis.statusFlat ||
              d.status == SwaraDiagnosis.statusSharp,
        )
        .toList();
    if (offTune.isNotEmpty) candidate = _worstByAbsDev(offTune);
  }

  if (candidate != null) {
    // Too short to judge (rule 2 exception): never a tuning verdict on a
    // note with too few points — ask them to hold it longer instead.
    if (candidate.pointCount < _minPointsToJudge) {
      return FeedbackCardContent(
        kind: FeedbackKind.length,
        fix:
            'Hold your ${candidate.swara} a little longer — it was too short to judge.',
        reinforcement: _reinforcementFor(diagnosis, candidate.swara),
        hearTokens: ['Sa', candidate.swara],
      );
    }
    if (candidate.status == SwaraDiagnosis.statusWrongNote) {
      final named = _ruleBreakName(candidate, table);
      final fix = named != null
          ? 'That went up to $named — ${table.ragaName} doesn\'t use $named. Listen (Sa… ${candidate.swara}) and sing it again.'
          : 'One note landed outside the raga — listen (Sa… ${candidate.swara}) and sing it again.';
      return FeedbackCardContent(
        kind: FeedbackKind.wrongNote,
        fix: fix,
        reinforcement: _reinforcementFor(diagnosis, candidate.swara),
        hearTokens: ['Sa', candidate.swara],
      );
    }
    // Tuning fix (rule 4): "a little low/high" up to 50c, plain beyond.
    final direction =
        candidate.medianDeviationCents < 0 ? 'low' : 'high';
    final little =
        candidate.medianDeviationCents.abs() <= _littleTierCents;
    final fix = little
        ? 'Your ${candidate.swara} was a little $direction. Listen (Sa… ${candidate.swara}) and sing it again.'
        : 'Your ${candidate.swara} was $direction. Listen (Sa… ${candidate.swara}) and sing it again.';
    return FeedbackCardContent(
      kind: FeedbackKind.tuning,
      fix: fix,
      reinforcement: _reinforcementFor(diagnosis, candidate.swara),
      hearTokens: ['Sa', candidate.swara],
    );
  }

  // 3. No wrong note and nothing off-tune: a note sung too briefly.
  final shortNotes = sung
      .where((d) => d.pointCount < _minPointsToJudge)
      .toList();
  if (shortNotes.isNotEmpty) {
    shortNotes.sort((a, b) => a.pointCount.compareTo(b.pointCount));
    final shortest = shortNotes.first;
    return FeedbackCardContent(
      kind: FeedbackKind.length,
      fix:
          'Hold your ${shortest.swara} a little longer — it was too short to judge.',
      reinforcement: _reinforcementFor(diagnosis, shortest.swara),
      hearTokens: ['Sa', shortest.swara],
    );
  }

  // 4. A note not sung at all. Not in the teacher's priority list; ranked
  // lowest here because a skipped note is a line problem, not a tuning
  // one, and the retry covers it.
  final missing = diagnosis
      .where((d) => d.status == SwaraDiagnosis.statusNotSung)
      .toList();
  if (missing.isNotEmpty) {
    final first = missing.first;
    return FeedbackCardContent(
      kind: FeedbackKind.notSung,
      fix:
          'You didn\'t sing ${first.swara} this time — listen (Sa… ${first.swara}) and try it again.',
      reinforcement: _reinforcementFor(diagnosis, first.swara),
      hearTokens: ['Sa', first.swara],
    );
  }

  // 5. Everything in tune.
  return const FeedbackCardContent(
    kind: FeedbackKind.allInTune,
    fix: null,
    reinforcement:
        'Every note was in tune. Sing it once more to make it stick.',
    hearTokens: [],
  );
}

/// The one thing that went well (rule 3): the in-tune notes by name, or —
/// when nothing is fully in tune — the closest sung note. Null when there
/// is no other sung note to praise.
String? _reinforcementFor(
  List<SwaraDiagnosis> diagnosis,
  String? excludeSwara,
) {
  final inTune = diagnosis
      .where(
        (d) =>
            d.status == SwaraDiagnosis.statusInTune &&
            d.swara != excludeSwara,
      )
      .map((d) => d.swara)
      .toList();
  if (inTune.isNotEmpty) {
    final names = _joinNames(inTune);
    return '$names ${inTune.length == 1 ? 'was' : 'were'} right in tune.';
  }
  final sung = diagnosis
      .where(
        (d) =>
            d.status != SwaraDiagnosis.statusNotSung &&
            d.swara != excludeSwara,
      )
      .toList();
  if (sung.isEmpty) return null;
  sung.sort(
    (a, b) => a.medianDeviationCents
        .abs()
        .compareTo(b.medianDeviationCents.abs()),
  );
  return 'Your ${sung.first.swara} was closest — nearly there.';
}

/// Name a wrong note only when it is a clear raga-rule break (rule 5):
/// its median sits within [_wrongNoteNamingBandCents] of a real degree
/// that is outside the raga. Otherwise null (unnamed — the Hear sound
/// carries the correction).
String? _ruleBreakName(SwaraDiagnosis wrongNote, RagaSwaraTable table) {
  final center = _centerOrNull(table, wrongNote.swara);
  if (center == null) return null;
  final absolute =
      ((center + wrongNote.medianDeviationCents) % 1200 + 1200) % 1200;
  var bestIndex = 0;
  var bestDist = double.infinity;
  for (var i = 0; i < 12; i++) {
    final degreeCents = i * 100.0;
    var dist = (absolute - degreeCents).abs();
    if (dist > 600) dist = 1200 - dist;
    if (dist < bestDist) {
      bestDist = dist;
      bestIndex = i;
    }
  }
  if (bestDist > _wrongNoteNamingBandCents) return null;
  final degreeCents = bestIndex * 100.0;
  if (table.swaras.any((s) => s.cents == degreeCents)) return null;
  return _chromaticSwaraNames[bestIndex];
}

double? _centerOrNull(RagaSwaraTable table, String swara) {
  for (final s in table.swaras) {
    if (s.name == swara) return s.cents;
  }
  return null;
}

SwaraDiagnosis _worstByAbsDev(List<SwaraDiagnosis> ds) {
  var worst = ds.first;
  for (final d in ds.skip(1)) {
    if (d.medianDeviationCents.abs() >
        worst.medianDeviationCents.abs()) {
      worst = d;
    }
  }
  return worst;
}

double _median(List<double> values) {
  final sorted = List<double>.from(values)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

String _joinNames(List<String> names) {
  if (names.length == 1) return names.first;
  if (names.length == 2) return '${names[0]} and ${names[1]}';
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// Line-coverage check (f-gap fix): did the take actually cover the
/// line's swaras with enough points each to count as sung?
///
/// A take of stray frames can leave a swara "sung" on a handful of
/// points (the notSung floor is only max(3, ceil(2% of voiced))), so a
/// non-line take can come back with a confident in-tune verdict. This
/// gate counts the line's swaras with status other than notSung and
/// requires at least half of them (rounded up): for the 5-note Bhopali
/// line that is 3. An empty diagnosis is not covered (never asserted —
/// callers check coverage before mapping).
bool isLineCovered(List<SwaraDiagnosis> diagnosis, RagaSwaraTable table) {
  if (diagnosis.isEmpty) return false;
  final inTable = table.swaras.map((s) => s.name).toSet();
  var covered = 0;
  for (final d in diagnosis) {
    if (inTable.contains(d.swara) && d.status != SwaraDiagnosis.statusNotSung) {
      covered++;
    }
  }
  return covered >= (table.swaras.length + 1) ~/ 2;
}
