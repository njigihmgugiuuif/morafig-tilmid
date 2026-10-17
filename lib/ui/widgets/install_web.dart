import 'dart:js_interop';

@JS('mqCanInstall')
external bool _canInstall();

@JS('mqIsStandalone')
external bool _isStandalone();

@JS('mqInstall')
external JSPromise<JSBoolean> _install();

@JS('mqIsIos')
external bool _isIos();

@JS('mqOfflineReady')
external JSPromise<JSBoolean> _offlineReady();

@JS('mqWatchInstall')
external void _watch(JSFunction callback);

bool canPromptInstall() {
  try {
    return _canInstall();
  } catch (_) {
    return false;
  }
}

bool isStandalone() {
  try {
    return _isStandalone();
  } catch (_) {
    return false;
  }
}

Future<bool> promptInstall() async {
  try {
    return (await _install().toDart).toDart;
  } catch (_) {
    return false;
  }
}

bool isIos() {
  try {
    return _isIos();
  } catch (_) {
    return false;
  }
}

/// Calls [onChange] when the browser's install state changes (the install
/// prompt became available, or the app was installed).
void watchInstall(void Function() onChange) {
  try {
    _watch(onChange.toJS);
  } catch (_) {
    // No watcher: the button simply keeps the state it had at first paint.
  }
}

/// True when the offline worker is active and the saved copy holds the start
/// page and the files the app needs to start. False on any doubt.
Future<bool> offlineReady() async {
  try {
    return (await _offlineReady().toDart).toDart;
  } catch (_) {
    return false;
  }
}
