import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/sandbox/bencode.dart';

void main() {
  test('Bencode roundtrip preserves exact raw info bytes', () {
    final payload = {
      'announce': Uint8List.fromList(utf8.encode('https://tracker.example.org/announce')),
      'info': {
        'length': 1500000000,
        'name': Uint8List.fromList(utf8.encode('Movie.2025.1080p.FRENCH.mkv')),
        'piece length': 262144,
        'pieces': Uint8List.fromList(List<int>.filled(20, 0xAB)),
      },
    };

    final encoded = Bencode.encode(payload);
    final decoded = Bencode.decodeWithInfoBytes(encoded);
    expect(decoded.rawInfoBytes, equals(Bencode.encode(payload['info'])));
  });

  test('Bencode rejects deep recursion bombs', () {
    final bomb = Uint8List.fromList([
      ...List<int>.filled(50, 0x6c), // 'l'
      ...List<int>.filled(50, 0x65), // 'e'
    ]);
    expect(() => Bencode.decode(bomb), throwsA(isA<BencodeException>()));
  });

  test('Bencode rejects non-canonical integers and HTML error pages', () {
    expect(
      () => Bencode.decode(Uint8List.fromList(ascii.encode('i-0e'))),
      throwsA(isA<BencodeException>()),
    );
    expect(
      () => Bencode.decodeWithInfoBytes(
        Uint8List.fromList(utf8.encode('<!DOCTYPE html><html><body>Fake</body></html>')),
      ),
      throwsA(isA<BencodeException>()),
    );
  });
}
