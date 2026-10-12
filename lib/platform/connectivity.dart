// "Connection is back" signal. On Flutter Web the browser's own `online`
// event is used (no package needed); elsewhere there is no signal and the
// stub returns an empty stream.
export 'connectivity_stub.dart' if (dart.library.html) 'connectivity_web.dart';
