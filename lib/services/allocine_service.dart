import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:safetorrent/models/movie_suggestion.dart';

class SeriesScheduleInfo {
  const SeriesScheduleInfo({
    required this.tvMazeId,
    this.status,
    this.seasonCount,
    this.nextSeasonInfo,
    this.nextReleaseDate,
    this.posterUrl,
  });

  final int tvMazeId;
  final String? status;
  final int? seasonCount;
  final String? nextSeasonInfo;
  final String? nextReleaseDate;
  final String? posterUrl;
}

/// Multilingual Movie & TV Series resolver (AlloCiné + Wikidata FR/EN/ES + TVMaze + IMDb).
///
/// - For Movies: resolves FR / EN / ES / Original titles, year, poster thumbnail, synopsis.
/// - For TV Series: also resolves season count, airing status, and exact upcoming
///   season / next episode release dates via the public TVMaze API (zero API key).
class AllocineService {
  static const String _allocineBase = 'https://www.allocine.fr';
  static const Duration _timeout = Duration(seconds: 10);

  static const Map<String, String> _allocineHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.5',
  };

  static int? _extractYear(String? text) {
    if (text == null) return null;
    final m = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(text);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  static String _formatFrenchDate(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length == 3) {
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    }
    return isoDate;
  }

  static String _translateSeriesStatus(String? raw) {
    return switch ((raw ?? '').toLowerCase()) {
      'running' => 'En cours',
      'ended' => 'Terminée',
      'in development' => 'En développement',
      'to be determined' => 'Renouvellement en attente',
      _ => raw ?? '',
    };
  }

  /// Backwards-compatible alias for movies.
  Future<List<MovieSuggestion>> resolveMovieTitles(
    String query, {
    int? year,
    int limit = 6,
  }) {
    return resolveTitles(query, mediaType: MediaType.movie, year: year, limit: limit);
  }

  /// Resolve Movie or TV Series titles across FR / EN / ES / VO with poster & series schedule.
  Future<List<MovieSuggestion>> resolveTitles(
    String query, {
    MediaType mediaType = MediaType.movie,
    int? year,
    int limit = 6,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    if (mediaType == MediaType.series) {
      return _resolveSeries(clean, limit: limit);
    }
    return _resolveMovies(clean, year: year, limit: limit);
  }

  Future<List<MovieSuggestion>> _resolveMovies(
    String clean, {
    int? year,
    int limit = 6,
  }) async {
    final results = await Future.wait([
      _searchAllocine(clean, mediaType: MediaType.movie, year: year, limit: limit),
      _searchWikidataMultilingual(clean, mediaType: MediaType.movie, year: year, limit: limit),
      _searchImdb(clean, mediaType: MediaType.movie, year: year, limit: limit),
    ]);

    final allocineHits = results[0];
    final wikiHits = results[1];
    final imdbHits = results[2];

    final merged = _mergeAllocineAndWikidata(allocineHits, wikiHits);

    // Enrich missing posters using IMDb suggestions
    for (var i = 0; i < merged.length; i++) {
      final m = merged[i];
      if (m.posterUrl != null) continue;
      final candidates = m.allDistinctTitles.map((t) => t.toLowerCase()).toSet();
      for (final im in imdbHits) {
        if (im.posterUrl == null) continue;
        final yearOk = m.year == null || im.year == null || (m.year! - im.year!).abs() <= 1;
        if (yearOk && candidates.contains(im.titleOriginal.toLowerCase())) {
          merged[i] = m.copyWith(posterUrl: im.posterUrl);
          break;
        }
      }
    }

    final posterTasks = <Future<void>>[];
    for (var i = 0; i < merged.length && i < 3; i++) {
      final m = merged[i];
      final lookupTitle = m.titleEn ?? m.titleOriginal;
      if (m.posterUrl == null && lookupTitle.toLowerCase() != clean.toLowerCase()) {
        final idx = i;
        posterTasks.add(() async {
          final hits =
              await _searchImdb(lookupTitle, mediaType: MediaType.movie, year: m.year, limit: 2);
          for (final h in hits) {
            if (h.posterUrl != null) {
              merged[idx] = merged[idx].copyWith(posterUrl: h.posterUrl);
              break;
            }
          }
        }());
      }
    }
    if (posterTasks.isNotEmpty) {
      await Future.wait(posterTasks);
    }

    if (merged.isEmpty) {
      merged.addAll(imdbHits);
    }

    return merged.take(limit).toList();
  }

  Future<List<MovieSuggestion>> _resolveSeries(
    String clean, {
    int limit = 6,
  }) async {
    final results = await Future.wait([
      _searchAllocine(clean, mediaType: MediaType.series, limit: limit),
      _searchWikidataMultilingual(clean, mediaType: MediaType.series, limit: limit),
      _searchTvMaze(clean, limit: limit),
    ]);

    final allocineHits = results[0];
    final wikiHits = results[1];
    final tvMazeHits = results[2];

    final merged = _mergeAllocineAndWikidata(allocineHits, wikiHits);

    // Match merged items against TVMaze results to attach season count & next release dates
    final usedTvMaze = <int>{};
    for (var i = 0; i < merged.length; i++) {
      final m = merged[i];
      final titles = m.allDistinctTitles.map((t) => t.toLowerCase()).toSet();
      for (var j = 0; j < tvMazeHits.length; j++) {
        final tv = tvMazeHits[j];
        if (titles.contains(tv.titleOriginal.toLowerCase()) ||
            titles.contains(tv.titleFr.toLowerCase())) {
          usedTvMaze.add(j);
          merged[i] = m.copyWith(
            posterUrl: m.posterUrl ?? tv.posterUrl,
            titleEn: m.titleEn ?? tv.titleEn,
            year: m.year ?? tv.year,
            synopsis: m.synopsis ?? tv.synopsis,
            tvMazeId: tv.tvMazeId,
            seriesStatus: tv.seriesStatus,
            seasonCount: tv.seasonCount,
            nextSeasonInfo: tv.nextSeasonInfo,
            nextReleaseDate: tv.nextReleaseDate,
            source: '${m.source} + TVMaze',
          );
          break;
        }
      }
    }

    // Add remaining TVMaze results
    for (var j = 0; j < tvMazeHits.length; j++) {
      if (usedTvMaze.contains(j)) continue;
      merged.add(tvMazeHits[j]);
    }

    // For top 3 series that came from AlloCiné/Wikidata without TVMaze match yet,
    // query TVMaze using their English/original title to get exact next-season dates!
    final enrichTasks = <Future<void>>[];
    for (var i = 0; i < merged.length && i < 3; i++) {
      final m = merged[i];
      if (m.tvMazeId == null) {
        final idx = i;
        final lookup = m.titleEn ?? m.titleOriginal;
        if (lookup.toLowerCase() != clean.toLowerCase()) {
          enrichTasks.add(() async {
            final hits = await _searchTvMaze(lookup, limit: 1);
            if (hits.isNotEmpty) {
              final tv = hits.first;
              merged[idx] = merged[idx].copyWith(
                posterUrl: merged[idx].posterUrl ?? tv.posterUrl,
                tvMazeId: tv.tvMazeId,
                seriesStatus: tv.seriesStatus,
                seasonCount: tv.seasonCount,
                nextSeasonInfo: tv.nextSeasonInfo,
                nextReleaseDate: tv.nextReleaseDate,
              );
            }
          }());
        }
      }
    }
    if (enrichTasks.isNotEmpty) {
      await Future.wait(enrichTasks);
    }

    return merged.take(limit).toList();
  }

  /// Refresh live season count & upcoming season/episode dates for a saved series.
  Future<SeriesScheduleInfo?> refreshSeriesSchedule({
    int? tvMazeId,
    String? fallbackTitle,
  }) async {
    if (tvMazeId != null) {
      return _fetchTvMazeShowSchedule(tvMazeId);
    }
    if (fallbackTitle != null && fallbackTitle.trim().isNotEmpty) {
      final hits = await _searchTvMaze(fallbackTitle.trim(), limit: 1);
      if (hits.isNotEmpty && hits.first.tvMazeId != null) {
        return SeriesScheduleInfo(
          tvMazeId: hits.first.tvMazeId!,
          status: hits.first.seriesStatus,
          seasonCount: hits.first.seasonCount,
          nextSeasonInfo: hits.first.nextSeasonInfo,
          nextReleaseDate: hits.first.nextReleaseDate,
          posterUrl: hits.first.posterUrl,
        );
      }
    }
    return null;
  }

  List<MovieSuggestion> _mergeAllocineAndWikidata(
    List<MovieSuggestion> allocineHits,
    List<MovieSuggestion> wikiHits,
  ) {
    final merged = <MovieSuggestion>[];
    final usedWikiIndices = <int>{};

    for (final a in allocineHits) {
      var enriched = a;
      for (var i = 0; i < wikiHits.length; i++) {
        final w = wikiHits[i];
        final titleMatches = w.titleFr.toLowerCase() == a.titleFr.toLowerCase() ||
            (w.titleEn != null && w.titleEn!.toLowerCase() == a.titleOriginal.toLowerCase()) ||
            w.titleOriginal.toLowerCase() == a.titleOriginal.toLowerCase();
        final yearMatches = a.year == null || w.year == null || (a.year! - w.year!).abs() <= 1;
        if (titleMatches && yearMatches) {
          usedWikiIndices.add(i);
          enriched = enriched.copyWith(
            titleEn: enriched.titleEn ?? w.titleEn,
            titleEs: enriched.titleEs ?? w.titleEs,
            year: enriched.year ?? w.year,
            synopsis: enriched.synopsis ?? w.synopsis,
            source: 'AlloCiné + Wikidata',
          );
          break;
        }
      }
      merged.add(enriched);
    }

    for (var i = 0; i < wikiHits.length; i++) {
      if (usedWikiIndices.contains(i)) continue;
      final w = wikiHits[i];
      final dup = merged.any(
        (m) =>
            m.titleFr.toLowerCase() == w.titleFr.toLowerCase() &&
            (m.year == null || w.year == null || m.year == w.year),
      );
      if (!dup) merged.add(w);
    }
    return merged;
  }

  // -------------------------------------------------------------------
  // TVMaze Public API (Zero API key — Posters, Seasons, Next Season Dates)
  // -------------------------------------------------------------------
  Future<List<MovieSuggestion>> _searchTvMaze(String query, {int limit = 5}) async {
    final uri = Uri.https('api.tvmaze.com', '/search/shows', {'q': query});
    try {
      final resp = await http
          .get(uri, headers: const {'User-Agent': 'TorrentSeeder/2.0 (Standalone)'})
          .timeout(_timeout);
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body);
      if (list is! List) return [];

      final rawShows = list
          .whereType<Map<String, dynamic>>()
          .map((e) => e['show'])
          .whereType<Map<String, dynamic>>()
          .take(limit)
          .toList();

      final enriched = await Future.wait(
        rawShows.map((show) async {
          final id = (show['id'] as num?)?.toInt();
          final name = (show['name'] ?? '').toString().trim();
          if (name.isEmpty) return null;
          final year = _extractYear(show['premiered']?.toString());
          final img = show['image'] as Map<String, dynamic>?;
          final poster = (img?['medium'] ?? img?['original'])?.toString();
          final summaryRaw = (show['summary'] ?? '').toString();
          final synopsis = summaryRaw.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

          SeriesScheduleInfo? schedule;
          if (id != null) {
            schedule = await _fetchTvMazeShowSchedule(id);
          }

          return MovieSuggestion(
            titleFr: name,
            titleOriginal: name,
            titleEn: name,
            mediaType: MediaType.series,
            year: year,
            posterUrl: poster ?? schedule?.posterUrl,
            source: 'TVMaze',
            sourceUrl: show['url']?.toString(),
            synopsis: synopsis.isNotEmpty ? synopsis : null,
            tvMazeId: id,
            seriesStatus: schedule?.status ?? _translateSeriesStatus(show['status']?.toString()),
            seasonCount: schedule?.seasonCount,
            nextSeasonInfo: schedule?.nextSeasonInfo,
            nextReleaseDate: schedule?.nextReleaseDate,
          );
        }),
      );

      return enriched.whereType<MovieSuggestion>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<SeriesScheduleInfo?> _fetchTvMazeShowSchedule(int tvMazeId) async {
    final uri = Uri.parse(
      'https://api.tvmaze.com/shows/$tvMazeId?embed[]=seasons&embed[]=nextepisode',
    );
    try {
      final resp = await http
          .get(uri, headers: const {'User-Agent': 'TorrentSeeder/2.0 (Standalone)'})
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final status = _translateSeriesStatus(data['status']?.toString());
      final img = data['image'] as Map<String, dynamic>?;
      final poster = (img?['medium'] ?? img?['original'])?.toString();
      final embedded = data['_embedded'] as Map<String, dynamic>? ?? const {};

      final seasons = (embedded['seasons'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
      final seasonCount = seasons.isNotEmpty ? seasons.length : null;
      final today = DateTime.now().toUtc();
      final todayStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      String? nextInfo;
      String? nextDate;

      // 1. Check upcoming season premiere dates
      for (final s in seasons) {
        final seasonNum = s['number'];
        final premiere = s['premiereDate']?.toString();
        if (premiere != null && premiere.isNotEmpty && premiere.compareTo(todayStr) >= 0) {
          nextDate = premiere;
          nextInfo = 'Saison $seasonNum prévue le ${_formatFrenchDate(premiere)}';
          break;
        }
      }

      // 2. Check next scheduled episode if no future season premiere was found
      final nextEp = embedded['nextepisode'] as Map<String, dynamic>?;
      if (nextEp != null) {
        final airdate = nextEp['airdate']?.toString();
        final sNum = nextEp['season'];
        final eNum = nextEp['number'];
        if (airdate != null && airdate.isNotEmpty) {
          final epTag =
              'S${(sNum ?? 0).toString().padLeft(2, '0')}E${(eNum ?? 0).toString().padLeft(2, '0')}';
          if (nextInfo == null) {
            nextDate = airdate;
            nextInfo = 'Prochain épisode ($epTag) le ${_formatFrenchDate(airdate)}';
          }
        }
      }

      // 3. Check announced upcoming season without a confirmed date yet
      if (nextInfo == null && seasons.isNotEmpty) {
        final last = seasons.last;
        final lastPremiere = last['premiereDate']?.toString();
        final lastNum = last['number'];
        if ((lastPremiere == null || lastPremiere.isEmpty) && lastNum != null) {
          nextInfo = 'Saison $lastNum annoncée (date à confirmer)';
        }
      }

      return SeriesScheduleInfo(
        tvMazeId: tvMazeId,
        status: status,
        seasonCount: seasonCount,
        nextSeasonInfo: nextInfo,
        nextReleaseDate: nextDate,
        posterUrl: poster,
      );
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------
  // AlloCiné (Movies + TV Series)
  // -------------------------------------------------------------------
  Future<List<MovieSuggestion>> _searchAllocine(
    String query, {
    required MediaType mediaType,
    int? year,
    int limit = 5,
  }) async {
    final searchTerm = year != null ? '$query $year' : query;
    final section = mediaType == MediaType.series ? 'series' : 'movie';
    final uri =
        Uri.parse('$_allocineBase/rechercher/$section/?q=${Uri.encodeQueryComponent(searchTerm)}');
    final client = http.Client();
    try {
      final resp = await client.get(uri, headers: _allocineHeaders).timeout(_timeout);
      if (resp.statusCode != 200) return [];

      final doc = html_parser.parse(resp.body);
      final cards = doc.querySelectorAll('li.mdl, .entity-card-list').take(limit);
      final results = <MovieSuggestion>[];

      for (final card in cards) {
        final titleEl = card.querySelector('a.meta-title-link');
        if (titleEl == null) continue;
        final titleFr = titleEl.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final href = titleEl.attributes['href'] ?? '';
        final pageUrl = href.startsWith('/') ? '$_allocineBase$href' : href;

        var parsedYear = _extractYear(card.text);

        final imgEl = card.querySelector('img.thumbnail-img');
        var posterUrl = imgEl?.attributes['data-src'] ?? imgEl?.attributes['src'];
        if (posterUrl != null && posterUrl.startsWith('data:')) {
          posterUrl = null;
        }

        String? originalTitle;
        final subEl = card.querySelector('.meta-body-item .dark-grey, .meta-sub');
        if (subEl != null) {
          final m = RegExp(r'titre\s+original\s*:?\s*(.+)$', caseSensitive: false)
              .firstMatch(subEl.text.trim());
          if (m != null) {
            originalTitle = m.group(1)?.trim();
          }
        }

        if (originalTitle == null && pageUrl.isNotEmpty && results.length < 3) {
          final detail = await _fetchAllocineDetail(client, pageUrl);
          originalTitle ??= detail.$1;
          parsedYear ??= detail.$2;
          posterUrl ??= detail.$3;
        }

        results.add(
          MovieSuggestion(
            titleFr: titleFr,
            titleOriginal: originalTitle ?? titleFr,
            titleEn: originalTitle,
            mediaType: mediaType,
            year: parsedYear,
            posterUrl: posterUrl,
            source: 'AlloCiné',
            sourceUrl: pageUrl.isNotEmpty ? pageUrl : null,
          ),
        );
      }
      return results;
    } catch (_) {
      return [];
    } finally {
      client.close();
    }
  }

  Future<(String?, int?, String?)> _fetchAllocineDetail(
    http.Client client,
    String pageUrl,
  ) async {
    try {
      final resp =
          await client.get(Uri.parse(pageUrl), headers: _allocineHeaders).timeout(_timeout);
      if (resp.statusCode != 200) return (null, null, null);

      final doc = html_parser.parse(resp.body);
      String? orig;
      int? year;
      String? poster;

      for (final div in doc.querySelectorAll('.meta-body-item, .ovw-technical .item')) {
        final txt = div.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final m = RegExp(r'titre\s+original\s*:?\s*(.+)$', caseSensitive: false).firstMatch(txt);
        if (m != null) {
          final cand = m.group(1)?.replaceAll(RegExp(r'^[\s:–-]+|[\s:–-]+$'), '');
          if (cand != null && cand.isNotEmpty) {
            orig = cand;
            break;
          }
        }
      }

      for (final script in doc.querySelectorAll('script[type="application/ld+json"]')) {
        try {
          final data = jsonDecode(script.text);
          if (data is Map<String, dynamic> &&
              (data['@type'] == 'Movie' || data['@type'] == 'TVSeries')) {
            if (orig == null && data['alternateName'] is String) {
              orig = (data['alternateName'] as String).trim();
            }
            year ??= _extractYear(data['datePublished']?.toString());
            if (poster == null) {
              final img = data['image'];
              if (img is Map && img['url'] is String) {
                poster = img['url'] as String;
              } else if (img is String) {
                poster = img;
              }
            }
          }
        } catch (_) {
          // ignore
        }
      }
      return (orig, year, poster);
    } catch (_) {
      return (null, null, null);
    }
  }

  // -------------------------------------------------------------------
  // Wikidata Multilingual FR / EN / ES (Movies & TV Series)
  // -------------------------------------------------------------------
  Future<List<MovieSuggestion>> _searchWikidataMultilingual(
    String query, {
    required MediaType mediaType,
    int? year,
    int limit = 6,
  }) async {
    const headers = {'User-Agent': 'TorrentSeeder/2.0 (Standalone)'};
    final searchLanguages = ['fr', 'en', 'es'];
    final candidateIds = <String>[];
    final seenIds = <String>{};

    try {
      final searchResponses = await Future.wait(
        searchLanguages.map((lang) {
          final uri = Uri.https('www.wikidata.org', '/w/api.php', {
            'action': 'wbsearchentities',
            'search': query,
            'language': lang,
            'uselang': 'fr',
            'type': 'item',
            'limit': '6',
            'format': 'json',
          });
          return http.get(uri, headers: headers).timeout(_timeout).catchError(
                (_) => http.Response('', 500),
              );
        }),
      );

      for (final resp in searchResponses) {
        if (resp.statusCode != 200) continue;
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final items = (decoded['search'] as List? ?? []).whereType<Map<String, dynamic>>();
        for (final item in items) {
          final desc = (item['description'] as String? ?? '').toLowerCase();
          final matchesType = mediaType == MediaType.series
              ? (desc.contains('série') ||
                  desc.contains('series') ||
                  desc.contains('serie') ||
                  desc.contains('anime') ||
                  desc.contains('mini-série') ||
                  desc.contains('sitcom'))
              : (desc.contains('film') ||
                  desc.contains('movie') ||
                  desc.contains('cinéma') ||
                  desc.contains('animation') ||
                  desc.contains('documentaire') ||
                  desc.contains('película') ||
                  desc.contains('long métrage'));
          final id = item['id'] as String?;
          if (matchesType && id != null && seenIds.add(id)) {
            candidateIds.add(id);
          }
          if (candidateIds.length >= limit + 4) break;
        }
      }

      if (candidateIds.isEmpty) return [];

      final entUri = Uri.https('www.wikidata.org', '/w/api.php', {
        'action': 'wbgetentities',
        'ids': candidateIds.take(10).join('|'),
        'props': 'labels|descriptions|claims',
        'languages': 'fr|en|es',
        'format': 'json',
      });
      final entResp = await http.get(entUri, headers: headers).timeout(_timeout);
      if (entResp.statusCode != 200) return [];

      final entities =
          (jsonDecode(entResp.body) as Map<String, dynamic>)['entities'] as Map<String, dynamic>? ??
              {};

      final suggestions = <MovieSuggestion>[];
      for (final qid in candidateIds.take(10)) {
        final ent = entities[qid] as Map<String, dynamic>? ?? {};
        final labels = ent['labels'] as Map<String, dynamic>? ?? {};
        final descs = ent['descriptions'] as Map<String, dynamic>? ?? {};
        final claims = ent['claims'] as Map<String, dynamic>? ?? {};

        final titleFr = (labels['fr'] as Map?)?['value'] as String?;
        final titleEn = (labels['en'] as Map?)?['value'] as String?;
        final titleEs = (labels['es'] as Map?)?['value'] as String?;

        String? titleOrig;
        final p1476 = claims['P1476'] as List?;
        if (p1476 != null && p1476.isNotEmpty) {
          titleOrig = ((p1476.first as Map?)?['mainsnak'] as Map?)?['datavalue']?['value']?['text']
              ?.toString();
        }

        int? parsedYear;
        final dateProp = claims['P577'] as List? ?? claims['P580'] as List?;
        if (dateProp != null && dateProp.isNotEmpty) {
          final tVal =
              ((dateProp.first as Map?)?['mainsnak'] as Map?)?['datavalue']?['value']?['time'];
          parsedYear = _extractYear(tVal?.toString());
        }
        parsedYear ??= _extractYear((descs['fr'] as Map?)?['value'] as String?);
        parsedYear ??= _extractYear((descs['en'] as Map?)?['value'] as String?);

        if (year != null && parsedYear != null && (parsedYear - year).abs() > 2) {
          continue;
        }

        final primaryFr = titleFr ?? titleEn ?? titleEs ?? titleOrig ?? query;
        final primaryOrig = titleOrig ?? titleEn ?? primaryFr;

        suggestions.add(
          MovieSuggestion(
            titleFr: primaryFr,
            titleEn: titleEn,
            titleEs: titleEs,
            titleOriginal: primaryOrig,
            mediaType: mediaType,
            year: parsedYear,
            source: 'Wikidata (FR/EN/ES)',
            sourceUrl: 'https://www.wikidata.org/wiki/$qid',
            synopsis: (descs['fr'] as Map?)?['value'] as String? ??
                (descs['en'] as Map?)?['value'] as String?,
          ),
        );
      }
      return suggestions;
    } catch (_) {
      return [];
    }
  }

  Future<List<MovieSuggestion>> _searchImdb(
    String query, {
    required MediaType mediaType,
    int? year,
    int limit = 5,
  }) async {
    final cleaned = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final prefix = cleaned.isNotEmpty ? cleaned[0] : 'a';
    final uri = Uri.parse(
      'https://v3.sg.media-imdb.com/suggestion/$prefix/${Uri.encodeQueryComponent(query)}.json',
    );
    try {
      final resp =
          await http.get(uri, headers: {'User-Agent': 'TorrentSeeder/2.0'}).timeout(_timeout);
      if (resp.statusCode != 200) return [];
      final list = (jsonDecode(resp.body) as Map<String, dynamic>)['d'] as List? ?? [];
      final out = <MovieSuggestion>[];
      for (final raw in list.whereType<Map<String, dynamic>>()) {
        final id = raw['id']?.toString() ?? '';
        if (!id.startsWith('tt')) continue;
        final title = raw['l']?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        final qid = (raw['qid'] ?? raw['q'] ?? '').toString().toLowerCase();
        if (mediaType == MediaType.series &&
            qid.isNotEmpty &&
            !qid.contains('tv') &&
            !qid.contains('series')) {
          continue;
        }
        final itemYear = raw['y'] is int ? raw['y'] as int : null;
        if (year != null && itemYear != null && (itemYear - year).abs() > 2) continue;
        final img = raw['i'] as Map?;
        out.add(
          MovieSuggestion(
            titleFr: title,
            titleEn: title,
            titleOriginal: title,
            mediaType: mediaType,
            year: itemYear,
            posterUrl: img?['imageUrl'] as String?,
            source: 'IMDb',
            sourceUrl: 'https://www.imdb.com/title/$id/',
          ),
        );
        if (out.length >= limit) break;
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}
