import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:safetorrent/models/torbox_models.dart';
import 'package:safetorrent/services/local_storage.dart';

class TorboxApiException implements Exception {
  TorboxApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Official TorBox API v1 client (`https://api.torbox.app/v1/api`).
///
/// Supports named user/family profiles (each using its own official TorBox API key),
/// reading official subscription plan / Premium status and cooldown timestamps from
/// `/user/me`, live torrent list management, instant cache checks, magnet & sanitized
/// `.torrent` uploads, and direct HTTPS CDN download links.
class TorboxService {
  TorboxService({required this.storage});

  final LocalStorageService storage;

  static const String _baseHost = 'api.torbox.app';
  static const Duration _timeout = Duration(seconds: 15);

  TorboxProfile? get activeProfile => storage.activeTorboxProfile;
  bool get hasProfile => activeProfile != null;

  Map<String, String> _authHeaders(String apiKey) => {
        'Authorization': 'Bearer ${apiKey.trim()}',
        'User-Agent': 'SafeTorrent/1.6 (Standalone)',
      };

  /// Sync official user info (`/user/me`) including plan, Premium status, and cooldown_until.
  Future<TorboxProfile> syncProfile(TorboxProfile profile) async {
    final uri = Uri.https(_baseHost, '/v1/api/user/me', {'settings': 'false'});
    final resp = await http.get(uri, headers: _authHeaders(profile.apiKey)).timeout(_timeout);
    final envelope = _parseEnvelope(resp);
    final data = envelope['data'] as Map<String, dynamic>? ?? const {};

    final plan = (data['plan'] as num?)?.toInt() ?? 0;
    final isSubscribed = data['is_subscribed'] == true || plan > 0;
    final cooldownRaw = data['cooldown_until']?.toString();
    final parsedCooldown =
        (cooldownRaw != null && cooldownRaw.isNotEmpty) ? DateTime.tryParse(cooldownRaw) : null;

    final updated = profile.copyWith(
      email: data['email']?.toString() ?? profile.email,
      plan: plan,
      isSubscribed: isSubscribed,
      cooldownUntil: isSubscribed ? null : parsedCooldown,
      clearCooldown: isSubscribed || parsedCooldown == null,
      totalDownloaded: (data['total_downloaded'] as num?)?.toInt() ?? profile.totalDownloaded,
      lastSyncedAt: DateTime.now().toUtc(),
    );

    await storage.addOrUpdateTorboxProfile(updated, makeActive: false);
    return updated;
  }

  /// Validate a new API key and save it as a named profile.
  Future<TorboxProfile> addProfile({
    required String label,
    required String apiKey,
    bool makeActive = true,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      throw TorboxApiException('Veuillez saisir une clé API TorBox valide.');
    }
    final draft = TorboxProfile(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      label: label.trim().isNotEmpty ? label.trim() : 'Mon compte TorBox',
      apiKey: cleanKey,
    );
    // Validate key immediately against /user/me
    final uri = Uri.https(_baseHost, '/v1/api/user/me');
    final resp = await http.get(uri, headers: _authHeaders(cleanKey)).timeout(_timeout);
    final envelope = _parseEnvelope(resp);
    final data = envelope['data'] as Map<String, dynamic>? ?? const {};

    final plan = (data['plan'] as num?)?.toInt() ?? 0;
    final isSubscribed = data['is_subscribed'] == true || plan > 0;
    final cooldownRaw = data['cooldown_until']?.toString();
    final parsedCooldown =
        (cooldownRaw != null && cooldownRaw.isNotEmpty) ? DateTime.tryParse(cooldownRaw) : null;

    final validated = draft.copyWith(
      email: data['email']?.toString(),
      plan: plan,
      isSubscribed: isSubscribed,
      cooldownUntil: isSubscribed ? null : parsedCooldown,
      clearCooldown: isSubscribed || parsedCooldown == null,
      totalDownloaded: (data['total_downloaded'] as num?)?.toInt() ?? 0,
      lastSyncedAt: DateTime.now().toUtc(),
    );

    await storage.addOrUpdateTorboxProfile(validated, makeActive: makeActive);
    return validated;
  }

  /// List active & completed torrents for the given profile (`/torrents/mylist`).
  Future<List<TorboxTorrentItem>> listTorrents(TorboxProfile profile) async {
    final uri = Uri.https(_baseHost, '/v1/api/torrents/mylist', {'bypass_cache': 'true'});
    final resp = await http.get(uri, headers: _authHeaders(profile.apiKey)).timeout(_timeout);
    final envelope = _parseEnvelope(resp);
    final rawList = envelope['data'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(TorboxTorrentItem.fromJson)
        .toList();
  }

  /// Check if a hash is already cached on TorBox (`/torrents/checkcached`).
  Future<bool> isHashCached(TorboxProfile profile, String infoHash) async {
    final cleanHash = infoHash.trim().toLowerCase();
    if (cleanHash.length != 40) return false;
    try {
      final uri = Uri.https(_baseHost, '/v1/api/torrents/checkcached', {
        'hash': cleanHash,
        'format': 'object',
      });
      final resp = await http.get(uri, headers: _authHeaders(profile.apiKey)).timeout(_timeout);
      if (resp.statusCode != 200) return false;
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic> && decoded['data'] is Map) {
        final map = decoded['data'] as Map;
        return map.containsKey(cleanHash) && map[cleanHash] != null;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Send a Magnet link to the selected TorBox profile (`/torrents/createtorrent`).
  Future<String> addMagnet(TorboxProfile profile, String magnet) async {
    final uri = Uri.https(_baseHost, '/v1/api/torrents/createtorrent');
    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders(profile.apiKey))
      ..fields['magnet'] = magnet.trim();

    final streamed = await req.send().timeout(_timeout);
    final resp = await http.Response.fromStream(streamed);
    final envelope = _parseEnvelope(resp);

    // Refresh official cooldown/stats right after creation on free accounts
    if (!profile.isPremium) {
      syncProfile(profile).catchError((_) => profile);
    }

    return envelope['detail']?.toString() ?? 'Torrent ajouté sur TorBox (${profile.label}) !';
  }

  /// Upload sanitized `.torrent` bytes from SafeTorrent's Sandbox to TorBox.
  Future<String> addTorrentBytes(
    TorboxProfile profile,
    Uint8List bytes,
    String fileName,
  ) async {
    final uri = Uri.https(_baseHost, '/v1/api/torrents/createtorrent');
    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders(profile.apiKey))
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName.endsWith('.torrent') ? fileName : '$fileName.torrent',
        ),
      );

    final streamed = await req.send().timeout(_timeout);
    final resp = await http.Response.fromStream(streamed);
    final envelope = _parseEnvelope(resp);

    if (!profile.isPremium) {
      syncProfile(profile).catchError((_) => profile);
    }

    return envelope['detail']?.toString() ??
        'Fichier .torrent vérifié envoyé sur TorBox (${profile.label}) !';
  }

  /// Request a direct HTTPS download link for a specific file or full torrent ZIP (`/torrents/requestdl`).
  Future<String> requestDownloadUrl(
    TorboxProfile profile,
    int torrentId, {
    int? fileId,
    bool zipLink = false,
  }) async {
    final params = <String, String>{
      'token': profile.apiKey.trim(),
      'torrent_id': '$torrentId',
      if (fileId != null) 'file_id': '$fileId',
      'zip_link': zipLink ? 'true' : 'false',
    };
    final uri = Uri.https(_baseHost, '/v1/api/torrents/requestdl', params);
    final resp = await http.get(uri, headers: _authHeaders(profile.apiKey)).timeout(_timeout);
    final envelope = _parseEnvelope(resp);
    final url = envelope['data']?.toString();
    if (url == null || url.isEmpty || !url.startsWith('http')) {
      throw TorboxApiException('Lien de téléchargement TorBox indisponible.');
    }
    return url;
  }

  /// Control a torrent (`delete`, `pause`, `resume`) via `/torrents/controltorrent`.
  Future<void> controlTorrent(
    TorboxProfile profile,
    int torrentId,
    String operation,
  ) async {
    final uri = Uri.https(_baseHost, '/v1/api/torrents/controltorrent');
    final resp = await http
        .post(
          uri,
          headers: {
            ..._authHeaders(profile.apiKey),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'torrent_id': torrentId,
            'operation': operation,
          }),
        )
        .timeout(_timeout);
    _parseEnvelope(resp);
  }

  Map<String, dynamic> _parseEnvelope(http.Response resp) {
    Map<String, dynamic> decoded = const {};
    try {
      final raw = jsonDecode(resp.body);
      if (raw is Map<String, dynamic>) decoded = raw;
    } catch (_) {
      // ignore
    }

    final success = decoded['success'];
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw TorboxApiException('Clé API TorBox invalide ou refusée (HTTP ${resp.statusCode}).');
    }
    if (resp.statusCode >= 400 || success == false) {
      final detail = decoded['detail']?.toString();
      final err = decoded['error']?.toString();
      throw TorboxApiException(
        detail ?? err ?? 'Erreur TorBox HTTP ${resp.statusCode}',
      );
    }
    return decoded;
  }
}
