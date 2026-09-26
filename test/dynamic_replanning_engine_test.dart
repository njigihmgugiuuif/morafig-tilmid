import 'package:test/test.dart';

import 'package:student_app/engines/dynamic_replanning_engine.dart';

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment).
void main() {
  const engine = DynamicReplanningEngine();

  group('no signals', () {
    test('empty signal list never triggers a replan', () {
      final d = engine.evaluate(const []);
      expect(d.shouldReplan, isFalse);
      expect(d.triggeringSignals, isEmpty);
    });
  });

  group('hysteresis on durationDeviation', () {
    test('a small deviation, below the threshold, does NOT trigger a '
        'replan on its own', () {
      final d = engine.evaluate(const [
        ReplanningSignal(
            kind: ReplanTriggerKind.durationDeviation, magnitudeMinutes: 5),
      ]);
      expect(d.shouldReplan, isFalse);
    });

    test('a deviation at or above the threshold DOES trigger a replan', () {
      final d = engine.evaluate(const [
        ReplanningSignal(
            kind: ReplanTriggerKind.durationDeviation, magnitudeMinutes: 15),
      ]);
      expect(d.shouldReplan, isTrue);
      expect(d.triggeringSignals, hasLength(1));
    });

    test('a null magnitude is treated as zero, never as an unknown-so-'
        'trigger-anyway case', () {
      final d = engine.evaluate(const [
        ReplanningSignal(kind: ReplanTriggerKind.durationDeviation),
      ]);
      expect(d.shouldReplan, isFalse);
    });
  });

  group('discrete triggers always fire, regardless of magnitude', () {
    test('missedSession always triggers', () {
      final d = engine.evaluate(
          const [ReplanningSignal(kind: ReplanTriggerKind.missedSession)]);
      expect(d.shouldReplan, isTrue);
    });

    test('newUnavailability always triggers', () {
      final d = engine.evaluate(const [
        ReplanningSignal(kind: ReplanTriggerKind.newUnavailability)
      ]);
      expect(d.shouldReplan, isTrue);
    });

    test('workloadStatusChanged always triggers', () {
      final d = engine.evaluate(const [
        ReplanningSignal(kind: ReplanTriggerKind.workloadStatusChanged)
      ]);
      expect(d.shouldReplan, isTrue);
    });

    test('manualRequest always triggers', () {
      final d = engine.evaluate(
          const [ReplanningSignal(kind: ReplanTriggerKind.manualRequest)]);
      expect(d.shouldReplan, isTrue);
    });
  });

  group('mixed batches', () {
    test('only the signals that actually crossed their threshold are '
        'reported in triggeringSignals — a sub-threshold deviation '
        'alongside a real trigger is not falsely cited as a cause', () {
      final d = engine.evaluate(const [
        ReplanningSignal(
            kind: ReplanTriggerKind.durationDeviation, magnitudeMinutes: 3),
        ReplanningSignal(kind: ReplanTriggerKind.missedSession),
      ]);
      expect(d.shouldReplan, isTrue);
      expect(d.triggeringSignals, hasLength(1));
      expect(d.triggeringSignals.single.kind, ReplanTriggerKind.missedSession);
    });
  });
}
