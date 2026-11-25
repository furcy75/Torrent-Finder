import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/models/seedr_models.dart';
import 'package:safetorrent/models/watchlist_item.dart';

/// 100% on-device local persistence (Android, Windows, Linux — zero server/cloud).
///
/// Stores user settings, the "Plus tard" watchlist, and optional Seedr OAuth tokens
/// (never stores passwords).
class LocalStorageService {
  LocalStorageService({Directory? overrideDirectory})
      : _overrideDirectory = overrideDirectory;

  final Directory? _overrideDirectory;

  AppSettings settings = const AppSettings();
  List<WatchlistItem> watchlist = [];
  SeedrSession? seedrSession;
  bool isLoaded = false;

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
      if (decoded['seedrSession'] is Map<String, dynamic>) {
        final s = SeedrSession.fromJson(decoded['seedrSession'] as Map<String, dynamic>);
        seedrSession = s.isValid ? s : null;
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
      'seedrSession': seedrSession?.toJson(),
    };
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(payload));
    await tmp.rename(file.path);
  }

  Future<void> updateSettings(AppSettings updated) async {
    settings = updated;
    await _save();
  }

  Future<void> setSeedrSession(SeedrSession? session) async {
    seedrSession = (session != null && session.isValid) ? session : null;
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
