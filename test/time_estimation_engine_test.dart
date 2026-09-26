import 'package:test/test.dart';

import 'package:student_app/engines/time_estimation_engine.dart';

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment).
void main() {
  const engine = TimeEstimationEngine();

  group('compute() — no observed samples', () {
    test('uses curriculum default verbatim when present', () {
      final r = engine.compute(
        curriculumDefaultMinutes: 45,
        observedSamples: const [],
      );
      expect(r.estimatedDurationMinutes, 45);
      expect(r.basis, TimeEstimateBasis.curriculumDefault);
      expect(r.confidenceLevel, TimeConfidenceLevel.low);
    });

    test('falls back to fallbackDurationMinutes with zero confidence when '
        'neither source exists', () {
      final r = engine.compute(
        curriculumDefaultMinutes: null,
        observedSamples: const [],
      );
      expect(r.estimatedDurationMinutes, engine.fallbackDurationMinutes);
      expect(r.confidenceValue, 0.0);
    });
  });

  group('compute() — observed samples only', () {
    test('estimate is close to the (recency-weighted) mean of samples', () {
      final r = engine.compute(
        curriculumDefaultMinutes: null,
        observedSamples: const [
          ObservedDuration(minutes: 40, daysAgo: 0.0),
          ObservedDuration(minutes: 40, daysAgo: 0.0),
          ObservedDuration(minutes: 40, daysAgo: 0.0),
        ],
      );
      expect(r.estimatedDurationMinutes, 40);
      expect(r.basis, TimeEstimateBasis.observedHistory);
    });

    test('more samples increases confidence, all else equal', () {
      final few = engine.compute(
        curriculumDefaultMinutes: null,
        observedSamples: const [
          ObservedDuration(minutes: 30, daysAgo: 0.0),
        ],
      );
      final many = engine.compute(
        curriculumDefaultMinutes: null,
        observedSamples: List.generate(
            10, (i) => const ObservedDuration(minutes: 30, daysAgo: 0.0)),
      );
      expect(many.confidenceValue, greaterThan(few.confidenceValue));
    });

    test('tighter agreement across samples increases confidence versus '
        'scattered samples with the same mean', () {
      final tight = engine.compute(
        curriculumDefaultMinutes: null,
        observedSamples: const [
          ObservedDuration(minutes: 29, daysAgo: 0.0),
          ObservedDuration(minutes: 30, daysAgo: 0.0),
          ObservedDuration(minutes: 31, daysAgo: 0.0),
        ],
      );
      final scattered = engine.compute(
        curriculumDefaultMinutes: null,
        observedSamples: const [
          ObservedDuration(minutes: 5, daysAgo: 0.0),
          ObservedDuration(minutes: 30, daysAgo: 0.0),
          ObservedDuration(minutes: 55, daysAgo: 0.0),
        ],
      );
      expect(tight.confidenceValue, greaterThan(scattered.confidenceValue));
    });
  });

  group('compute() — hybrid', () {
    test('blended estimate lies between curriculum default and observed '
        'mean', () {
      final r = engine.compute(
        curriculumDefaultMinutes: 60,
        observedSamples: const [
          ObservedDuration(minutes: 30, daysAgo: 0.0),
          ObservedDuration(minutes: 30, daysAgo: 0.0),
        ],
      );
      expect(r.basis, TimeEstimateBasis.hybrid);
      expect(r.estimatedDurationMinutes, greaterThanOrEqualTo(30));
      expect(r.estimatedDurationMinutes, lessThanOrEqualTo(60));
    });

    test('more observed samples pulls the hybrid estimate closer to the '
        'observed mean than fewer samples do', () {
      final fewSamples = engine.compute(
        curriculumDefaultMinutes: 60,
        observedSamples: const [
          ObservedDuration(minutes: 20, daysAgo: 0.0),
        ],
      );
      final manySamples = engine.compute(
        curriculumDefaultMinutes: 60,
        observedSamples: List.generate(
            20, (i) => const ObservedDuration(minutes: 20, daysAgo: 0.0)),
      );
      expect(manySamples.estimatedDurationMinutes,
          lessThan(fewSamples.estimatedDurationMinutes));
    });

    test('confidenceValue never exceeds 1.0', () {
      final r = engine.compute(
        curriculumDefaultMinutes: 30,
        observedSamples: List.generate(
            100, (i) => const ObservedDuration(minutes: 30, daysAgo: 0.0)),
      );
      expect(r.confidenceValue, lessThanOrEqualTo(1.0));
    });
  });

  group('validation', () {
    test('throws on negative daysAgo', () {
      expect(
          () => engine.compute(
                curriculumDefaultMinutes: null,
                observedSamples: const [
                  ObservedDuration(minutes: 30, daysAgo: -1.0),
                ],
              ),
          throwsArgumentError);
    });
  });
}
