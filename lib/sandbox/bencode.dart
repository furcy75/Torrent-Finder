import 'dart:convert';
import 'dart:typed_data';

/// Strict pure-Dart Bencode decoder and canonical encoder.
///
/// Security guarantees:
/// - Hard limit on nesting depth (prevents stack overflow / recursion bombs)
/// - Hard limit on total parsed elements (prevents CPU/RAM DoS)
/// - Hard limit on payload size (2 MiB)
/// - Captures exact raw byte slice of the root `info` dictionary so SHA-1
///   `info_hash` remains 100% bit-identical to the BitTorrent swarm.
class BencodeException implements Exception {
  BencodeException(this.message);
  final String message;

  @override
  String toString() => 'BencodeException: $message';
}

class DecodedTorrentRoot {
  const DecodedTorrentRoot({
    required this.root,
    required this.rawInfoBytes,
  });

  final Map<String, Object?> root;
  final Uint8List rawInfoBytes;
}

class Bencode {
  static const int maxDepth = 32;
  static const int maxItems = 15000;
  static const int maxPayloadBytes = 2 * 1024 * 1024;

  static Object? decode(Uint8List data) {
    final decoder = _BencodeDecoder(data);
    return decoder.decodeRoot();
  }

  static DecodedTorrentRoot decodeWithInfoBytes(Uint8List data) {
    final decoder = _BencodeDecoder(data);
    final root = decoder.decodeRoot();
    if (root is! Map<String, Object?>) {
      throw BencodeException('La racine du fichier .torrent doit être un dictionnaire');
    }
    final span = decoder.infoSpan;
    if (span == null || root['info'] is! Map<String, Object?>) {
      throw BencodeException('Dictionnaire "info" absent ou invalide');
    }
    return DecodedTorrentRoot(
      root: root,
      rawInfoBytes: Uint8List.sublistView(data, span.$1, span.$2),
    );
  }

  /// Encode Dart primitives (`int`, `Uint8List`, `String`, `List`, `Map<String, Object?>`)
  /// into canonical Bencode bytes.
  ///
  /// Map keys are interpreted as raw byte strings via `latin1` (1:1 mapping for 0x00..0xFF).
  static Uint8List encode(Object? value, {int depth = 0}) {
    final builder = BytesBuilder(copy: false);
    _encodeInto(builder, value, depth);
    return builder.toBytes();
  }

  static void _encodeInto(BytesBuilder out, Object? value, int depth) {
    if (depth > maxDepth) {
      throw BencodeException('Profondeur maximale d\'encodage dépassée');
    }
    if (value is int) {
      out.add(ascii.encode('i${value}e'));
      return;
    }
    if (value is Uint8List) {
      out.add(ascii.encode('${value.length}:'));
      out.add(value);
      return;
    }
    if (value is String) {
      final raw = utf8.encode(value);
      out.add(ascii.encode('${raw.length}:'));
      out.add(raw);
      return;
    }
    if (value is List) {
      out.addByte(0x6c); // 'l'
      for (final item in value) {
        _encodeInto(out, item, depth + 1);
      }
      out.addByte(0x65); // 'e'
      return;
    }
    if (value is Map) {
      out.addByte(0x64); // 'd'
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      for (final key in keys) {
        final keyBytes = Uint8List.fromList(latin1.encode(key));
        out.add(ascii.encode('${keyBytes.length}:'));
        out.add(keyBytes);
        _encodeInto(out, value[key], depth + 1);
      }
      out.addByte(0x65); // 'e'
      return;
    }
    throw BencodeException('Type non pris en charge pour Bencode : ${value.runtimeType}');
  }
}

class _BencodeDecoder {
  _BencodeDecoder(this.data) {
    if (data.isEmpty) {
      throw BencodeException('Fichier Bencode vide');
    }
    if (data.length > Bencode.maxPayloadBytes) {
      throw BencodeException(
        'Fichier trop volumineux (> ${Bencode.maxPayloadBytes} octets)',
      );
    }
  }

  final Uint8List data;
  int pos = 0;
  int items = 0;
  (int, int)? infoSpan;

  void _bumpItems() {
    items++;
    if (items > Bencode.maxItems) {
      throw BencodeException('Structure Bencode trop complexe (limite atteinte)');
    }
  }

  Object? decodeRoot() {
    final value = _decode(0, isRoot: true);
    if (pos != data.length) {
      throw BencodeException('Données superflues détectées à la position $pos');
    }
    return value;
  }

  Object? _decode(int depth, {bool isRoot = false}) {
    if (depth > Bencode.maxDepth) {
      throw BencodeException('Profondeur d\'imbrication Bencode dépassée');
    }
    if (pos >= data.length) {
      throw BencodeException('Fin de fichier Bencode inattendue');
    }
    _bumpItems();
    final byte = data[pos];
    if (byte == 0x69) {
      return _decodeInt(); // 'i'
    }
    if (byte == 0x6c) {
      return _decodeList(depth + 1); // 'l'
    }
    if (byte == 0x64) {
      return _decodeDict(depth + 1, captureInfo: isRoot); // 'd'
    }
    if (byte >= 0x30 && byte <= 0x39) {
      return _decodeBytes(); // '0'..'9'
    }
    throw BencodeException('Jeton Bencode invalide (0x${byte.toRadixString(16)}) à $pos');
  }

  int _decodeInt() {
    pos++; // skip 'i'
    final end = data.indexOf(0x65, pos); // 'e'
    if (end == -1) {
      throw BencodeException('Entier Bencode non terminé');
    }
    final raw = ascii.decode(Uint8List.sublistView(data, pos, end), allowInvalid: false);
    if (raw.isEmpty ||
        raw == '-0' ||
        raw.startsWith('-0') ||
        (raw.startsWith('0') && raw.length > 1)) {
      throw BencodeException('Entier Bencode non canonique : "$raw"');
    }
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      throw BencodeException('Entier Bencode invalide : "$raw"');
    }
    pos = end + 1;
    return parsed;
  }

  Uint8List _decodeBytes() {
    final colon = data.indexOf(0x3a, pos); // ':'
    if (colon == -1) {
      throw BencodeException('Longueur de chaîne Bencode non terminée');
    }
    final lenStr = ascii.decode(Uint8List.sublistView(data, pos, colon), allowInvalid: false);
    if (lenStr.isEmpty || (lenStr.startsWith('0') && lenStr.length > 1)) {
      throw BencodeException('Longueur de chaîne invalide : "$lenStr"');
    }
    final len = int.tryParse(lenStr);
    if (len == null || len < 0) {
      throw BencodeException('Longueur de chaîne négative ou invalide : "$lenStr"');
    }
    final start = colon + 1;
    final end = start + len;
    if (end > data.length) {
      throw BencodeException('Longueur de chaîne dépasse la fin du fichier');
    }
    pos = end;
    return Uint8List.fromList(Uint8List.sublistView(data, start, end));
  }

  List<Object?> _decodeList(int depth) {
    pos++; // skip 'l'
    final list = <Object?>[];
    while (pos < data.length && data[pos] != 0x65) {
      list.add(_decode(depth));
    }
    if (pos >= data.length) {
      throw BencodeException('Liste Bencode non terminée');
    }
    pos++; // skip 'e'
    return list;
  }

  Map<String, Object?> _decodeDict(int depth, {bool captureInfo = false}) {
    pos++; // skip 'd'
    final map = <String, Object?>{};
    while (pos < data.length && data[pos] != 0x65) {
      if (data[pos] < 0x30 || data[pos] > 0x39) {
        throw BencodeException('Clé de dictionnaire Bencode invalide à $pos');
      }
      final keyBytes = _decodeBytes();
      final key = latin1.decode(keyBytes);
      final valStart = pos;
      final val = _decode(depth);
      final valEnd = pos;
      if (captureInfo && key == 'info') {
        infoSpan = (valStart, valEnd);
      }
      map[key] = val;
    }
    if (pos >= data.length) {
      throw BencodeException('Dictionnaire Bencode non terminé');
    }
    pos++; // skip 'e'
    return map;
  }
}
