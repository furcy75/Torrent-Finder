import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/models/watchlist_item.dart';
import 'package:safetorrent/services/local_storage.dart';

void main() {
  test('LocalStorage persists settings and deduplicated watchlist without storing history',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('safetorrent_test_');
    addTearDown(() => tmpDir.delete(recursive: true));

    final storage = LocalStorageService(overrideDirectory: tmpDir);
    await storage.load();

    // New built-in sources are enabled by default
    expect(storage.settings.enableKnaben, isTrue);
    expect(storage.settings.enableTorrentCsv, isTrue);
    expect(storage.settings.enableSolidTorrents, isTrue);

    await storage.updateSettings(storage.settings.copyWith(enableKnaben: false));

    // Watchlist deduplication + reload from disk
    final added1 = await storage.addToWatchlist(
      WatchlistItem(
        id: 'w1',
        titleFr: 'Film Introuvable',
        year: 2026,
        languages: const [LanguageFilter.all],
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final addedDup = await storage.addToWatchlist(
      WatchlistItem(
        id: 'w2',
        titleFr: 'film introuvable',
        languages: const [LanguageFilter.all],
        createdAt: DateTime.now().toUtc(),
      ),
    );
    expect(added1, isTrue);
    expect(addedDup, isFalse);

    final reloaded = LocalStorageService(overrideDirectory: tmpDir);
    await reloaded.load();
    expect(reloaded.settings.enableKnaben, isFalse);
    expect(reloaded.watchlist.length, equals(1));
    expect(reloaded.watchlist.first.titleFr, equals('Film Introuvable'));
  });
}
