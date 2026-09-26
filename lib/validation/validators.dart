/// Validation layer, deliberately independent of UI, import, sync, or any
/// engine. Every entry point (UI form submit, JSON import, a future sync
/// merge, an engine writing derived state) is expected to call the
/// relevant validator BEFORE the repository call — repositories themselves
/// also re-validate their own invariants (e.g. CurriculumRepository's
/// guards, MasteryRepository's [0,1] check) so a caller skipping this
/// layer does not bypass safety, only loses the clearer error messages
/// this layer provides.
library validation;

class ValidationError implements Exception {
  ValidationError(this.field, this.message);
  final String field;
  final String message;
  @override
  String toString() => 'ValidationError($field): $message';
}

class ValidationResult {
  const ValidationResult.valid() : errors = const [];
  const ValidationResult.invalid(this.errors);
  final List<ValidationError> errors;
  bool get isValid => errors.isEmpty;
}

class TaskValidator {
  static ValidationResult validate({
    required int estimatedDurationMinutes,
    required bool isSplittable,
    int? minimumChunkDurationMinutes,
    int? maximumChunkDurationMinutes,
  }) {
    final errors = <ValidationError>[];

    if (estimatedDurationMinutes <= 0) {
      errors.add(ValidationError('estimatedDurationMinutes',
          'must be > 0, got $estimatedDurationMinutes'));
    }

    if (isSplittable && minimumChunkDurationMinutes == null) {
      errors.add(ValidationError('minimumChunkDurationMinutes',
          'is required when isSplittable=true (Data Foundation Schema, '
          'Task contract)'));
    }

    if (isSplittable &&
        minimumChunkDurationMinutes != null &&
        estimatedDurationMinutes < 2 * minimumChunkDurationMinutes) {
      errors.add(ValidationError('estimatedDurationMinutes',
          'a splittable task must be at least 2x minimumChunkDuration, '
          'per the Intelligence Spec Section E splitting rules — otherwise '
          'splitting it can never produce two valid chunks'));
    }

    if (maximumChunkDurationMinutes != null &&
        minimumChunkDurationMinutes != null &&
        maximumChunkDurationMinutes < minimumChunkDurationMinutes) {
      errors.add(ValidationError('maximumChunkDurationMinutes',
          'must be >= minimumChunkDurationMinutes'));
    }

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }
}

class PriorityStateValidator {
  /// Invariant #16 (INV-16): weights used to compute a score must sum to
  /// 1.0. Small floating-point tolerance is intentional (exact equality on
  /// doubles is not meaningful) but bounded tightly enough to catch a real
  /// normalization bug rather than hide one.
  static ValidationResult validateWeightsSum(Map<String, double> weightsUsed) {
    final sum = weightsUsed.values.fold<double>(0, (a, b) => a + b);
    const tolerance = 0.0001;
    if ((sum - 1.0).abs() > tolerance) {
      return ValidationResult.invalid([
        ValidationError('weightsUsed',
            'must sum to 1.0 (Invariant #16), got $sum from $weightsUsed'),
      ]);
    }
    return const ValidationResult.valid();
  }

  static ValidationResult validateScore(double score) {
    if (score < 0 || score > 1) {
      return ValidationResult.invalid([
        ValidationError(
            'score', 'must be in [0,1] (Invariant #1), got $score'),
      ]);
    }
    return const ValidationResult.valid();
  }
}

class RealityConstraintValidator {
  static ValidationResult validate({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    if (!windowEnd.isAfter(windowStart)) {
      return ValidationResult.invalid([
        ValidationError(
            'windowEnd', 'must be after windowStart'),
      ]);
    }
    return const ValidationResult.valid();
  }
}
