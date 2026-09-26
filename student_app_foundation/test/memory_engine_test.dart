import 'package:test/test.dart';

import 'package:student_app/engines/memory_engine.dart';

/// STATUS: UNVERIFIED. This file has not been run through a real Dart
/// test runner (no Flutter/Dart SDK in the environment that wrote it —
/// same standing limitation as the rest of this codebase). It must be
/// the first thing run, alongside export_import_test.dart, once a real
/// toolchain is available: `flutter test test/memory_engine_test.dart`.
///
/// These are PROPERTY tests — checking invariants that must hold given
/// the published FSRS-4.5 formulas (see memory_engine.dart's doc comment
/// for the source), not hand-computed numeric oracles. A property that's
/// wrong here means either the formula transcription has a bug, or the
/// property itself was reasoned about incorrectly — either way, a real
/// test run is what turns this from "reviewed" into "verified".
void main() {
  final engine = MemoryEngine();

  group('retrievability()', () {
    test('R(0, S) == 1 for any stability, by construction', () {
      for (final s in [0.1, 1.0, 10.0, 365.0]) {
        expect(engine.retrievability(0.0, s), closeTo(1.0, 1e-9));
      }
    });

    test('retrievability strictly decreases as elapsed time increases', () {
      const s = 10.0;
      final rAt1 = engine.retrievability(1.0, s);
      final rAt5 = engine.retrievability(5.0, s);
      final rAt20 = engine.retrievability(20.0, s);
      expect(rAt5, lessThan(rAt1));
      expect(rAt20, lessThan(rAt5));
    });

    test('retrievability stays in (0, 1] for non-negative elapsed time', () {
      for (final t in [0.0, 1.0, 100.0, 10000.0]) {
        final r = engine.retrievability(t, 5.0);
        expect(r, greaterThan(0.0));
        expect(r, lessThanOrEqualTo(1.0));
      }
    });

    test('throws on non-positive stability — not a representable state',
        () {
      expect(() => engine.retrievability(1.0, 0.0), throwsArgumentError);
      expect(() => engine.retrievability(1.0, -1.0), throwsArgumentError);
    });
  });

  group('intervalForDesiredRetention()', () {
    test(
        'interval(0.9, S) == S by definition of stability '
        '(S is "days for R to fall to 0.9")', () {
      for (final s in [1.0, 5.0, 30.0, 100.0]) {
        final interval =
            engine.intervalForDesiredRetention(desiredRetention: 0.9, stability: s);
        expect(interval, closeTo(s, s * 1e-6 + 1e-6));
      }
    });

    test('lower desired retention yields a longer interval for the same S',
        () {
      const s = 20.0;
      final iAt90 =
          engine.intervalForDesiredRetention(desiredRetention: 0.9, stability: s);
      final iAt80 =
          engine.intervalForDesiredRetention(desiredRetention: 0.8, stability: s);
      expect(iAt80, greaterThan(iAt90));
    });

    test('interval is never less than 1 day even for tiny stability', () {
      final interval =
          engine.intervalForDesiredRetention(desiredRetention: 0.9, stability: 0.01);
      expect(interval, greaterThanOrEqualTo(1.0));
    });

    test('rejects desiredRetention outside the open interval (0, 1)', () {
      expect(
          () => engine.intervalForDesiredRetention(
              desiredRetention: 0.0, stability: 10.0),
          throwsArgumentError);
      expect(
          () => engine.intervalForDesiredRetention(
              desiredRetention: 1.0, stability: 10.0),
          throwsArgumentError);
    });
  });

  group('initialState()', () {
    test('difficulty is always within [1, 10] for every grade', () {
      for (final g in MemoryGrade.values) {
        final state = engine.initialState(g);
        expect(state.difficulty, greaterThanOrEqualTo(1.0));
        expect(state.difficulty, lessThanOrEqualTo(10.0));
      }
    });

    test('stability is positive for every grade', () {
      for (final g in MemoryGrade.values) {
        expect(engine.initialState(g).stability, greaterThan(0.0));
      }
    });

    test('a first review of "easy" starts with lower difficulty than '
        '"forgot" — easier first impressions predict an easier card', () {
      final easy = engine.initialState(MemoryGrade.easy).difficulty;
      final forgot = engine.initialState(MemoryGrade.forgot).difficulty;
      expect(easy, lessThan(forgot));
    });
  });

  group('reviewFrom()', () {
    test('difficulty stays within [1, 10] across a long, mixed grade '
        'sequence — the clamp must hold under repeated updates, not just '
        'once', () {
      var dsr = engine.initialState(MemoryGrade.good);
      const sequence = [
        MemoryGrade.good,
        MemoryGrade.hard,
        MemoryGrade.forgot,
        MemoryGrade.easy,
        MemoryGrade.good,
        MemoryGrade.forgot,
        MemoryGrade.forgot,
        MemoryGrade.easy,
      ];
      for (final grade in sequence) {
        dsr = engine.reviewFrom(
          previous: dsr,
          elapsedDaysSincePreviousReview: dsr.stability, // reviewed on-time
          grade: grade,
        );
        expect(dsr.difficulty, greaterThanOrEqualTo(1.0));
        expect(dsr.difficulty, lessThanOrEqualTo(10.0));
        expect(dsr.stability, greaterThan(0.0));
      }
    });

    test('forgetting can never increase stability beyond its prior value',
        () {
      final dsr = engine.initialState(MemoryGrade.good);
      final afterForgetting = engine.reviewFrom(
        previous: dsr,
        elapsedDaysSincePreviousReview: dsr.stability,
        grade: MemoryGrade.forgot,
      );
      expect(afterForgetting.stability, lessThanOrEqualTo(dsr.stability));
    });

    test(
        'reviewing exactly on schedule (elapsed == stability, so R≈0.9) '
        'with "good" increases stability — successful spaced review should '
        'grow the interval, not shrink it', () {
      final dsr = engine.initialState(MemoryGrade.good);
      final after = engine.reviewFrom(
        previous: dsr,
        elapsedDaysSincePreviousReview: dsr.stability,
        grade: MemoryGrade.good,
      );
      expect(after.stability, greaterThan(dsr.stability));
    });
  });
}
