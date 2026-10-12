import 'dart:async';

import 'package:flutter/foundation.dart';

import 'lesson_remote_service.dart';

/// Key under which the student's school year (1, 2 or 3) is kept on the device.
const String kStudentLessonLevelKey = 'student_lesson_path';

/// Brings new lessons to the student WITHOUT any button.
///
/// When it runs (only while the app is open — a web page cannot sync in the
/// background, and this class does not pretend otherwise):
///  * when the app opens,
///  * when the app comes back to the foreground,
///  * when the browser reports the connection is back,
///  * every [interval] while the app is open and visible,
///  * a few seconds after a failure (growing delay, capped at [interval]).
///
/// Each run only lists lesson titles (small) and downloads what is new, so
/// data and battery use stay low. Already saved lessons are never touched by a
/// failure: they stay on the device and open offline.
class LessonAutoSync extends ChangeNotifier {
  LessonAutoSync({
    required this.readLevel,
    required this.syncLevel,
    required this.isConfigured,
    this.interval = const Duration(minutes: 4),
    this.minGap = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<int?> Function() readLevel;
  final Future<SyncReport> Function(int level) syncLevel;
  final bool Function() isConfigured;
  final Duration interval;
  final Duration minGap;
  final DateTime Function() _now;

  Timer? _timer;
  Timer? _retry;
  StreamSubscription<void>? _online;
  bool _running = false;
  bool _foreground = true;
  bool _again = false;
  DateTime? _lastAttempt;
  int _failStreak = 0;

  bool _syncing = false;
  bool _offline = false;
  String? _problem;
  String? _notice;
  DateTime? _lastOkAt;
  int _revision = 0;

  /// A run is in progress.
  bool get syncing => _syncing;

  /// The last run failed only because there is no connection.
  bool get offline => _offline;

  /// The last run failed for a reason worth telling the student.
  String? get problem => _problem;

  /// One-time good news (new lessons arrived); cleared by [clearNotice].
  String? get notice => _notice;

  /// When the last fully successful run finished.
  DateTime? get lastOkAt => _lastOkAt;

  /// Grows each time new lessons were saved; screens rebuild their lists on it.
  int get revision => _revision;

  /// Notifies only when new lessons were saved (for rebuilding lesson lists).
  final ValueNotifier<int> _revisionNotifier = ValueNotifier<int>(0);
  Listenable get revisionListenable => _revisionNotifier;

  /// Starts the periodic check and the "connection is back" trigger, then
  /// runs once now (app opened).
  void start(Stream<void> online) {
    stop();
    _timer = Timer.periodic(interval, (_) {
      if (_foreground) unawaited(trigger());
    });
    _online = online.listen((_) => unawaited(trigger(force: true)));
    unawaited(trigger(force: true));
  }

  void stop() {
    _timer?.cancel();
    _retry?.cancel();
    _online?.cancel();
    _timer = null;
    _retry = null;
    _online = null;
  }

  /// The app went to the background / came back.
  void setForeground(bool foreground) {
    final was = _foreground;
    _foreground = foreground;
    if (foreground && !was) unawaited(trigger());
  }

  bool _disposed = false;

  void clearNotice() {
    if (_disposed || _notice == null) return;
    _notice = null;
    notifyListeners();
  }

  /// Runs one check now. Unless [force], runs closer together than [minGap]
  /// are skipped. A forced call that arrives during a run is re-run after it.
  Future<void> trigger({bool force = false}) async {
    if (!isConfigured()) return;
    if (_running) {
      if (force) _again = true;
      return;
    }
    final t = _now();
    if (!force &&
        _lastAttempt != null &&
        t.difference(_lastAttempt!) < minGap) {
      return;
    }
    final level = await readLevel();
    if (level == null) return;

    _running = true;
    _lastAttempt = t;
    _syncing = true;
    notifyListeners();
    try {
      final r = await syncLevel(level);
      _offline = false;
      if (r.failed > 0) {
        _problem = 'تعذّر تنزيل بعض الدروس: ${r.errors.isEmpty ? '' : r.errors.first}'
            '\nسنعيد المحاولة تلقائيًا.';
        _scheduleRetry();
      } else {
        _problem = null;
        _failStreak = 0;
        _retry?.cancel();
        _lastOkAt = _now();
      }
      if (r.changedAnything) {
        _revision++;
        _revisionNotifier.value = _revision;
        _notice = r.added + r.updated == 1
            ? 'وصل درس جديد.'
            : 'وصلت ${r.added + r.updated} دروس جديدة.';
        Timer(const Duration(seconds: 12), clearNotice);
      }
    } on RemoteException catch (e) {
      if (e.transient) {
        _offline = true;
        _problem = null;
      } else {
        _offline = false;
        _problem = e.message;
      }
      _scheduleRetry();
    } catch (_) {
      _offline = false;
      _problem = 'تعذّر تحديث الدروس. سنعيد المحاولة تلقائيًا.';
      _scheduleRetry();
    } finally {
      _running = false;
      _syncing = false;
      notifyListeners();
    }
    if (_again) {
      _again = false;
      unawaited(trigger(force: true));
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _failStreak++;
    var seconds = 30 * (1 << (_failStreak - 1).clamp(0, 6).toInt());
    if (seconds > interval.inSeconds) seconds = interval.inSeconds;
    _retry = Timer(Duration(seconds: seconds), () {
      if (_foreground) unawaited(trigger(force: true));
    });
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    _revisionNotifier.dispose();
    super.dispose();
  }
}
