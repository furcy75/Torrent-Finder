import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:safetorrent/models/seedr_models.dart';
import 'package:safetorrent/services/local_storage.dart';

class SeedrApiException implements Exception {
  SeedrApiException(this.message, {this.authExpired = false});

  final String message;
  final bool authExpired;

  @override
  String toString() => message;
}

/// Complete Seedr.cc API client supporting BOTH authentication flows:
/// 1. Device Code OAuth (`seedr.cc/devices`, long-lived token, zero password stored)
/// 2. Email + Password OAuth (`oauth_test/token.php`, auto-refreshable token, password never saved)
///
/// Supports live account management:
/// - Storage quota, folder browsing, active transfers monitoring
/// - Sending Magnet links OR sanitized `.torrent` bytes directly from SafeTorrent
/// - Direct HTTPS file download links, folder ZIP archive links, HLS stream links
/// - Deleting active transfers, files, and folders
class SeedrService {
  SeedrService({required this.storage});

  final LocalStorageService storage;

  static const Duration _timeout = Duration(seconds: 15);
  static const String _deviceClientId = 'seedr_xbmc';
  static const String _passwordClientId = 'seedr_chrome';
  static const Map<String, String> _headers = {
    'User-Agent': 'SafeTorrent/1.5 (Standalone)',
  };

  SeedrSession? get session => storage.seedrSession;
  bool get isConnected => session != null && session!.isValid;

  // -------------------------------------------------------------------
  // Auth Mode 1: Device Code OAuth (Recommended — no password required)
  // -------------------------------------------------------------------
  Future<SeedrDeviceCode> requestDeviceCode() async {
    final uri = Uri.https('www.seedr.cc', '/api/device/code', {
      'client_id': _deviceClientId,
    });
    final resp = await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw SeedrApiException('Impossible de générer un code appareil Seedr (HTTP ${resp.statusCode}).');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final deviceCode = data['device_code']?.toString() ?? '';
    final userCode = data['user_code']?.toString() ?? '';
    if (deviceCode.isEmpty || userCode.isEmpty) {
      throw SeedrApiException('Réponse Seedr incomplète lors de la demande de code.');
    }
    return SeedrDeviceCode(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUrl: (data['verification_url'] ?? 'https://www.seedr.cc/devices').toString(),
      intervalSeconds: (data['interval'] as num?)?.toInt() ?? 5,
      expiresInSeconds: (data['expires_in'] as num?)?.toInt() ?? 1800,
    );
  }

  /// Poll Seedr once to check if the user authorized `deviceCode` on `seedr.cc/devices`.
  /// Returns `null` while authorization is still pending.
  Future<SeedrSession?> pollDeviceAuthorization(String deviceCode) async {
    final uri = Uri.https('www.seedr.cc', '/api/device/authorize', {
      'device_code': deviceCode,
      'client_id': _deviceClientId,
    });
    final resp = await http.get(uri, headers: _headers).timeout(_timeout);
    final data = _safeJsonMap(resp.body);
    final err = data['error']?.toString();
    if (err == 'authorization_pending' || err == 'slow_down') {
      return null;
    }
    final token = data['access_token']?.toString();
    if (token != null && token.isNotEmpty) {
      var newSession = SeedrSession(
        accessToken: token,
        refreshToken: data['refresh_token']?.toString(),
        authMode: 'device',
      );
      await storage.setSeedrSession(newSession);
      newSession = await _enrichAccountProfile(newSession);
      await storage.setSeedrSession(newSession);
      return newSession;
    }
    if (err != null && err.isNotEmpty) {
      throw SeedrApiException('Autorisation Seedr refusée ou expirée ($err).');
    }
    return null;
  }

  // -------------------------------------------------------------------
  // Auth Mode 2: Email + Password OAuth (Password never written to disk)
  // -------------------------------------------------------------------
  Future<SeedrSession> loginWithPassword({
    required String email,
    required String password,
  }) async {
    final uri = Uri.https('www.seedr.cc', '/oauth_test/token.php');
    final resp = await http
        .post(
          uri,
          headers: _headers,
          body: {
            'grant_type': 'password',
            'client_id': _passwordClientId,
            'type': 'login',
            'username': email.trim(),
            'password': password,
          },
        )
        .timeout(_timeout);

    final data = _safeJsonMap(resp.body);
    final token = data['access_token']?.toString();
    if (resp.statusCode != 200 || token == null || token.isEmpty) {
      final errDesc =
          data['error_description']?.toString() ?? data['error']?.toString() ?? 'Identifiants invalides';
      throw SeedrApiException('Échec connexion Seedr : $errDesc');
    }

    var newSession = SeedrSession(
      accessToken: token,
      refreshToken: data['refresh_token']?.toString(),
      authMode: 'password',
      email: email.trim(),
    );
    await storage.setSeedrSession(newSession);
    newSession = await _enrichAccountProfile(newSession);
    await storage.setSeedrSession(newSession);
    return newSession;
  }

  Future<bool> _tryRefreshToken() async {
    final current = storage.seedrSession;
    if (current == null || (current.refreshToken ?? '').isEmpty) return false;

    final uri = Uri.https('www.seedr.cc', '/oauth_test/token.php');
    try {
      final resp = await http
          .post(
            uri,
            headers: _headers,
            body: {
              'grant_type': 'refresh_token',
              'client_id': current.authMode == 'device' ? _deviceClientId : _passwordClientId,
              'refresh_token': current.refreshToken!,
            },
          )
          .timeout(_timeout);
      final data = _safeJsonMap(resp.body);
      final newToken = data['access_token']?.toString();
      if (resp.statusCode == 200 && newToken != null && newToken.isNotEmpty) {
        await storage.setSeedrSession(
          current.copyWith(
            accessToken: newToken,
            refreshToken: data['refresh_token']?.toString() ?? current.refreshToken,
          ),
        );
        return true;
      }
    } catch (_) {
      // ignore
    }
    return false;
  }

  Future<void> logout() async {
    await storage.setSeedrSession(null);
  }

  Future<SeedrSession> _enrichAccountProfile(SeedrSession s) async {
    try {
      final uri = Uri.https('www.seedr.cc', '/oauth_test/resource.php', {
        'access_token': s.accessToken,
        'func': 'get_settings',
      });
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) return s;
      final data = _safeJsonMap(resp.body);
      final acct = data['account'] as Map<String, dynamic>? ?? const {};
      return s.copyWith(
        username: acct['username']?.toString() ?? s.username,
        email: acct['email']?.toString() ?? s.email,
        packageName: acct['package_name']?.toString() ?? s.packageName,
      );
    } catch (_) {
      return s;
    }
  }

  // -------------------------------------------------------------------
  // Live Account & Storage Management
  // -------------------------------------------------------------------
  Future<SeedrFolderContents> listContents({String? folderId}) async {
    return _withAutoRefresh((token) async {
      final path = (folderId == null || folderId.isEmpty || folderId == '0')
          ? '/api/folder'
          : '/api/folder/$folderId';
      final uri = Uri.https('www.seedr.cc', path, {'access_token': token});
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      final data = _checkAuthAndParse(resp);
      return SeedrFolderContents.fromJson(data);
    });
  }

  Future<String> addMagnet(String magnetLink, {String folderId = '-1'}) async {
    return _withAutoRefresh((token) async {
      final uri = Uri.https('www.seedr.cc', '/oauth_test/resource.php');
      final resp = await http
          .post(
            uri,
            headers: _headers,
            body: {
              'access_token': token,
              'func': 'add_torrent',
              'torrent_magnet': magnetLink.trim(),
              'folder_id': folderId,
            },
          )
          .timeout(_timeout);
      final data = _checkAuthAndParse(resp);
      final result = data['result'];
      if (result == true || result == 'true' || data['user_torrent_id'] != null) {
        return data['title']?.toString() ?? 'Torrent ajouté sur votre compte Seedr !';
      }
      final err = data['error']?.toString() ?? data['result']?.toString() ?? 'Erreur Seedr';
      throw SeedrApiException(_translateSeedrError(err));
    });
  }

  /// Upload a sanitized `.torrent` file straight from SafeTorrent's Sandbox to Seedr!
  Future<String> addTorrentBytes(
    Uint8List torrentBytes,
    String fileName, {
    String folderId = '-1',
  }) async {
    return _withAutoRefresh((token) async {
      final uri = Uri.https('www.seedr.cc', '/oauth_test/resource.php');
      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers)
        ..fields['access_token'] = token
        ..fields['func'] = 'add_torrent'
        ..fields['folder_id'] = folderId
        ..files.add(
          http.MultipartFile.fromBytes(
            'torrent_file',
            torrentBytes,
            filename: fileName.endsWith('.torrent') ? fileName : '$fileName.torrent',
          ),
        );

      final streamed = await req.send().timeout(_timeout);
      final resp = await http.Response.fromStream(streamed);
      final data = _checkAuthAndParse(resp);
      final result = data['result'];
      if (result == true || result == 'true' || data['user_torrent_id'] != null) {
        return data['title']?.toString() ?? 'Fichier .torrent vérifié envoyé sur Seedr !';
      }
      final err = data['error']?.toString() ?? data['result']?.toString() ?? 'Erreur Seedr';
      throw SeedrApiException(_translateSeedrError(err));
    });
  }

  /// Fetch direct HTTPS CDN download URL for a file stored in Seedr.
  Future<String> fetchFileDownloadUrl(String folderFileId) async {
    return _withAutoRefresh((token) async {
      final uri = Uri.https('www.seedr.cc', '/oauth_test/resource.php');
      final resp = await http
          .post(
            uri,
            headers: _headers,
            body: {
              'access_token': token,
              'func': 'fetch_file',
              'folder_file_id': folderFileId,
            },
          )
          .timeout(_timeout);
      final data = _checkAuthAndParse(resp);
      final url = data['url']?.toString();
      if (url == null || url.isEmpty) {
        throw SeedrApiException('Impossible de récupérer le lien de téléchargement Seedr.');
      }
      return url;
    });
  }

  /// Create a ZIP download link for a full folder in Seedr.
  Future<String> createFolderZipUrl(String folderId) async {
    return _withAutoRefresh((token) async {
      final uri = Uri.https('www.seedr.cc', '/oauth_test/resource.php');
      final archiveArr = jsonEncode([
        {'type': 'folder', 'id': int.tryParse(folderId) ?? folderId},
      ]);
      final resp = await http
          .post(
            uri,
            headers: _headers,
            body: {
              'access_token': token,
              'func': 'create_empty_archive',
              'archive_arr': archiveArr,
            },
          )
          .timeout(_timeout);
      final data = _checkAuthAndParse(resp);
      final url = data['archive_url']?.toString() ?? data['url']?.toString();
      if (url == null || url.isEmpty) {
        throw SeedrApiException('Impossible de générer l\'archive ZIP Seedr.');
      }
      return url;
    });
  }

  /// Delete a file (`file`), folder (`folder`), or active transfer (`torrent`) from Seedr.
  Future<void> deleteItem({required String type, required String id}) async {
    await _withAutoRefresh((token) async {
      final uri = Uri.https('www.seedr.cc', '/oauth_test/resource.php');
      final deleteArr = jsonEncode([
        {'type': type, 'id': id},
      ]);
      final resp = await http
          .post(
            uri,
            headers: _headers,
            body: {
              'access_token': token,
              'func': 'delete',
              'delete_arr': deleteArr,
            },
          )
          .timeout(_timeout);
      _checkAuthAndParse(resp);
    });
  }

  // -------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------
  Future<T> _withAutoRefresh<T>(Future<T> Function(String token) action) async {
    final current = storage.seedrSession;
    if (current == null || !current.isValid) {
      throw SeedrApiException(
        'Aucun compte Seedr connecté. Ouvrez l\'onglet Seedr pour vous connecter.',
        authExpired: true,
      );
    }
    try {
      return await action(current.accessToken);
    } on SeedrApiException catch (e) {
      if (e.authExpired && await _tryRefreshToken()) {
        final updated = storage.seedrSession!;
        return action(updated.accessToken);
      }
      rethrow;
    }
  }

  Map<String, dynamic> _checkAuthAndParse(http.Response resp) {
    final data = _safeJsonMap(resp.body);
    final err = data['error']?.toString().toLowerCase() ?? '';
    if (resp.statusCode == 401 ||
        err.contains('expired_token') ||
        err.contains('invalid_token')) {
      throw SeedrApiException(
        'Session Seedr expirée — reconnectez-vous dans l\'onglet Seedr.',
        authExpired: true,
      );
    }
    if (resp.statusCode >= 400) {
      throw SeedrApiException(
        data['error_description']?.toString() ??
            data['error']?.toString() ??
            'Erreur Seedr HTTP ${resp.statusCode}',
      );
    }
    return data;
  }

  static Map<String, dynamic> _safeJsonMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // ignore
    }
    return const {};
  }

  static String _translateSeedrError(String raw) {
    final low = raw.toLowerCase();
    if (low.contains('not_enough_space')) {
      return 'Espace insuffisant sur votre compte Seedr — supprimez des fichiers dans l\'onglet Seedr.';
    }
    if (low.contains('queue_full')) {
      return 'File d\'attente Seedr pleine — attendez la fin d\'un transfert en cours.';
    }
    if (low.contains('parsing_error') || low.contains('invalid')) {
      return 'Lien Magnet ou fichier .torrent refusé par Seedr ($raw).';
    }
    return 'Seedr : $raw';
  }
}
