import 'package:test/test.dart';

import 'package:student_app/services/teacher_session.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
/// The PIN is a comfort lock, not authentication (O-1); these tests only pin
/// the behaviour the screens rely on.
void main() {
  late TeacherSession session;
  setUp(() => session = TeacherSession(MemoryKeyValueStore()));

  test('name is required', () async {
    expect(await session.enter(name: '  '), EntryResult.nameRequired);
  });

  test('first entry without PIN works and remembers the name', () async {
    expect(await session.enter(name: ' أ. سمير '), EntryResult.ok);
    expect(await session.savedName(), 'أ. سمير');
    expect(await session.hasPin(), isFalse);
  });

  test('a PIN can be created at entry, then it is required', () async {
    expect(await session.enter(name: 'أ', newPin: '1234'), EntryResult.ok);
    expect(await session.hasPin(), isTrue);
    expect(await session.enter(name: 'أ'), EntryResult.pinRequired);
    expect(await session.enter(name: 'أ', pin: '9999'), EntryResult.pinWrong);
    expect(await session.enter(name: 'أ', pin: '1234'), EntryResult.ok);
  });

  test('PIN format: at least 4 digits, digits only', () async {
    expect(await session.enter(name: 'أ', newPin: '12'), EntryResult.pinRequired);
    expect(await session.enter(name: 'أ', newPin: 'abcd'), EntryResult.pinRequired);
    expect(await session.hasPin(), isFalse);
  });

  test('changing and removing the PIN needs the current one', () async {
    await session.enter(name: 'أ', newPin: '1234');
    expect(await session.changePin(currentPin: 'bad', newPin: '5678'), isFalse);
    expect(await session.changePin(currentPin: '1234', newPin: '5678'), isTrue);
    expect(await session.enter(name: 'أ', pin: '5678'), EntryResult.ok);
    expect(await session.changePin(currentPin: '5678', newPin: ''), isTrue);
    expect(await session.hasPin(), isFalse);
  });

  test('the PIN is stored hashed, never in clear', () async {
    final store = MemoryKeyValueStore();
    final s = TeacherSession(store);
    await s.enter(name: 'أ', newPin: '1234');
    final stored = await store.getString(TeacherSession.pinHashKey);
    expect(stored, isNotNull);
    expect(stored, isNot('1234'));
    expect(stored!.length, 64);
  });

  test('rename refuses an empty name', () async {
    expect(() => session.rename(' '), throwsArgumentError);
  });
}
