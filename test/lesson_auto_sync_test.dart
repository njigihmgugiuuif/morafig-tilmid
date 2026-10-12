import 'dart:async';

import 'package:test/test.dart';

import 'package:student_app/services/lesson_auto_sync.dart';
import 'package:student_app/services/lesson_remote_service.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Logic of the automatic arrival of lessons (no button): when it runs, that
/// it never runs twice at once, how it reacts to no connection and to a
/// problem, and that it recovers by itself. The timers and the browser's
/// "online" event are not what is tested here; their effect is, through
/// [LessonAutoSync.trigger] and the stream given to [LessonAutoSync.start].
void main() {
  late int calls;
  late int? level;
  late bool configured;
  late DateTime clock;
  Future<SyncReport> Function(int) behaviour = (_) async => const SyncReport();
  late LessonAutoSync sync;

  setUp(() {
    calls = 0;
    level = 2;
    configured = true;
    clock = DateTime(2026, 1, 1, 8);
    behaviour = (_) async => const SyncReport(unchanged: 1);
    sync = LessonAutoSync(
      readLevel: () async => level,
      syncLevel: (l) {
        calls++;
        return behaviour(l);
      },
      isConfigured: () => configured,
      interval: const Duration(minutes: 4),
      minGap: const Duration(seconds: 20),
      now: () => clock,
    );
  });
  tearDown(() => sync.dispose());

  test('does nothing without a chosen year or without a configured server',
      () async {
    level = null;
    await sync.trigger(force: true);
    expect(calls, 0);
    level = 2;
    configured = false;
    await sync.trigger(force: true);
    expect(calls, 0);
  });

  test('new lessons raise the revision and give a one-time notice', () async {
    behaviour = (_) async => const SyncReport(added: 2, pagesReceived: 5);
    await sync.trigger(force: true);
    expect(sync.revision, 1);
    expect(sync.notice, contains('2'));
    expect(sync.problem, isNull);
    expect(sync.lastOkAt, isNotNull);
    sync.clearNotice();
    expect(sync.notice, isNull);
  });

  test('nothing new: no revision change and no notice', () async {
    await sync.trigger(force: true);
    expect(sync.revision, 0);
    expect(sync.notice, isNull);
    expect(sync.lastOkAt, isNotNull);
  });

  test('runs closer than the minimum gap are skipped unless forced', () async {
    await sync.trigger(force: true);
    clock = clock.add(const Duration(seconds: 5));
    await sync.trigger();
    expect(calls, 1);
    clock = clock.add(const Duration(seconds: 30));
    await sync.trigger();
    expect(calls, 2);
    await sync.trigger(force: true);
    expect(calls, 3);
  });

  test('never two runs at once; a forced call during a run re-runs after it',
      () async {
    final gate = Completer<SyncReport>();
    behaviour = (_) => gate.future;
    final first = sync.trigger(force: true);
    await Future<void>.delayed(Duration.zero);
    await sync.trigger(force: true); // queued, not started
    expect(calls, 1);
    behaviour = (_) async => const SyncReport(unchanged: 1);
    gate.complete(const SyncReport(unchanged: 1));
    await first;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 2);
  });

  test('no connection is calm: offline flag, no problem text, then recovers',
      () async {
    behaviour = (_) async =>
        throw const RemoteException('تعذّر الاتصال', transient: true);
    await sync.trigger(force: true);
    expect(sync.offline, isTrue);
    expect(sync.problem, isNull);

    behaviour = (_) async => const SyncReport(added: 1, pagesReceived: 3);
    await sync.trigger(force: true); // what the "back online" event does
    expect(sync.offline, isFalse);
    expect(sync.revision, 1);
  });

  test('a server problem is shown, and cleared after a good run', () async {
    behaviour = (_) async =>
        throw const RemoteException('رفض الخادم الطلب (500).');
    await sync.trigger(force: true);
    expect(sync.problem, contains('500'));
    expect(sync.offline, isFalse);
    behaviour = (_) async => const SyncReport(unchanged: 1);
    await sync.trigger(force: true);
    expect(sync.problem, isNull);
  });

  test('a lesson that failed to download is reported and will be retried',
      () async {
    behaviour = (_) async => const SyncReport(
        added: 1, failed: 1, errors: ['الدرس س: الصورة 2 من 3 لم تصل']);
    await sync.trigger(force: true);
    expect(sync.problem, contains('الصورة 2 من 3'));
    expect(sync.revision, 1, reason: 'the lesson that did arrive is shown');
  });

  test('the connection-back stream and app start trigger a run', () async {
    final online = StreamController<void>();
    sync.start(online.stream);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1, reason: 'app opened');
    online.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 2, reason: 'connection back');
    sync.stop();
    await online.close();
  });

  test('coming back to the foreground checks again (after the gap)', () async {
    await sync.trigger(force: true);
    sync.setForeground(false);
    clock = clock.add(const Duration(minutes: 10));
    sync.setForeground(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 2);
  });
}
