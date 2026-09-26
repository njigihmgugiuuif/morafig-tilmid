/// The canonical Event.type vocabulary — must match exactly what
/// algeria-intelligence-final-spec.md Section F enumerates. Kept as a
/// simple const list (not an enum) because Event.type is stored as free
/// text in SQLite for forward-compatibility (a future engine version can
/// introduce a new type without a schema migration), but every writer is
/// expected to only ever use a value from this list — enforced by
/// EventTypeValidator below, called from EventRepository before insert in
/// the (future) engine-integration phase.
const List<String> kKnownEventTypes = [
  'TaskCreated',
  'TaskCompleted',
  'TaskMissed',
  'TaskPostponed',
  'TaskChunkCompleted',
  'ExamCreated',
  'ExamMoved_earlier',
  'ExamMoved_later',
  'MasteryUpdated',
  'MemoryReviewCompleted',
  'ErrorRecorded',
  'AvailabilityChanged',
  'EmergencyEntered',
  'EmergencyExited',
  'PlanGenerated',
  'PlanInvalidated',
  'CurriculumDataStatusChanged',
  'WeightsCalibrated',
];

class EventTypeValidator {
  static bool isKnown(String type) => kKnownEventTypes.contains(type);
}
