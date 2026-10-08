import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sha256.dart';

/// Tiny key/value seam so the session logic is testable without Flutter's
/// SharedPreferences (tests use [MemoryKeyValueStore]).
abstract class KeyValueStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _map = {};
  @override
  Future<String?> getString(String key) async => _map[key];
  @override
  Future<void> setString(String key, String value) async => _map[key] = value;
  @override
  Future<void> remove(String key) async => _map.remove(key);
}

class SharedPrefsKeyValueStore implements KeyValueStore {
  @override
  Future<String?> getString(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> setString(String key, String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await (await SharedPreferences.getInstance()).remove(key);
  }
}

enum EntryResult { ok, nameRequired, pinRequired, pinWrong }

/// The teacher "entry" of this version (D-2 T01 / T05, open point O-1).
///
/// There is NO server, so this CANNOT verify who anyone is. The name is an
/// unverified label that appears on the teacher's lessons. The optional PIN
/// is a convenience lock on this device (a comfort, not protection): anyone
/// who can read the device's local storage can read or remove it. The UI
/// says so in words. A real, identity-verified teacher account is an open
/// decision and is NOT built here.
class TeacherSession {
  TeacherSession(this._store);
  final KeyValueStore _store;

  static const nameKey = 'teacher_display_name';
  static const pinHashKey = 'teacher_pin_hash';
  static const minPinLength = 4;

  Future<String> savedName() async => (await _store.getString(nameKey)) ?? '';

  Future<bool> hasPin() async =>
      ((await _store.getString(pinHashKey)) ?? '').isNotEmpty;

  static String hashPin(String pin) => Sha256.hexOfString('marafiq-pin:$pin');

  static bool isValidPinFormat(String pin) =>
      pin.length >= minPinLength && RegExp(r'^[0-9]+$').hasMatch(pin);

  /// Checks the entry form. When no PIN is set yet, [pin] is ignored here
  /// (setting one is done in the account screen, or here with [newPin]).
  Future<EntryResult> enter({
    required String name,
    String pin = '',
    String? newPin,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return EntryResult.nameRequired;
    final stored = (await _store.getString(pinHashKey)) ?? '';
    if (stored.isNotEmpty) {
      if (pin.isEmpty) return EntryResult.pinRequired;
      if (hashPin(pin) != stored) return EntryResult.pinWrong;
    } else if (newPin != null && newPin.isNotEmpty) {
      if (!isValidPinFormat(newPin)) return EntryResult.pinRequired;
      await _store.setString(pinHashKey, hashPin(newPin));
    }
    await _store.setString(nameKey, trimmed);
    return EntryResult.ok;
  }

  Future<void> rename(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('اسم الأستاذ مطلوب.');
    }
    await _store.setString(nameKey, trimmed);
  }

  /// Sets, changes or removes the comfort PIN. When a PIN already exists the
  /// current one must be given. Returns false on a wrong/invalid PIN.
  Future<bool> changePin({String currentPin = '', String? newPin}) async {
    final stored = (await _store.getString(pinHashKey)) ?? '';
    if (stored.isNotEmpty && hashPin(currentPin) != stored) return false;
    if (newPin == null || newPin.isEmpty) {
      await _store.remove(pinHashKey);
      return true;
    }
    if (!isValidPinFormat(newPin)) return false;
    await _store.setString(pinHashKey, hashPin(newPin));
    return true;
  }
}
