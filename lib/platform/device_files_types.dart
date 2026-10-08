import 'dart:typed_data';

/// A file the user chose on their device.
class DeviceFile {
  const DeviceFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}
