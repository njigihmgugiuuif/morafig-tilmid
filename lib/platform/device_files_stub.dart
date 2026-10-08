import 'dart:typed_data';

import 'device_files_types.dart';

export 'device_files_types.dart';

/// Not-web fallback: no file input is available without an image/file
/// package (open decision O-4). The UI shows this as an honest message and
/// offers the clipboard route for packages instead.
const bool deviceFilesAvailable = false;

Future<List<DeviceFile>> pickImages({bool capture = false}) async =>
    throw UnsupportedError('device_files_unavailable');

Future<List<DeviceFile>> pickAnyFiles({String accept = '*/*'}) async =>
    throw UnsupportedError('device_files_unavailable');

Future<bool> saveBytesAs(
        String fileName, Uint8List bytes, String mimeType) async =>
    false;
