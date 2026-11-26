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

/// Complete Seedr.cc API client supporting one or more Seedr accounts via
/// Email + Password OAuth (`oauth_test/token.php`, auto-refreshable via
/// `refresh_token`, password NEVER persisted on disk).
class SeedrService {
  SeedrService({required this.storage});

  final LocalStorageService storage;

  static const Duration _timeout = Duration(seconds: 15);
  static const String _passwordClientId = 'seedr_chrome';
  static const Map<String, String> _headers = {
    'User-Agent': 'TorrentSeeder/2.0 (Standalone)',
  };

  List<SeedrSession> get accounts => storage.seedrAccounts;
  SeedrSession? get activeAccount => storage.activeSeedrAccount;
  bool get isConnected => accounts.isNotEmpty;

  /// Builds the exact Seedr RPC URI with `access_token` and `func` in the
  /// URL query parameters (required by `resource.php` to avoid HTTP 404).
  static Uri buildResourceUri({
    required String accessToken,
    required String func,
  }) {
    return Uri.https('www.seedr.cc', '/oauth_test/resource.php', {
      'access_token': accessToken,
      'func': func,
    });
  }

  // -------------------------------------------------------------------
  // Email + Password OAuth (Password never written to disk)
  // -------------------------------------------------------------------
  Future<SeedrSession> loginWithPassword({
    required String email,
    required String password,
    String label = '',
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
      final errDesc = data['error_description']?.toString() ??
          data['error']?.toString() ??
          'Invalid credentials';
      throw SeedrApiException('Seedr: $errDesc');
    }

    final cleanLabel = label.trim().isNotEmpty
        ? label.trim()
        : (email.trim().contains('@') ? email.trim().split('@').first : email.trim());
    var newSession = SeedrSession(
      id: 'seedr_${DateTime.now().microsecondsSinceEpoch}',
      label: cleanLabel,
      accessToken: token,
      refreshToken: data['refresh_token']?.toString(),
      email: email.trim(),
    );
    newSession = await _enrichAccountProfile(
      newSession,
      customLabelProvided: label.trim().isNotEmpty,
    );
    await storage.addOrUpdateSeedrAccount(newSession, makeActive: true);
    return newSession;
  }

  Future<SeedrSession?> _tryRefreshAccount(SeedrSession account) async {
    if ((account.refreshToken ?? '').isEmpty) return null;
    try {
      final uri = Uri.https('www.seedr.cc', '/oauth_test/token.php');
      final resp = await http
          .post(
            uri,
            headers: _headers,
            body: {
              'grant_type': 'refresh_token',
              'client_id': _passwordClientId,
              'refresh_token': account.refreshToken!,
            },
          )
          .timeout(_timeout);
      final data = _safeJsonMap(resp.body);
      final newToken = data['access_token']?.toString();
      if (resp.statusCode == 200 && newToken != null && newToken.isNotEmpty) {
        final updated = account.copyWith(
          accessToken: newToken,
          refreshToken: data['refresh_token']?.toString() ?? account.refreshToken,
        );
        await storage.addOrUpdateSeedrAccount(updated, makeActive: false);
        return updated;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<void> disconnectAccount(String accountId) async {
    await storage.deleteSeedrAccount(accountId);
  }

  Future<SeedrSession> _enrichAccountProfile(
    SeedrSession s, {
    required bool customLabelProvided,
  }) async {
    var enriched = s;
    try {
      final uri = buildResourceUri(accessToken: s.accessToken, func: 'get_settings');
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode == 200) {
        final data = _safeJsonMap(resp.body);
        final acct = data['account'] as Map<String, dynamic>? ?? const {};
        final uname = acct['username']?.toString();
        final mail = acct['email']?.toString();
        enriched = enriched.copyWith(
          label: (!customLabelProvided && uname != null && uname.trim().isNotEmpty)
              ? uname.trim()
              : enriched.label,
          username: uname ?? enriched.username,
          email: mail ?? enriched.email,
          packageName: acct['package_name']?.toString() ?? enriched.packageName,
        );
      }
    } catch (_) {
      // ignore
    }

    try {
      final memUri = buildResourceUri(accessToken: enriched.accessToken, func: 'get_memory_bandwidth');
      final resp = await http.get(memUri, headers: _headers).timeout(_timeout);
      if (resp.statusCode == 200) {
        final data = _safeJsonMap(resp.body);
        final used = (data['space_used'] as num?)?.toInt();
        final max = (data['space_max'] as num?)?.toInt();
        if (used != null && max != null && max > 0) {
          enriched = enriched.copyWith(lastSpaceUsed: used, lastSpaceMax: max);
        }
      }
    } catch (_) {
      // ignore
    }
    return enriched;
  }

  // -------------------------------------------------------------------
  // Quota & Active Transfer Checking Across All Accounts (Manual Picker)
  // -------------------------------------------------------------------
  Future<SeedrAccountQuota> fetchAccountQuota(SeedrSession account) async {
    try {
      return await _withAutoRefresh(account, (token, current) async {
        final folderUri = buildResourceUri(accessToken: token, func: 'list_contents');
        final folderResp = await http
            .post(
              folderUri,
              headers: _headers,
              body: {'content_type': 'folder', 'content_id': '0'},
            )
            .timeout(_timeout);
        final folderData = _checkAuthAndParse(folderResp);
        final contents = SeedrFolderContents.fromJson(folderData);

        var used = contents.spaceMax > 0 ? contents.spaceUsed : null;
        var max = contents.spaceMax > 0 ? contents.spaceMax : null;

        if (used == null || max == null) {
          final memUri = buildResourceUri(accessToken: token, func: 'get_memory_bandwidth');
          final memResp = await http.get(memUri, headers: _headers).timeout(_timeout);
          final memData = _checkAuthAndParse(memResp);
          used = (memData['space_used'] as num?)?.toInt();
          max = (memData['space_max'] as num?)?.toInt();
        }

        var updatedAcc = current;
        if (used != null && max != null && max > 0) {
          updatedAcc = current.copyWith(lastSpaceUsed: used, lastSpaceMax: max);
          await storage.addOrUpdateSeedrAccount(updatedAcc, makeActive: false);
        }

        return SeedrAccountQuota(
          account: updatedAcc,
          spaceUsed: used ?? updatedAcc.lastSpaceUsed,
          spaceMax: max ?? updatedAcc.lastSpaceMax,
          activeDownloadsCount: contents.torrents.length,
        );
      });
    } catch (e) {
      return SeedrAccountQuota(
        account: account,
        spaceUsed: account.lastSpaceUsed,
        spaceMax: account.lastSpaceMax,
        error: e.toString(),
      );
    }
  }

  Future<List<SeedrAccountQuota>> fetchAllAccountsQuota() async {
    final list = List<SeedrSession>.from(storage.seedrAccounts);
    if (list.isEmpty) return const [];
    return Future.wait(list.map(fetchAccountQuota));
  }

  // -------------------------------------------------------------------
  // Live Account & Storage Management
  // -------------------------------------------------------------------
  Future<SeedrFolderContents> listContents({
    SeedrSession? account,
    String? folderId,
  }) async {
    final target = _requireAccount(account);
    return _withAutoRefresh(target, (token, current) async {
      final uri = buildResourceUri(accessToken: token, func: 'list_contents');
      final resp = await http
          .post(
            uri,
            headers: _headers,
            body: {
              'content_type': 'folder',
              'content_id': (folderId == null || folderId.isEmpty) ? '0' : folderId,
            },
          )
          .timeout(_timeout);
      final data = _checkAuthAndParse(resp);
      final contents = SeedrFolderContents.fromJson(data);
      if (contents.spaceMax > 0) {
        final updated = current.copyWith(
          lastSpaceUsed: contents.spaceUsed,
          lastSpaceMax: contents.spaceMax,
        );
        await storage.addOrUpdateSeedrAccount(updated, makeActive: false);
      }
      return contents;
    });
  }

  Future<String> addMagnet(
    String magnetLink, {
    SeedrSession? account,
    String folderId = '0',
  }) async {
    final target = _requireAccount(account);
    return _withAutoRefresh(target, (token, _) async {
      final uri = buildResourceUri(accessToken: token, func: 'add_torrent');
      final resp = await http
          .post(
            uri,
            headers: _headers,
            body: {
              'torrent_magnet': magnetLink.trim(),
              'folder_id': folderId,
            },
          )
          .timeout(_timeout);
      final data = _checkAuthAndParse(resp);
      final result = data['result'];
      if (result == true || result == 'true' || data['user_torrent_id'] != null) {
        return data['title']?.toString() ?? 'OK';
      }
      final err = data['error']?.toString() ?? data['result']?.toString() ?? 'Seedr error';
      throw SeedrApiException(_translateSeedrError(err));
    });
  }

  /// Upload a sanitized `.torrent` file straight from the Sandbox to Seedr.
  Future<String> addTorrentBytes(
    Uint8List torrentBytes,
    String fileName, {
    SeedrSession? account,
    String folderId = '0',
  }) async {
    final target = _requireAccount(account);
    return _withAutoRefresh(target, (token, _) async {
      final uri = buildResourceUri(accessToken: token, func: 'add_torrent');
      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers)
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
        return data['title']?.toString() ?? 'OK';
      }
      final err = data['error']?.toString() ?? data['result']?.toString() ?? 'Seedr error';
      throw SeedrApiException(_translateSeedrError(err));
    });
  }

  Future<String> fetchFileDownloadUrl(
    String folderFileId, {
    SeedrSession? account,
  }) async {
    final target = _requireAccount(account);
    return _withAutoRefresh(target, (token, _) async {
      final uri = buildResourceUri(accessToken: token, func: 'fetch_file');
      final resp = await http
          .post(
            uri,
            headers: _headers,
            body: {'folder_file_id': folderFileId},
          )
          .timeout(_timeout);
      final data = _checkAuthAndParse(resp);
      final url = data['url']?.toString();
      if (url == null || url.isEmpty) {
        throw SeedrApiException('Unable to retrieve Seedr download link.');
      }
      return url;
    });
  }

  Future<String> createFolderZipUrl(
    String folderId, {
    SeedrSession? account,
  }) async {
    final target = _requireAccount(account);
    return _withAutoRefresh(target, (token, _) async {
      final uri = buildResourceUri(accessToken: token, func: 'create_empty_archive');
      final archiveArr = jsonEncode([
        {'type': 'folder', 'id': int.tryParse(folderId) ?? folderId},
      ]);
      final resp = await http
          .post(
            uri,
            headers: _headers,
            body: {'archive_arr': archiveArr},
          )
          .timeout(_timeout);
      final data = _checkAuthAndParse(resp);
      final url = data['archive_url']?.toString() ?? data['url']?.toString();
      if (url == null || url.isEmpty) {
        throw SeedrApiException('Unable to create Seedr ZIP archive.');
      }
      return url;
    });
  }

  Future<void> deleteItem({
    required String type,
    required String id,
    SeedrSession? account,
  }) async {
    final target = _requireAccount(account);
    await _withAutoRefresh(target, (token, _) async {
      final uri = buildResourceUri(accessToken: token, func: 'delete');
      final deleteArr = jsonEncode([
        {'type': type, 'id': int.tryParse(id) ?? id},
      ]);
      final resp = await http
          .post(
            uri,
            headers: _headers,
            body: {'delete_arr': deleteArr},
          )
          .timeout(_timeout);
      _checkAuthAndParse(resp);
    });
  }

  // -------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------
  SeedrSession _requireAccount(SeedrSession? account) {
    final resolved = account ?? storage.activeSeedrAccount;
    if (resolved == null || !resolved.isValid) {
      throw SeedrApiException(
        'No Seedr account connected.',
        authExpired: true,
      );
    }
    return storage.seedrAccountById(resolved.id) ?? resolved;
  }

  Future<T> _withAutoRefresh<T>(
    SeedrSession account,
    Future<T> Function(String token, SeedrSession current) action,
  ) async {
    final current = storage.seedrAccountById(account.id) ?? account;
    try {
      return await action(current.accessToken, current);
    } on SeedrApiException catch (e) {
      if (e.authExpired) {
        final refreshed = await _tryRefreshAccount(current);
        if (refreshed != null) {
          return action(refreshed.accessToken, refreshed);
        }
      }
      rethrow;
    }
  }

  Map<String, dynamic> _checkAuthAndParse(http.Response resp) {
    final data = _safeJsonMap(resp.body);
    final err = data['error']?.toString().toLowerCase() ?? '';
    if (resp.statusCode == 401 ||
        err.contains('expired_token') ||
        err.contains('invalid_token') ||
        err.contains('access_denied')) {
      throw SeedrApiException(
        'Seedr session expired — please sign in again.',
        authExpired: true,
      );
    }
    if (resp.statusCode >= 400) {
      throw SeedrApiException(
        data['error_description']?.toString() ??
            data['error']?.toString() ??
            'Seedr HTTP ${resp.statusCode}',
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
      return 'Seedr: not_enough_space';
    }
    if (low.contains('queue_full')) {
      return 'Seedr: queue_full';
    }
    return 'Seedr: $raw';
  }
}
