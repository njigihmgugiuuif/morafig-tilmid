import 'dart:js_interop';

@JS('mqCanInstall')
external bool _canInstall();

@JS('mqIsStandalone')
external bool _isStandalone();

@JS('mqInstall')
external JSPromise<JSBoolean> _install();

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
