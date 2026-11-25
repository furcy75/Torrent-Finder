import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/models/seedr_models.dart';
import 'package:safetorrent/models/torbox_models.dart';
import 'package:safetorrent/models/watchlist_item.dart';

/// 100% on-device local persistence (Android, Windows, Linux — zero server/cloud).
///
/// Stores user settings, the "Plus tard" watchlist, optional Seedr OAuth tokens,
/// and optional named TorBox profiles (API keys stored locally only).
class LocalStorageService {
  LocalStorageService({Directory? overrideDirectory})
      : _overrideDirectory = overrideDirectory;

  final Directory? _overrideDirectory;

  AppSettings settings = const AppSettings();
  List<WatchlistItem> watchlist = [];
  SeedrSession? seedrSession;
  List<TorboxProfile> torboxProfiles = [];
  String? activeTorboxProfileId;
  bool isLoaded = false;

  TorboxProfile? get activeTorboxProfile {
    if (torboxProfiles.isEmpty) return null;
    if (activeTorboxProfileId != null) {
      for (final p in torboxProfiles) {
        if (p.id == activeTorboxProfileId) return p;
      }
    }
    return torboxProfiles.first;
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
      if (decoded['seedrSession'] is Map<String, dynamic>) {
        final s = SeedrSession.fromJson(decoded['seedrSession'] as Map<String, dynamic>);
        seedrSession = s.isValid ? s : null;
      }
      if (decoded['torboxProfiles'] is List) {
        torboxProfiles = (decoded['torboxProfiles'] as List)
            .whereType<Map<String, dynamic>>()
            .map(TorboxProfile.fromJson)
            .where((p) => p.apiKey.trim().isNotEmpty)
            .toList();
      }
      activeTorboxProfileId = decoded['activeTorboxProfileId'] as String?;
      if (torboxProfiles.isNotEmpty &&
          !torboxProfiles.any((p) => p.id == activeTorboxProfileId)) {
        activeTorboxProfileId = torboxProfiles.first.id;
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
      'torboxProfiles': torboxProfiles.map((e) => e.toJson()).toList(),
      'activeTorboxProfileId': activeTorboxProfileId,
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

  Future<void> addOrUpdateTorboxProfile(TorboxProfile profile, {bool makeActive = true}) async {
    final idx = torboxProfiles.indexWhere((p) => p.id == profile.id);
    if (idx == -1) {
      torboxProfiles.add(profile);
    } else {
      torboxProfiles[idx] = profile;
    }
    if (makeActive || activeTorboxProfileId == null) {
      activeTorboxProfileId = profile.id;
    }
    await _save();
  }

  Future<void> setActiveTorboxProfile(String profileId) async {
    if (torboxProfiles.any((p) => p.id == profileId)) {
      activeTorboxProfileId = profileId;
      await _save();
    }
  }

  Future<void> deleteTorboxProfile(String profileId) async {
    torboxProfiles.removeWhere((p) => p.id == profileId);
    if (activeTorboxProfileId == profileId) {
      activeTorboxProfileId = torboxProfiles.isNotEmpty ? torboxProfiles.first.id : null;
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
