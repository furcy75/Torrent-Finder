import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:safetorrent/models/movie_suggestion.dart';

/// Multilingual movie title resolver (AlloCiné + Wikidata FR/EN/ES + IMDb).
///
/// Supports searching by movie title + optional release year, and returns
/// localized titles across French (FR), English (EN), Spanish (ES), and Original (VO)
/// using pure raw HTTP requests (zero WebView, zero JavaScript).
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

  /// Resolve movie titles across languages from AlloCiné + Wikidata (FR/EN/ES) + IMDb.
  Future<List<MovieSuggestion>> resolveMovieTitles(
    String query, {
    int? year,
    int limit = 6,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    // Query AlloCiné and Wikidata (FR/EN/ES) concurrently to maximize multilingual coverage
    final results = await Future.wait([
      _searchAllocine(clean, year: year, limit: limit),
      _searchWikidataMultilingual(clean, year: year, limit: limit),
    ]);

    final allocineHits = results[0];
    final wikiHits = results[1];

    // Enrich AlloCiné results with FR / EN / ES labels found via Wikidata when matching
    final merged = <MovieSuggestion>[];
    final usedWikiIndices = <int>{};

    for (final a in allocineHits) {
      MovieSuggestion enriched = a;
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
            source: 'AlloCiné + Wikidata',
          );
          break;
        }
      }
      merged.add(enriched);
    }

    // Add remaining distinct Wikidata multilingual hits
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

    if (merged.isEmpty) {
      merged.addAll(await _searchImdb(clean, year: year, limit: limit));
    }

    // Prioritize exact year match if user specified a year
    if (year != null) {
      merged.sort((a, b) {
        final aDist = a.year != null ? (a.year! - year).abs() : 99;
        final bDist = b.year != null ? (b.year! - year).abs() : 99;
        return aDist.compareTo(bDist);
      });
    }

    return merged.take(limit).toList();
  }

  Future<List<MovieSuggestion>> _searchAllocine(
    String query, {
    int? year,
    int limit = 5,
  }) async {
    final searchTerm = year != null ? '$query $year' : query;
    final uri =
        Uri.parse('$_allocineBase/rechercher/movie/?q=${Uri.encodeQueryComponent(searchTerm)}');
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
        final movieUrl = href.startsWith('/') ? '$_allocineBase$href' : href;

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

        if (originalTitle == null && movieUrl.isNotEmpty && results.length < 3) {
          final detail = await _fetchAllocineDetail(client, movieUrl);
          originalTitle ??= detail.$1;
          parsedYear ??= detail.$2;
          posterUrl ??= detail.$3;
        }

        results.add(
          MovieSuggestion(
            titleFr: titleFr,
            titleOriginal: originalTitle ?? titleFr,
            titleEn: originalTitle,
            year: parsedYear,
            posterUrl: posterUrl,
            source: 'AlloCiné',
            sourceUrl: movieUrl.isNotEmpty ? movieUrl : null,
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
    String movieUrl,
  ) async {
    try {
      final resp =
          await client.get(Uri.parse(movieUrl), headers: _allocineHeaders).timeout(_timeout);
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
          if (data is Map<String, dynamic> && data['@type'] == 'Movie') {
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

  /// Searches Wikidata in French, English, and Spanish simultaneously to retrieve
  /// the movie's localized title in FR, EN, ES, and original language (P1476).
  Future<List<MovieSuggestion>> _searchWikidataMultilingual(
    String query, {
    int? year,
    int limit = 6,
  }) async {
    const headers = {'User-Agent': 'SafeTorrent/1.1 (Standalone)'};
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
          final isMovie = desc.contains('film') ||
              desc.contains('movie') ||
              desc.contains('cinéma') ||
              desc.contains('animation') ||
              desc.contains('documentaire') ||
              desc.contains('película') ||
              desc.contains('long métrage');
          final id = item['id'] as String?;
          if (isMovie && id != null && seenIds.add(id)) {
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

        // Official original title property P1476 if available
        String? titleOrig;
        final p1476 = claims['P1476'] as List?;
        if (p1476 != null && p1476.isNotEmpty) {
          titleOrig = ((p1476.first as Map?)?['mainsnak'] as Map?)?['datavalue']?['value']?['text']
              ?.toString();
        }

        // Release year property P577
        int? parsedYear;
        final p577 = claims['P577'] as List?;
        if (p577 != null && p577.isNotEmpty) {
          final tVal =
              ((p577.first as Map?)?['mainsnak'] as Map?)?['datavalue']?['value']?['time'];
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
          await http.get(uri, headers: {'User-Agent': 'SafeTorrent/1.1'}).timeout(_timeout);
      if (resp.statusCode != 200) return [];
      final list = (jsonDecode(resp.body) as Map<String, dynamic>)['d'] as List? ?? [];
      final out = <MovieSuggestion>[];
      for (final raw in list.whereType<Map<String, dynamic>>()) {
        final id = raw['id']?.toString() ?? '';
        if (!id.startsWith('tt')) continue;
        final title = raw['l']?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        final itemYear = raw['y'] is int ? raw['y'] as int : null;
        if (year != null && itemYear != null && (itemYear - year).abs() > 2) continue;
        final img = raw['i'] as Map?;
        out.add(
          MovieSuggestion(
            titleFr: title,
            titleEn: title,
            titleOriginal: title,
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
