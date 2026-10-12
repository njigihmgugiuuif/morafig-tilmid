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

/// Shrinks a phone photo before it is stored or published: longest side at
/// most [maxSide] px, re-encoded as JPEG. Phone photos are 3–8 MB each; a
/// lesson of several pages would otherwise exceed what the shared storage
/// accepts. The browser applies the photo's rotation (EXIF) when drawing.
///
/// Returns the ORIGINAL bytes whenever anything fails or the result would not
/// be smaller, so a picture is never lost or made worse by this step.
Future<Uint8List> compressImage(Uint8List bytes,
    {int maxSide = 1600, double quality = 0.78}) async {
  String? url;
  try {
    url = html.Url.createObjectUrlFromBlob(html.Blob([bytes]));
    final img = html.ImageElement(src: url);
    await img.onLoad.first.timeout(const Duration(seconds: 20));
    final w = img.naturalWidth;
    final h = img.naturalHeight;
    if (w <= 0 || h <= 0) return bytes;
    final longest = w > h ? w : h;
    final scale = longest > maxSide ? maxSide / longest : 1.0;
    final cw = (w * scale).round();
    final ch = (h * scale).round();
    final canvas = html.CanvasElement(width: cw, height: ch);
    final ctx = canvas.context2D;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, cw, ch);
    ctx.drawImageScaled(img, 0, 0, cw, ch);
    final blob = await canvas.toBlob('image/jpeg', quality);
    final reader = html.FileReader()..readAsArrayBuffer(blob);
    await reader.onLoadEnd.first;
    final r = reader.result;
    final Uint8List out;
    if (r is Uint8List) {
      out = r;
    } else if (r is ByteBuffer) {
      out = Uint8List.view(r);
    } else {
      return bytes;
    }
    return (out.isNotEmpty && out.length < bytes.length) ? out : bytes;
  } catch (_) {
    return bytes;
  } finally {
    if (url != null) html.Url.revokeObjectUrl(url);
  }
}
