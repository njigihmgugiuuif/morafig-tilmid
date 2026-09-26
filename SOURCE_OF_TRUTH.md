# SOURCE_OF_TRUTH.md

| Entity | Raw/Derived | Source of Truth | Writable directly? | Append-only? | Derived from | Consumers |
|---|---|---|---|---|---|---|
| Student | Raw | itself | Yes (onboarding) | No | — | everything |
| AcademicYear | Raw | itself | Yes (setup) | No | — | CurriculumVersion, Task context |
| EducationLevel | Raw | itself (seed data) | Yes (seed) | No | — | Stream, Subject |
| Stream | Raw | itself (seed data) | Yes (seed) | No | — | SubjectLoad |
| PolicyDocument | Raw | itself (research phases 1/2-B/2-C) | Yes | No | — | CurriculumVersion, SubjectLoad |
| CurriculumVersion | Policy | PolicyDocument | Yes, via CurriculumRepository Guard #1 | No | PolicyDocument | SubjectLoad |
| SubjectLoad | Policy | PolicyDocument | **Only via CurriculumRepository.ingestSubjectLoad (Guard #1)** | No | PolicyDocument | PriorityEngine (future), via Guard #2 only |
| Subject/Unit/Lesson/KnowledgeNode | Raw | curriculum research data | Yes | No | — | Task, Mastery, Memory, Error |
| Prerequisite | Raw | curriculum research + engineering derivation | **Only via PrerequisiteRepository.insert (cycle check)** | No | KnowledgeNode graph | PriorityEngine Hard Constraints |
| Task | Planning | PriorityEngine output or user input | Yes | No | KnowledgeNode + generation logic | Scheduler |
| TaskSegment | Planning | Scheduler (when splitting) | Yes | No | Task | TimeEstimationEngine |
| Assignment/Exam/Deadline | Raw | **user input only** | Yes | No | — | PriorityEngine (examProximity, deadlinePressure) |
| StudySession | Planning | Scheduler | Yes | No | Task/TaskSegment + Availability | ObservationLayer, TimeEstimationEngine |
| Availability/RealityConstraint | Raw | **user input only, never inferred** | Yes, but RealityConstraint only via RealityConstraintRepository.insertFromUser | No | — | Scheduler, WorkloadEngine |
| MasteryState | **Derived** | ErrorRecord history (via BKT) | **No direct write — only MasteryRepository.recomputeFrom** | No | ErrorRecord | PriorityEngine |
| MemoryState | **Derived** | StudySession review history (via FSRS) | No direct write, only via a future MemoryRepository.recomputeFrom | No | StudySession | PriorityEngine |
| ErrorRecord | Raw (event-like) | actual graded answers | Yes (from ErrorEngine only, future phase) | Effectively append-only in practice | — | MasteryEngine, ErrorEngine signals |
| TimeEstimate | **Derived** | observed StudySession durations | via TimeEstimationEngine only (future phase) | No | StudySession.observedDuration | PriorityEngine, Scheduler |
| WorkloadState | **Derived, snapshot** | Task + Availability (current) | via WorkloadEngine only (future phase); **replaced, never accumulated** | No | Task, Availability | Scheduler, RecoveryEngine |
| PriorityState | **Derived** | all Signal sources, merged once | via PriorityEngine only (future phase) | No (superseded, not accumulated) | Mastery/Memory/Error/Time/Curriculum/RealityLayer signals | Scheduler |
| RecoveryRecord | Derived (decision record) | RecoveryEngine's triage decision | via RecoveryEngine only (future phase) | Effectively append-only (one record per triage decision) | Event + PriorityState | audit/UI |
| EmergencyState | Derived (state record) | EmergencyMode logic | via EmergencyMode only (future phase) | No (exitedAt updated once) | Exam/Workload signals | PriorityEngine reweighting |
| HumanOverride | Interaction | the student's actual action | insert-only | **Yes, enforced structurally** | — | calibration (future), audit |
| Explanation | Audit | the decision computation itself | insert-only | **Yes, enforced structurally** | PriorityState computation | UI, HumanOverride.systemStateSnapshotId |
| Event | Audit | the actual occurrence | insert-only (+ one-time processedAt set) | **Yes, enforced structurally** | — | ReplanningTrigger, MasteryState, MemoryState, etc. |
| AlgorithmVersion/ConfigurationVersion | Config | design-time releases | Yes (by developers, not runtime engines) | No | — | DecisionVersionBundle references |
| ThresholdRegistryEntry | Config | design-time defaults + calibration | Yes (calibration writes new rows, future phase) | No | ConfigurationVersion | PriorityEngine, RecoveryEngine, EmergencyMode |
| DataStateVersion | Audit pointer | the Event it references | insert-only | Effectively append-only | Event | reconstruction/audit tooling |
| SyncMetadataEntry | Sync bookkeeping | the entity it tracks | reserved for the future sync engine (unused this phase) | No | — | future Sync Engine |

**General rule applied everywhere above:** a Derived-State row is never a second, independent "opinion" about a fact — it is always recomputed from its Raw source and the Repository exposes no path to set it directly from anywhere except the one engine that owns that computation.
