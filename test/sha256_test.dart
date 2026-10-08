import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:student_app/domain/sha256.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
/// Known FIPS 180-4 test vectors for the in-house SHA-256.
void main() {
  test('empty input', () {
    expect(Sha256.hex(const []),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });

  test('"abc"', () {
    expect(Sha256.hexOfString('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('two-block message (448 bits)', () {
    expect(
        Sha256.hexOfString(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
  });

  test('padding boundary: 55, 56 and 64 byte inputs differ and are stable', () {
    final a = Sha256.hex(Uint8List(55));
    final b = Sha256.hex(Uint8List(56));
    final c = Sha256.hex(Uint8List(64));
    expect({a, b, c}.length, 3);
    expect(Sha256.hex(Uint8List(55)), a);
    expect(a.length, 64);
  });

  test('UTF-8 text (Arabic) hashes the encoded bytes', () {
    expect(Sha256.hexOfString('درس'), isNot(Sha256.hexOfString('درس ')));
    expect(Sha256.hexOfString('درس'), Sha256.hexOfString('درس'));
  });
}
