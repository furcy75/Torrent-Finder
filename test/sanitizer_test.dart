import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/sandbox/bencode.dart';
import 'package:safetorrent/sandbox/sandbox_worker.dart';
import 'package:safetorrent/sandbox/torrent_sanitizer.dart';

Uint8List _makeTorrent({
  List<(List<String>, int)>? files,
  String singleName = 'Inception.2010.1080p.FRENCH.mkv',
}) {
  final info = <String, Object?>{
    'name': Uint8List.fromList(utf8.encode(singleName)),
    'piece length': 262144,
    'pieces': Uint8List.fromList(List<int>.filled(20, 0x11)),
  };

  if (files != null) {
    info['files'] = files
        .map(
          (f) => {
            'length': f.$2,
            'path': f.$1.map((seg) => Uint8List.fromList(utf8.encode(seg))).toList(),
          },
        )
        .toList();
  } else {
    info['length'] = 2400000000;
  }

  return Bencode.encode({
    'announce': Uint8List.fromList(utf8.encode('https://tracker.opentrackr.org/announce')),
    'comment': Uint8List.fromList(utf8.encode('Spam metadata to remove')),
    'created by': Uint8List.fromList(utf8.encode('UntrustedTool/1.0')),
    'info': info,
  });
}

void main() {
  test('Clean movie torrent passes and keeps bit-exact SHA-1 info_hash', () {
    final raw = _makeTorrent(
      files: [
        (['Inception.2010.1080p.FRENCH.mkv'], 2500000000),
        (['Inception.2010.fr.srt'], 85000),
      ],
    );
    final originalHash =
        sha1.convert(Bencode.decodeWithInfoBytes(raw).rawInfoBytes).toString().toLowerCase();

    final res = TorrentSanitizer.inspectAndSanitize(raw);

    expect(res.report.safeToDownload, isTrue);
    expect(res.report.status, equals(SafetyStatus.safe));
    expect(res.report.videoFileCount, equals(1));
    expect(res.report.infoHash, equals(originalHash));
    expect(res.report.sanitizedFieldsRemoved, containsAll(['comment', 'created by']));
    expect(res.sanitizedBytes, isNotNull);

    final rebuilt = Bencode.decodeWithInfoBytes(res.sanitizedBytes!);
    expect(rebuilt.root.containsKey('comment'), isFalse);
    expect(rebuilt.root.containsKey('created by'), isFalse);
    expect(sha1.convert(rebuilt.rawInfoBytes).toString().toLowerCase(), equals(originalHash));
  });

  test('Blocks executable and double-extension malware', () {
    final raw = _makeTorrent(
      files: [
        (['Movie.2026.1080p.mkv'], 1800000000),
        (['Codec_Required.mkv.exe'], 450000),
      ],
    );
    final res = TorrentSanitizer.inspectAndSanitize(raw);
    expect(res.report.safeToDownload, isFalse);
    expect(res.report.status, equals(SafetyStatus.blocked));
    expect(res.sanitizedBytes, isNull);
  });

  test('Blocks dangerous shortcuts, scripts, installers, and RTLO spoofing', () {
    final evilNames = [
      'Watch_Movie.lnk',
      'Play.bat',
      'Install.msi',
      'Trailer.scr',
      'run.ps1',
      'Movie_\u202evkm.exe',
    ];
    for (final name in evilNames) {
      final res = TorrentSanitizer.inspectAndSanitize(_makeTorrent(singleName: name));
      expect(res.report.safeToDownload, isFalse, reason: 'Should block $name');
      expect(res.sanitizedBytes, isNull);
    }
  });

  test('Blocks path traversal and password-trap archives', () {
    final traversal = _makeTorrent(
      files: [
        (['..', '..', 'Windows', 'evil.mkv'], 1000000),
      ],
    );
    expect(TorrentSanitizer.inspectAndSanitize(traversal).report.safeToDownload, isFalse);

    final archive = _makeTorrent(
      files: [
        (['Movie.2026.rar'], 1500000000),
        (['Password.txt'], 400),
      ],
    );
    expect(
      TorrentSanitizer.inspectAndSanitize(archive, blockArchives: true).report.safeToDownload,
      isFalse,
    );
  });

  test('Blocks fake torrent without any video file in strict mode', () {
    final fake = _makeTorrent(files: [(['Readme.txt'], 1200)]);
    final res = TorrentSanitizer.inspectAndSanitize(fake, strictVideoOnly: true);
    expect(res.report.safeToDownload, isFalse);
    expect(res.sanitizedBytes, isNull);
  });

  test('SSRF protection blocks private/loopback IPs and non-HTTP schemes', () async {
    const badUrls = [
      'file:///etc/passwd',
      'ftp://example.com/a.torrent',
      'http://127.0.0.1:8000/secret',
      'http://localhost/admin',
      'http://169.254.169.254/latest/meta-data/',
      'http://192.168.1.1/router',
    ];
    for (final url in badUrls) {
      final (ok, _) = await SandboxWorker.isUrlSafeToFetch(url);
      expect(ok, isFalse, reason: 'SSRF must block $url');
    }

    final (okLocal, _) = await SandboxWorker.isUrlSafeToFetch(
      'http://127.0.0.1:9117/dl',
      allowedLocalHosts: {'127.0.0.1'},
    );
    expect(okLocal, isTrue);
  });
}
