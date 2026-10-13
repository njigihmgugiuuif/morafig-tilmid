import 'dart:convert';

import 'lesson_auto_sync.dart' show kStudentLessonLevelKey;
import 'teacher_session.dart' show KeyValueStore;

/// What the student told us about their school year (device-local).
///
/// Kept in the device's own key-value storage, NOT in the database: the
/// database schema is frozen (v6) and its level/stream columns point to
/// official rows that do not exist (no official list is shipped, by design).
/// The year is one of the three internal levels (1, 2, 3). The stream /
/// section is free text typed by the student: no official list is imposed.
class StudentSetup {
  const StudentSetup({this.year, this.track = ''});
  final int? year;
  final String track;

  bool get isEmpty => year == null && track.trim().isEmpty;

  Map<String, dynamic> toJson() => {'year': year, 'track': track};

  static StudentSetup fromJson(Map<String, dynamic> j) {
    final y = j['year'];
    return StudentSetup(
      year: (y is int && y >= 1 && y <= 3) ? y : null,
      track: (j['track'] as String?)?.trim() ?? '',
    );
  }
}

class StudentSetupStore {
  StudentSetupStore(this._kv);
  final KeyValueStore _kv;

  static const key = 'student_setup_v1';

  Future<StudentSetup> read() async {
    final raw = await _kv.getString(key);
    if (raw == null || raw.isEmpty) return const StudentSetup();
    try {
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) return StudentSetup.fromJson(d);
    } on FormatException {
      // A damaged value is treated as "not set", never as a guess.
    }
    return const StudentSetup();
  }

  /// Saves the year and stream. The year also becomes the lesson path the
  /// library uses, so the student is never asked for it twice.
  Future<void> save(StudentSetup s) async {
    await _kv.setString(key, jsonEncode(s.toJson()));
    if (s.year != null) {
      await _kv.setString(kStudentLessonLevelKey, '${s.year}');
    }
  }

  /// Forgets only the year and stream (and the lesson path that came from
  /// the year). Nothing in the database is touched.
  Future<void> clear() async {
    await _kv.remove(key);
    await _kv.remove(kStudentLessonLevelKey);
  }
}

/// A recurring busy time typed during registration (day 0 = Sunday).
class DraftCommitment {
  const DraftCommitment({
    required this.day,
    required this.startMinutes,
    required this.endMinutes,
    this.label = '',
  });
  final int day;
  final int startMinutes;
  final int endMinutes;
  final String label;

  Map<String, dynamic> toJson() => {
        'day': day,
        'start': startMinutes,
        'end': endMinutes,
        'label': label,
      };

  static DraftCommitment? fromJson(Object? j) {
    if (j is! Map) return null;
    final d = j['day'], s = j['start'], e = j['end'];
    if (d is! int || s is! int || e is! int) return null;
    if (d < 0 || d > 6 || s < 0 || s >= 1440 || e <= s || e > 1440) return null;
    return DraftCommitment(
        day: d,
        startMinutes: s,
        endMinutes: e,
        label: (j['label'] as String?) ?? '');
  }
}

/// Everything typed in the first-run journey, saved after each change so
/// closing the app never loses it. Cleared when the journey is finished.
class OnboardingDraft {
  const OnboardingDraft({
    this.step = 0,
    this.name = '',
    this.sleepHours = 7,
    this.year,
    this.track = '',
    this.commitments = const [],
    this.goalKind = 'exam',
    this.subject = '',
    this.goalTitle = '',
    this.goalDate,
  });

  final int step;
  final String name;
  final int sleepHours;
  final int? year;
  final String track;
  final List<DraftCommitment> commitments;
  final String goalKind; // exam | general | later
  final String subject;
  final String goalTitle;
  final DateTime? goalDate;

  Map<String, dynamic> toJson() => {
        'step': step,
        'name': name,
        'sleepHours': sleepHours,
        'year': year,
        'track': track,
        'commitments': [for (final c in commitments) c.toJson()],
        'goalKind': goalKind,
        'subject': subject,
        'goalTitle': goalTitle,
        'goalDate': goalDate?.toIso8601String(),
      };

  static OnboardingDraft fromJson(Map<String, dynamic> j) {
    final y = j['year'];
    final sh = j['sleepHours'];
    final st = j['step'];
    return OnboardingDraft(
      step: (st is int && st >= 0 && st <= 5) ? st : 0,
      name: (j['name'] as String?) ?? '',
      sleepHours: (sh is int && sh >= 5 && sh <= 10) ? sh : 7,
      year: (y is int && y >= 1 && y <= 3) ? y : null,
      track: (j['track'] as String?) ?? '',
      commitments: [
        for (final c in (j['commitments'] is List ? j['commitments'] as List : const []))
          if (DraftCommitment.fromJson(c) != null) DraftCommitment.fromJson(c)!,
      ],
      goalKind: const {'exam', 'general', 'later'}.contains(j['goalKind'])
          ? j['goalKind'] as String
          : 'exam',
      subject: (j['subject'] as String?) ?? '',
      goalTitle: (j['goalTitle'] as String?) ?? '',
      goalDate: DateTime.tryParse((j['goalDate'] as String?) ?? ''),
    );
  }
}

class OnboardingDraftStore {
  OnboardingDraftStore(this._kv);
  final KeyValueStore _kv;

  static const key = 'onboarding_draft_v1';

  Future<OnboardingDraft?> read() async {
    final raw = await _kv.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) return OnboardingDraft.fromJson(d);
    } on FormatException {
      // damaged draft: start fresh
    }
    return null;
  }

  Future<void> write(OnboardingDraft d) => _kv.setString(key, jsonEncode(d.toJson()));

  Future<void> clear() => _kv.remove(key);
}
