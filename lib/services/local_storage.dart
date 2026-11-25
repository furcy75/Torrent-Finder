import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/models/history_item.dart';
import 'package:safetorrent/models/watchlist_item.dart';

/// 100% on-device local persistence (Android, Windows, Linux — zero server/cloud).
///
/// Stores settings, opt-in search history, and the "À rechercher plus tard" watchlist
/// in a single private JSON file inside the OS application support directory.
class LocalStorageService {
  LocalStorageService({Directory? overrideDirectory})
      : _overrideDirectory = overrideDirectory;

  final Directory? _overrideDirectory;

  AppSettings settings = const AppSettings();
  List<HistoryItem> history = [];
  List<WatchlistItem> watchlist = [];
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
      if (decoded['history'] is List) {
        history = (decoded['history'] as List)
            .whereType<Map<String, dynamic>>()
            .map(HistoryItem.fromJson)
            .toList();
      }
      if (decoded['watchlist'] is List) {
        watchlist = (decoded['watchlist'] as List)
            .whereType<Map<String, dynamic>>()
            .map(WatchlistItem.fromJson)
            .toList();
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
      'history': history.map((e) => e.toJson()).toList(),
      'watchlist': watchlist.map((e) => e.toJson()).toList(),
    };
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(payload));
    await tmp.rename(file.path);
  }

  Future<void> updateSettings(AppSettings updated) async {
    settings = updated;
    await _save();
  }

  Future<void> addHistory(HistoryItem item) async {
    if (!settings.saveHistory) return;
    history.insert(0, item);
    if (history.length > 100) {
      history = history.sublist(0, 100);
    }
    await _save();
  }

  Future<void> deleteHistory(String id) async {
    history.removeWhere((e) => e.id == id);
    await _save();
  }

  Future<void> clearHistory() async {
    history.clear();
    await _save();
  }

  Future<bool> addToWatchlist(WatchlistItem item) async {
    final newLangKey = (item.languages.map((l) => l.code).toList()..sort()).join(',');
    final exists = watchlist.any((e) {
      final existingKey = (e.languages.map((l) => l.code).toList()..sort()).join(',');
      return e.titleFr.toLowerCase() == item.titleFr.toLowerCase() &&
          existingKey == newLangKey;
    });
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
