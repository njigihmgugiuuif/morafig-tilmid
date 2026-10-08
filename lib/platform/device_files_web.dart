// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'device_files_types.dart';

export 'device_files_types.dart';

/// Web implementation using the browser's file input. `dart:html` is
/// deprecated (not removed) in the current SDKs and is used here only
/// because package:web would have to be added to pubspec.yaml, which phase C
/// may not touch. UNVERIFIED until the CI web build and a real phone test.
const bool deviceFilesAvailable = true;

Future<List<DeviceFile>> pickImages({bool capture = false}) =>
    _pick(accept: 'image/*', capture: capture, multiple: !capture);

Future<List<DeviceFile>> pickAnyFiles({String accept = '*/*'}) =>
    _pick(accept: accept, capture: false, multiple: false);

Future<List<DeviceFile>> _pick({
  required String accept,
  required bool capture,
  required bool multiple,
}) {
  final completer = Completer<List<DeviceFile>>();
  final input = html.FileUploadInputElement()
    ..accept = accept
    ..multiple = multiple
    ..style.display = 'none';
  // `capture` asks a phone browser to open the camera directly.
  if (capture) input.setAttribute('capture', 'environment');
  html.document.body?.append(input);

  void finish(List<DeviceFile> files) {
    if (!completer.isCompleted) completer.complete(files);
    input.remove();
  }

  input.onChange.first.then((_) async {
    try {
      final out = <DeviceFile>[];
      for (final f in input.files ?? <html.File>[]) {
        final reader = html.FileReader()..readAsArrayBuffer(f);
        await reader.onLoadEnd.first;
        final r = reader.result;
        if (r is Uint8List) {
          out.add(DeviceFile(f.name, r));
        } else if (r is ByteBuffer) {
          out.add(DeviceFile(f.name, Uint8List.view(r)));
        }
      }
      finish(out);
    } catch (e, s) {
      if (!completer.isCompleted) completer.completeError(e, s);
      input.remove();
    }
  });
  // Closing the picker without choosing fires `cancel` in current browsers.
  input.addEventListener('cancel', (_) => finish(const []));
  input.click();
  return completer.future;
}

Future<bool> saveBytesAs(
    String fileName, Uint8List bytes, String mimeType) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)..download = fileName;
  html.document.body?.append(a);
  a.click();
  a.remove();
  html.Url.revokeObjectUrl(url);
  return true;
}
