import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/models/seedr_models.dart';
import 'package:safetorrent/models/watchlist_item.dart';

/// 100% on-device local persistence (Android, Windows, Linux — zero server/cloud).
///
/// Stores user settings, the "Plus tard" watchlist, and optional named Seedr
/// accounts (OAuth tokens only — passwords are NEVER saved).
class LocalStorageService {
  LocalStorageService({Directory? overrideDirectory})
      : _overrideDirectory = overrideDirectory;

  final Directory? _overrideDirectory;

  AppSettings settings = const AppSettings();
  List<WatchlistItem> watchlist = [];
  List<SeedrSession> seedrAccounts = [];
  String? activeSeedrAccountId;
  bool isLoaded = false;

  SeedrSession? get activeSeedrAccount {
    if (seedrAccounts.isEmpty) return null;
    if (activeSeedrAccountId != null) {
      for (final acc in seedrAccounts) {
        if (acc.id == activeSeedrAccountId) return acc;
      }
    }
    return seedrAccounts.first;
  }

  /// Legacy single-session getter mapped to [activeSeedrAccount].
  SeedrSession? get seedrSession => activeSeedrAccount;

  SeedrSession? seedrAccountById(String id) {
    for (final acc in seedrAccounts) {
      if (acc.id == id) return acc;
    }
    return null;
  }

  Future<File> _storageFile() async {
    final dir = _overrideDirectory ?? await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}safetorrent_data.json');
  }

  Future<void> load() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) return;
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return;

      if (decoded['settings'] is Map<String, dynamic>) {
        settings = AppSettings.fromJson(decoded['settings'] as Map<String, dynamic>);
      }
      if (decoded['watchlist'] is List) {
        watchlist = (decoded['watchlist'] as List)
            .whereType<Map<String, dynamic>>()
            .map(WatchlistItem.fromJson)
            .toList();
      }

      if (decoded['seedrAccounts'] is List) {
        seedrAccounts = (decoded['seedrAccounts'] as List)
            .whereType<Map<String, dynamic>>()
            .map(SeedrSession.fromJson)
            .where((a) => a.isValid)
            .toList();
      }
      // Automatic migration from v1.5 single `seedrSession`
      if (seedrAccounts.isEmpty && decoded['seedrSession'] is Map<String, dynamic>) {
        final legacy = SeedrSession.fromJson(decoded['seedrSession'] as Map<String, dynamic>);
        if (legacy.isValid) {
          seedrAccounts = [legacy];
        }
      }
      activeSeedrAccountId = decoded['activeSeedrAccountId'] as String?;
      if (seedrAccounts.isNotEmpty &&
          !seedrAccounts.any((a) => a.id == activeSeedrAccountId)) {
        activeSeedrAccountId = seedrAccounts.first.id;
      }
    } catch (_) {
      // Fall back cleanly to defaults if file is empty or unreadable
    } finally {
      isLoaded = true;
    }
  }

  Future<void> _save() async {
    final file = await _storageFile();
    final payload = {
      'settings': settings.toJson(),
      'watchlist': watchlist.map((e) => e.toJson()).toList(),
      'seedrAccounts': seedrAccounts.map((e) => e.toJson()).toList(),
      'activeSeedrAccountId': activeSeedrAccountId,
    };
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(payload));
    await tmp.rename(file.path);
  }

  Future<void> updateSettings(AppSettings updated) async {
    settings = updated;
    await _save();
  }

  Future<void> addOrUpdateSeedrAccount(
    SeedrSession account, {
    bool makeActive = true,
  }) async {
    if (!account.isValid) return;
    final idx = seedrAccounts.indexWhere((a) => a.id == account.id);
    if (idx == -1) {
      seedrAccounts.add(account);
    } else {
      seedrAccounts[idx] = account;
    }
    if (makeActive || activeSeedrAccountId == null) {
      activeSeedrAccountId = account.id;
    }
    await _save();
  }

  Future<void> setActiveSeedrAccount(String accountId) async {
    if (seedrAccounts.any((a) => a.id == accountId)) {
      activeSeedrAccountId = accountId;
      await _save();
    }
  }

  Future<void> renameSeedrAccount(String accountId, String newLabel) async {
    final trimmed = newLabel.trim();
    if (trimmed.isEmpty) return;
    final idx = seedrAccounts.indexWhere((a) => a.id == accountId);
    if (idx != -1) {
      seedrAccounts[idx] = seedrAccounts[idx].copyWith(label: trimmed);
      await _save();
    }
  }

  Future<void> deleteSeedrAccount(String accountId) async {
    seedrAccounts.removeWhere((a) => a.id == accountId);
    if (activeSeedrAccountId == accountId) {
      activeSeedrAccountId = seedrAccounts.isNotEmpty ? seedrAccounts.first.id : null;
    }
    await _save();
  }

  Future<bool> addToWatchlist(WatchlistItem item) async {
    final exists = watchlist.any(
      (e) => e.titleFr.toLowerCase() == item.titleFr.toLowerCase(),
    );
    if (exists) return false;
    watchlist.insert(0, item);
    await _save();
    return true;
  }

  Future<void> updateWatchlistItem(WatchlistItem updated) async {
    final idx = watchlist.indexWhere((e) => e.id == updated.id);
    if (idx != -1) {
      watchlist[idx] = updated;
      await _save();
    }
  }

  Future<void> deleteWatchlistItem(String id) async {
    watchlist.removeWhere((e) => e.id == id);
    await _save();
  }
}
