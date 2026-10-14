// Reloads the page (web only). Used when the app came back from the
// background and its storage did not answer: a reload restores everything
// from what is saved on the device.
export 'page_control_stub.dart' if (dart.library.html) 'page_control_web.dart';
