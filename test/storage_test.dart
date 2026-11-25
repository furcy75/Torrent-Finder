import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/models/movie_suggestion.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/models/watchlist_item.dart';
import 'package:safetorrent/services/local_storage.dart';

void main() {
  test('LocalStorage persists settings, posters, and TV series next-season info in watchlist',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('safetorrent_test_');
    addTearDown(() => tmpDir.delete(recursive: true));

    final storage = LocalStorageService(overrideDirectory: tmpDir);
    await storage.load();

    // All 10 built-in sources enabled by default
    expect(storage.settings.enableKnaben, isTrue);
    expect(storage.settings.enableEztv, isTrue);
    expect(storage.settings.enableBitSearch, isTrue);
    expect(storage.settings.enableNyaa, isTrue);
    expect(storage.settings.enableLimeTorrents, isTrue);

    await storage.updateSettings(storage.settings.copyWith(enableKnaben: false));

    // Watchlist stores posterUrl + TV series next-season metadata and deduplicates
    final added1 = await storage.addToWatchlist(
      WatchlistItem(
        id: 'w1',
        titleFr: 'Severance',
        titleOriginal: 'Severance',
        titleEn: 'Severance',
        posterUrl: 'https://static.tvmaze.com/uploads/images/medium_portrait/1.jpg',
        mediaType: MediaType.series,
        tvMazeId: 44933,
        seriesStatus: 'En cours',
        seasonCount: 2,
        nextSeasonInfo: 'Saison 3 annoncée (date à confirmer)',
        year: 2022,
        languages: const [LanguageFilter.all],
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final addedDup = await storage.addToWatchlist(
      WatchlistItem(
        id: 'w2',
        titleFr: 'severance',
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
    final saved = reloaded.watchlist.first;
    expect(saved.posterUrl, equals('https://static.tvmaze.com/uploads/images/medium_portrait/1.jpg'));
    expect(saved.mediaType, equals(MediaType.series));
    expect(saved.seasonCount, equals(2));
    expect(saved.nextSeasonInfo, contains('Saison 3'));
    expect(saved.toMovieSuggestion().posterUrl, equals(saved.posterUrl));
  });
}
