import 'package:test/test.dart';

import 'package:student_app/engines/workload_engine.dart';

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment).
void main() {
  const engine = WorkloadEngine();

  group('classification boundaries', () {
    test('zero needed time is always underload, regardless of available',
        () {
      final r = engine.compute(neededMinutes: 0, availableMinutes: 100);
      expect(r.classification, WorkloadClassification.underload);
      expect(r.ratio, 0.0);
    });

    test('needed == available (ratio 1.0) classifies as overload, not '
        'balanced or impossible, under default thresholds', () {
      final r = engine.compute(neededMinutes: 100, availableMinutes: 100);
      expect(r.classification, WorkloadClassification.overload);
    });

    test('needed far beyond available classifies as impossible', () {
      final r = engine.compute(neededMinutes: 500, availableMinutes: 100);
      expect(r.classification, WorkloadClassification.impossible);
    });

    test('needed comfortably under available classifies as underload', () {
      final r = engine.compute(neededMinutes: 30, availableMinutes: 100);
      expect(r.classification, WorkloadClassification.underload);
    });

    test('needed moderately under available classifies as balanced', () {
      final r = engine.compute(neededMinutes: 80, availableMinutes: 100);
      expect(r.classification, WorkloadClassification.balanced);
    });
  });

  group('zero-available edge case', () {
    test('zero available and zero needed is underload (nothing to do, '
        'nothing to do it with — not a crisis)', () {
      final r = engine.compute(neededMinutes: 0, availableMinutes: 0);
      expect(r.classification, WorkloadClassification.underload);
    });

    test('zero available and positive needed is impossible, ratio is '
        'infinite, and this never throws', () {
      final r = engine.compute(neededMinutes: 30, availableMinutes: 0);
      expect(r.classification, WorkloadClassification.impossible);
      expect(r.ratio, double.infinity);
    });
  });

  group('monotonicity', () {
    test('classification never improves as neededMinutes increases, '
        'available held fixed', () {
      const order = [
        WorkloadClassification.underload,
        WorkloadClassification.balanced,
        WorkloadClassification.overload,
        WorkloadClassification.impossible,
      ];
      final needs = [10, 50, 80, 100, 110, 130, 300];
      var lastIndex = 0;
      for (final n in needs) {
        final r = engine.compute(neededMinutes: n, availableMinutes: 100);
        final idx = order.indexOf(r.classification);
        expect(idx, greaterThanOrEqualTo(lastIndex));
        lastIndex = idx;
      }
    });
  });

  group('validation', () {
    test('throws on negative inputs', () {
      expect(() => engine.compute(neededMinutes: -1, availableMinutes: 10),
          throwsArgumentError);
      expect(() => engine.compute(neededMinutes: 10, availableMinutes: -1),
          throwsArgumentError);
    });
  });
}
