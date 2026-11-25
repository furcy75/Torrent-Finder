import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/models/history_item.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/models/watchlist_item.dart';
import 'package:safetorrent/services/local_storage.dart';

void main() {
  test('LocalStorage persists multi-language history and watchlist on disk', () async {
    final tmpDir = await Directory.systemTemp.createTemp('safetorrent_test_');
    addTearDown(() => tmpDir.delete(recursive: true));

    final storage = LocalStorageService(overrideDirectory: tmpDir);
    await storage.load();

    // History enabled by default (multi-language + year)
    await storage.addHistory(
      HistoryItem(
        id: 'h1',
        query: 'Les Évadés',
        originalTitle: 'The Shawshank Redemption',
        year: 1994,
        languages: const [LanguageFilter.fr, LanguageFilter.en],
        resultCount: 4,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    expect(storage.history.length, equals(1));
    expect(storage.history.first.languages, equals([LanguageFilter.fr, LanguageFilter.en]));

    // Disable history -> new searches are NOT saved
    await storage.updateSettings(storage.settings.copyWith(saveHistory: false));
    await storage.addHistory(
      HistoryItem(
        id: 'h2',
        query: 'Secret Movie',
        languages: const [LanguageFilter.en],
        resultCount: 0,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    expect(storage.history.length, equals(1));

    // Watchlist deduplication + reload from disk
    final added1 = await storage.addToWatchlist(
      WatchlistItem(
        id: 'w1',
        titleFr: 'Film Introuvable',
        year: 2026,
        languages: const [LanguageFilter.fr, LanguageFilter.es],
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final addedDup = await storage.addToWatchlist(
      WatchlistItem(
        id: 'w2',
        titleFr: 'film introuvable',
        languages: const [LanguageFilter.es, LanguageFilter.fr],
        createdAt: DateTime.now().toUtc(),
      ),
    );
    expect(added1, isTrue);
    expect(addedDup, isFalse);

    final reloaded = LocalStorageService(overrideDirectory: tmpDir);
    await reloaded.load();
    expect(reloaded.settings.saveHistory, isFalse);
    expect(reloaded.history.length, equals(1));
    expect(reloaded.history.first.year, equals(1994));
    expect(reloaded.watchlist.length, equals(1));
    expect(reloaded.watchlist.first.languages.length, equals(2));
  });
}
