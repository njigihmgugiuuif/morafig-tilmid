import 'dart:convert';

import '../engines/weekly_timeline_engine.dart' show WeekCalendar;

/// School timetable — pure logic (no database, no Flutter).
///
/// The student's school timetable is a grid: some days (Sunday-first index
/// 0..6) times some time slots. Each filled cell is stored as one
/// `WeeklyTemplateEntries` row of kind `school` (see
/// WeeklyTemplateRepository), which the planner already treats as a fixed
/// hard block. This file only knows the SHAPE of the grid (which days, which
/// slots) and how to move cells when the shape changes.
///
/// Nothing here is a default timetable: [SchoolTimetableLayout.photoModel] is
/// an OPTION the student chooses on purpose (the blank model of the table in
/// the photo the student sent: Sunday to Thursday, 08:00 to 17:00, break
/// 12:00 to 13:00). It has no subjects and it is never applied by itself.
///
/// STATUS: written without a Dart SDK; verified only by GitHub Actions.

const int kSchoolMaxSlots = 14;
const int kSchoolMaxLabel = 40;

/// One row of the grid: a lesson slot or a break.
class SchoolSlot {
  const SchoolSlot({
    required this.id,
    required this.startMinutes,
    required this.endMinutes,
    this.isBreak = false,
  });

  /// Stable inside one layout, so a slot whose times are edited can be
  /// matched with its old self (and its filled cells moved with it).
  final int id;
  final int startMinutes;
  final int endMinutes;
  final bool isBreak;

  int get durationMinutes => endMinutes - startMinutes;

  SchoolSlot copyWith({int? startMinutes, int? endMinutes, bool? isBreak}) =>
      SchoolSlot(
        id: id,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
        isBreak: isBreak ?? this.isBreak,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': startMinutes,
        'end': endMinutes,
        'break': isBreak,
      };

  static SchoolSlot? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], s = j['start'], e = j['end'];
    if (id is! int || s is! int || e is! int) return null;
    if (s < 0 || s >= 1440 || e <= s || e > 1440) return null;
    return SchoolSlot(
        id: id, startMinutes: s, endMinutes: e, isBreak: j['break'] == true);
  }

  @override
  bool operator ==(Object other) =>
      other is SchoolSlot &&
      other.id == id &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes &&
      other.isBreak == isBreak;

  @override
  int get hashCode => Object.hash(id, startMinutes, endMinutes, isBreak);
}

/// A filled cell as stored (one `school` row of the weekly template).
class SchoolEntry {
  const SchoolEntry({
    required this.id,
    required this.dayStored,
    required this.startMinutes,
    required this.endMinutes,
    required this.label,
  });

  final String id;

  /// Stored day (Dart weekday: 1 = Monday ... 7 = Sunday).
  final int dayStored;
  final int startMinutes;
  final int endMinutes;
  final String label;

  /// Sunday-first index (0..6), or null for an invalid stored day.
  int? get dayIndex => WeekCalendar.isValidStoredDay(dayStored)
      ? WeekCalendar.indexFromStoredDay(dayStored)
      : null;
}

/// What happens to filled cells when the layout is edited.
class LayoutChangePlan {
  const LayoutChangePlan({required this.removed, required this.retimed});

  /// Cells whose day or slot no longer exists: they are deleted.
  final List<SchoolEntry> removed;

  /// Cells whose slot got new times: deleted and written again at [to].
  final List<({SchoolEntry entry, SchoolSlot to})> retimed;

  bool get isEmpty => removed.isEmpty && retimed.isEmpty;
}

class SchoolTimetableLayout {
  const SchoolTimetableLayout({required this.days, required this.slots});

  /// Sunday-first day indexes (0 = Sunday ... 6 = Saturday), sorted, unique.
  final List<int> days;

  /// Sorted by start time.
  final List<SchoolSlot> slots;

  static const SchoolTimetableLayout empty =
      SchoolTimetableLayout(days: <int>[], slots: <SchoolSlot>[]);

  /// The blank model of the table in the photo the student sent. Only the
  /// shape: no subjects. Offered as a choice, never applied by default.
  factory SchoolTimetableLayout.photoModel() => const SchoolTimetableLayout(
        days: [0, 1, 2, 3, 4],
        slots: [
          SchoolSlot(id: 1, startMinutes: 480, endMinutes: 540),
          SchoolSlot(id: 2, startMinutes: 540, endMinutes: 600),
          SchoolSlot(id: 3, startMinutes: 600, endMinutes: 660),
          SchoolSlot(id: 4, startMinutes: 660, endMinutes: 720),
          SchoolSlot(id: 5, startMinutes: 720, endMinutes: 780, isBreak: true),
          SchoolSlot(id: 6, startMinutes: 780, endMinutes: 840),
          SchoolSlot(id: 7, startMinutes: 840, endMinutes: 900),
          SchoolSlot(id: 8, startMinutes: 900, endMinutes: 960),
          SchoolSlot(id: 9, startMinutes: 960, endMinutes: 1020),
        ],
      );

  /// Sorts days and slots and removes duplicate days.
  factory SchoolTimetableLayout.normalized(
      Iterable<int> days, Iterable<SchoolSlot> slots) {
    final d = days.where((x) => x >= 0 && x <= 6).toSet().toList()..sort();
    final s = slots.toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return SchoolTimetableLayout(days: d, slots: s);
  }

  List<SchoolSlot> get periods =>
      [for (final s in slots) if (!s.isBreak) s];

  /// True when there is at least one day and one lesson slot.
  bool get isConfigured => days.isNotEmpty && periods.isNotEmpty;

  int get nextSlotId {
    var m = 0;
    for (final s in slots) {
      if (s.id > m) m = s.id;
    }
    return m + 1;
  }

  SchoolSlot? slotById(int id) {
    for (final s in slots) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The lesson slot whose times equal [start]..[end], or null.
  SchoolSlot? slotForTimes(int start, int end) {
    for (final s in slots) {
      if (!s.isBreak && s.startMinutes == start && s.endMinutes == end) {
        return s;
      }
    }
    return null;
  }

  // ------------------------------------------------------ validation

  /// An Arabic message for the first problem found, or null when the layout
  /// is acceptable to save.
  static String? validate(Iterable<int> days, Iterable<SchoolSlot> slots) {
    final d = days.toSet();
    if (d.isEmpty) return 'اختر يومًا واحدًا على الأقل.';
    if (d.any((x) => x < 0 || x > 6)) return 'يوم غير صالح.';
    final list = slots.toList();
    if (list.where((s) => !s.isBreak).isEmpty) {
      return 'أضف حصة واحدة على الأقل.';
    }
    if (list.length > kSchoolMaxSlots) {
      return 'عدد الصفوف كبير (الأقصى $kSchoolMaxSlots).';
    }
    final ids = <int>{};
    for (final s in list) {
      if (!ids.add(s.id)) return 'تعذّر الحفظ: صفّان بالرقم نفسه.';
      if (s.startMinutes < 0 || s.startMinutes >= 1440) {
        return 'بداية حصة خارج اليوم.';
      }
      if (s.endMinutes <= s.startMinutes) {
        return 'نهاية الحصة يجب أن تكون بعد بدايتها.';
      }
      if (s.endMinutes > 1440) return 'الحصة يجب أن تنتهي قبل منتصف الليل.';
    }
    final sorted = [...list]
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].startMinutes < sorted[i - 1].endMinutes) {
        return 'حصتان متداخلتان في الوقت. اجعل بداية الثانية بعد نهاية الأولى.';
      }
    }
    return null;
  }

  /// Message for a subject name typed in a cell, or null when fine.
  static String? validateLabel(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'اكتب اسم المادة.';
    if (t.length > kSchoolMaxLabel) {
      return 'الاسم طويل (الأقصى $kSchoolMaxLabel حرفًا).';
    }
    return null;
  }

  // ------------------------------------------------------ JSON

  Map<String, dynamic> toJson() => {
        'v': 1,
        'days': days,
        'slots': [for (final s in slots) s.toJson()],
      };

  String encode() => jsonEncode(toJson());

  /// Reads a stored layout. A damaged or invalid value gives null (never a
  /// guess): the caller then rebuilds the layout from the stored cells.
  static SchoolTimetableLayout? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final dRaw = j['days'], sRaw = j['slots'];
      if (dRaw is! List || sRaw is! List) return null;
      final days = <int>[
        for (final x in dRaw)
          if (x is int) x
      ];
      final slots = <SchoolSlot>[
        for (final x in sRaw)
          if (SchoolSlot.fromJson(x) != null) SchoolSlot.fromJson(x)!
      ];
      final layout = SchoolTimetableLayout.normalized(days, slots);
      if (validate(layout.days, layout.slots) != null) return null;
      return layout;
    } on FormatException {
      return null;
    }
  }

  // ------------------------------------------------------ cells

  /// True when [e] sits on a day and a slot of this layout.
  bool fits(SchoolEntry e) {
    final idx = e.dayIndex;
    if (idx == null || !days.contains(idx)) return false;
    return slotForTimes(e.startMinutes, e.endMinutes) != null;
  }

  /// The stored cell at [dayIndex] / [slot], or null. If duplicated rows
  /// exist, the first one is returned.
  static SchoolEntry? cellAt(
      List<SchoolEntry> entries, int dayIndex, SchoolSlot slot) {
    for (final e in entries) {
      if (e.dayIndex == dayIndex &&
          e.startMinutes == slot.startMinutes &&
          e.endMinutes == slot.endMinutes) {
        return e;
      }
    }
    return null;
  }

  /// Subject names the student already used, most used first (for quick
  /// pick). Only names typed by the student; nothing is suggested from
  /// elsewhere.
  static List<String> usedLabels(List<SchoolEntry> entries) {
    final counts = <String, int>{};
    for (final e in entries) {
      final t = e.label.trim();
      if (t.isEmpty) continue;
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final names = counts.keys.toList()
      ..sort((a, b) {
        final c = counts[b]!.compareTo(counts[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    return names;
  }

  /// Builds the layout that explains stored cells which this layout does not
  /// show (for instance after a restore, when the layout was lost but the
  /// cells were kept). Days of the cells are added; a missing slot is added
  /// only if it does not overlap another slot. Cells that still do not fit
  /// stay stored and are counted by [outsideGridCount].
  SchoolTimetableLayout mergedWith(List<SchoolEntry> entries) {
    final days = <int>{...this.days};
    final slots = [...this.slots];
    var nextId = nextSlotId;
    final seen = <String>{};
    final sortedEntries = [...entries]..sort((a, b) {
        final c = a.startMinutes.compareTo(b.startMinutes);
        return c != 0 ? c : a.endMinutes.compareTo(b.endMinutes);
      });
    for (final e in sortedEntries) {
      final idx = e.dayIndex;
      if (idx == null) continue;
      days.add(idx);
      final key = '${e.startMinutes}-${e.endMinutes}';
      if (!seen.add(key)) continue;
      final exists = slots.any((s) =>
          !s.isBreak &&
          s.startMinutes == e.startMinutes &&
          s.endMinutes == e.endMinutes);
      if (exists) continue;
      if (e.endMinutes > 1440) continue;
      final overlaps = slots.any((s) =>
          e.startMinutes < s.endMinutes && s.startMinutes < e.endMinutes);
      if (overlaps) continue;
      slots.add(SchoolSlot(
          id: nextId++,
          startMinutes: e.startMinutes,
          endMinutes: e.endMinutes));
    }
    return SchoolTimetableLayout.normalized(days, slots);
  }

  int outsideGridCount(List<SchoolEntry> entries) =>
      entries.where((e) => !fits(e)).length;

  // ------------------------------------------------------ changes

  /// What must happen to the stored cells to go from [oldLayout] to
  /// [next]. Cells that did not belong to the old grid are never touched.
  static LayoutChangePlan planChange({
    required SchoolTimetableLayout oldLayout,
    required SchoolTimetableLayout next,
    required List<SchoolEntry> entries,
  }) {
    final removed = <SchoolEntry>[];
    final retimed = <({SchoolEntry entry, SchoolSlot to})>[];
    for (final e in entries) {
      if (!oldLayout.fits(e)) continue; // not part of the old grid
      final oldSlot = oldLayout.slotForTimes(e.startMinutes, e.endMinutes)!;
      final idx = e.dayIndex!;
      final newSlot = next.slotById(oldSlot.id);
      if (newSlot == null || newSlot.isBreak || !next.days.contains(idx)) {
        removed.add(e);
        continue;
      }
      if (newSlot.startMinutes != e.startMinutes ||
          newSlot.endMinutes != e.endMinutes) {
        retimed.add((entry: e, to: newSlot));
      }
    }
    return LayoutChangePlan(removed: removed, retimed: retimed);
  }

  /// Arabic label for a slot, e.g. «08:00 – 09:00».
  static String slotText(SchoolSlot s) =>
      '${minutesText(s.startMinutes)} – ${minutesText(s.endMinutes)}';

  static String minutesText(int m) {
    final mm = m % 1440;
    return '${(mm ~/ 60).toString().padLeft(2, '0')}:'
        '${(mm % 60).toString().padLeft(2, '0')}';
  }
}
