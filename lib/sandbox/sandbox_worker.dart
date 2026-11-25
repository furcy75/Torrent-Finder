import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:safetorrent/models/safety_report.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/sandbox/bencode.dart';
import 'package:safetorrent/sandbox/torrent_sanitizer.dart';

/// Isolated Dart Isolate Sandbox Worker.
///
/// Runs 100% on-device (Android APK, Windows EXE, Linux binary) with zero PC/server:
/// 1. Executes inside a separate memory-isolated Dart Isolate (`Isolate.run`).
/// 2. Pure raw HTTP streaming (ZERO WebView, ZERO browser, ZERO JavaScript).
/// 3. Hard 2 MiB ceiling in RAM + rejects `text/html` pages immediately.
/// 4. Strict SSRF validation on initial URL AND every redirect hop (max 5 hops).
/// 5. Runs `TorrentSanitizer.inspectAndSanitize` and returns only the clean report
///    + rebuilt `.torrent` bytes.
class SandboxWorker {
  static const int maxRedirects = 5;
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration totalTimeout = Duration(seconds: 18);
  static const String userAgent = 'TorrentSeeder/2.0 (Standalone-Sandbox)';

  static Future<SandboxExecutionResult> fetchAndSanitize({
    String? torrentUrl,
    String? infoHash,
    bool strictVideoOnly = true,
    bool blockArchives = true,
    Set<String> allowedLocalHosts = const {},
  }) {
    final localList = allowedLocalHosts.map((h) => h.toLowerCase()).toList();
    final platformLabel = Platform.isAndroid
        ? 'Android OS Sandbox + Dart Isolate'
        : Platform.isWindows
            ? 'Windows + Dart Isolate'
            : 'Linux + Dart Isolate';

    return Isolate.run(
      () => _executeInIsolate(
        torrentUrl: torrentUrl,
        infoHash: infoHash,
        strictVideoOnly: strictVideoOnly,
        blockArchives: blockArchives,
        allowedLocalHosts: localList.toSet(),
        sandboxMode: platformLabel,
      ),
    );
  }

  /// Validate a URL against SSRF (scheme + private/loopback/link-local IP blocking).
  static Future<(bool, String)> isUrlSafeToFetch(
    String rawUrl, {
    Set<String> allowedLocalHosts = const {},
  }) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return (false, 'URL invalide ou malformée');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return (false, 'Protocole interdit ("$scheme") — uniquement HTTP/HTTPS');
    }

    final host = uri.host.toLowerCase();
    if (allowedLocalHosts.contains(host)) {
      return (true, '');
    }

    if (host == 'localhost' ||
        host == 'localhost.localdomain' ||
        host.endsWith('.local')) {
      return (false, 'Accès hôte local refusé par le bac à sable ($host)');
    }

    final directIp = InternetAddress.tryParse(host);
    if (directIp != null) {
      if (isRestrictedIp(directIp)) {
        return (false, 'Adresse IP privée/interne bloquée par le bac à sable ($host)');
      }
      return (true, '');
    }

    try {
      final addresses = await InternetAddress.lookup(host).timeout(connectTimeout);
      if (addresses.isEmpty) {
        return (false, 'Domaine introuvable ($host)');
      }
      for (final addr in addresses) {
        if (isRestrictedIp(addr)) {
          return (
            false,
            'Adresse IP privée/interne bloquée par le bac à sable (${addr.address})',
          );
        }
      }
      return (true, '');
    } catch (_) {
      return (false, 'Impossible de résoudre le domaine ($host)');
    }
  }

  static bool isRestrictedIp(InternetAddress addr) {
    if (addr.isLoopback || addr.isLinkLocal || addr.isMulticast) return true;
    final bytes = addr.rawAddress;

    if (addr.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final a = bytes[0];
      final b = bytes[1];
      if (a == 0) return true; // 0.0.0.0/8
      if (a == 10) return true; // 10.0.0.0/8
      if (a == 127) return true; // 127.0.0.0/8
      if (a == 169 && b == 254) return true; // 169.254.0.0/16 (cloud metadata / link-local)
      if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
      if (a == 192 && b == 168) return true; // 192.168.0.0/16
      if (a == 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10 CGNAT
      if (a >= 224) return true; // Multicast & reserved
      return false;
    }

    if (addr.type == InternetAddressType.IPv6 && bytes.length == 16) {
      // Unspecified ::
      if (bytes.every((b) => b == 0)) return true;
      // Unique local fc00::/7
      if ((bytes[0] & 0xFE) == 0xFC) return true;
      // Link-local fe80::/10
      if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) return true;
      // IPv4-mapped ::ffff:0:0/96
      final isV4Mapped = bytes.sublist(0, 10).every((b) => b == 0) &&
          bytes[10] == 0xFF &&
          bytes[11] == 0xFF;
      if (isV4Mapped) {
        final v4 = InternetAddress.fromRawAddress(
          Uint8List.fromList(bytes.sublist(12, 16)),
          type: InternetAddressType.IPv4,
        );
        return isRestrictedIp(v4);
      }
    }

    return false;
  }

  static Future<SandboxExecutionResult> _executeInIsolate({
    required String? torrentUrl,
    required String? infoHash,
    required bool strictVideoOnly,
    required bool blockArchives,
    required Set<String> allowedLocalHosts,
    required String sandboxMode,
  }) async {
    final candidates = <String>[];
    if (torrentUrl != null && torrentUrl.trim().isNotEmpty) {
      candidates.add(torrentUrl.trim());
    }
    final cleanHash = (infoHash ?? '').trim().toUpperCase();
    if (RegExp(r'^[0-9A-F]{40}$').hasMatch(cleanHash)) {
      candidates.add('https://itorrents.org/torrent/$cleanHash.torrent');
      candidates.add('https://torcache.net/torrent/$cleanHash.torrent');
    }

    if (candidates.isEmpty) {
      return SandboxExecutionResult(
        report: SafetyReport(
          status: SafetyStatus.blocked,
          safeToDownload: false,
          blockedReasons: ['Aucune URL .torrent ni info_hash valide fourni.'],
          sandboxMode: sandboxMode,
        ),
      );
    }

    Uint8List? downloaded;
    String? lastError;

    for (final url in candidates) {
      final (bytes, err) = await _downloadSafe(url, allowedLocalHosts);
      if (bytes != null) {
        downloaded = bytes;
        break;
      }
      lastError = err;
    }

    if (downloaded == null) {
      return SandboxExecutionResult(
        report: SafetyReport(
          status: SafetyStatus.unverified,
          safeToDownload: false,
          blockedReasons: [
            lastError ?? 'Impossible de récupérer le fichier .torrent dans le bac à sable.',
          ],
          sandboxMode: sandboxMode,
        ),
      );
    }

    return TorrentSanitizer.inspectAndSanitize(
      downloaded,
      strictVideoOnly: strictVideoOnly,
      blockArchives: blockArchives,
      sandboxMode: sandboxMode,
    );
  }

  static Future<(Uint8List?, String?)> _downloadSafe(
    String startUrl,
    Set<String> allowedLocalHosts,
  ) async {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    var currentUrl = startUrl;

    try {
      for (var hop = 0; hop <= maxRedirects; hop++) {
        final (ok, reason) = await isUrlSafeToFetch(
          currentUrl,
          allowedLocalHosts: allowedLocalHosts,
        );
        if (!ok) return (null, reason);

        final uri = Uri.parse(currentUrl);
        final request = await client.getUrl(uri).timeout(connectTimeout);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, userAgent);
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/x-bittorrent, application/octet-stream;q=0.9, */*;q=0.1',
        );

        final response = await request.close().timeout(totalTimeout);

        if (response.statusCode >= 300 &&
            response.statusCode < 400 &&
            response.headers.value(HttpHeaders.locationHeader) != null) {
          await response.drain<void>();
          final loc = response.headers.value(HttpHeaders.locationHeader)!;
          currentUrl = uri.resolve(loc).toString();
          continue;
        }

        if (response.statusCode != 200) {
          await response.drain<void>();
          return (null, 'Serveur distant a répondu HTTP ${response.statusCode}');
        }

        final contentType = (response.headers.contentType?.mimeType ?? '').toLowerCase();
        if (contentType.contains('text/html') || contentType.contains('xhtml')) {
          await response.drain<void>();
          return (
            null,
            'Le serveur a renvoyé une page HTML au lieu d\'un fichier .torrent (bloqué).',
          );
        }

        final builder = BytesBuilder(copy: false);
        var total = 0;
        await for (final chunk in response.timeout(totalTimeout)) {
          total += chunk.length;
          if (total > Bencode.maxPayloadBytes) {
            return (null, 'Fichier trop volumineux (> 2 Mo) pour un .torrent — bloqué.');
          }
          builder.add(chunk);
        }
        return (builder.toBytes(), null);
      }
      return (null, 'Trop de redirections HTTP');
    } on TimeoutException {
      return (null, 'Délai d\'attente dépassé lors de la récupération du .torrent');
    } catch (e) {
      return (null, 'Erreur réseau : $e');
    } finally {
      client.close(force: true);
    }
  }
}
