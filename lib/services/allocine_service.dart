import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:safetorrent/models/movie_suggestion.dart';

/// Resolves a French movie title to its original / English title directly on-device:
/// 1. AlloCiné (primary, pure raw HTTP HTML/JSON-LD — zero WebView, zero JS)
/// 2. Wikidata API FR→EN (zero-API-key fallback)
/// 3. IMDb Suggestion JSON API (fallback)
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

  Future<List<MovieSuggestion>> resolveMovieTitles(String query, {int limit = 5}) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    final allocineHits = await _searchAllocine(clean, limit: limit);
    if (allocineHits.isNotEmpty) return allocineHits;

    final wikiHits = await _searchWikidata(clean, limit: limit);
    if (wikiHits.isNotEmpty) return wikiHits;

    return _searchImdb(clean, limit: limit);
  }

  Future<List<MovieSuggestion>> _searchAllocine(String query, {int limit = 5}) async {
    final uri = Uri.parse('$_allocineBase/rechercher/movie/?q=${Uri.encodeQueryComponent(query)}');
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

        var year = _extractYear(card.text);

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

        // Fetch top 2 movie detail pages to extract "Titre original" reliably
        if (originalTitle == null && movieUrl.isNotEmpty && results.length < 2) {
          final detail = await _fetchAllocineDetail(client, movieUrl);
          originalTitle ??= detail.$1;
          year ??= detail.$2;
          posterUrl ??= detail.$3;
        }

        results.add(
          MovieSuggestion(
            titleFr: titleFr,
            titleOriginal: originalTitle ?? titleFr,
            year: year,
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
          // ignore malformed JSON-LD block
        }
      }
      return (orig, year, poster);
    } catch (_) {
      return (null, null, null);
    }
  }

  Future<List<MovieSuggestion>> _searchWikidata(String query, {int limit = 5}) async {
    const headers = {'User-Agent': 'SafeTorrent/1.0 (Standalone)'};
    final searchUri = Uri.https('www.wikidata.org', '/w/api.php', {
      'action': 'wbsearchentities',
      'search': query,
      'language': 'fr',
      'uselang': 'fr',
      'type': 'item',
      'limit': '${limit + 3}',
      'format': 'json',
    });

    try {
      final resp = await http.get(searchUri, headers: headers).timeout(_timeout);
      if (resp.statusCode != 200) return [];
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = (decoded['search'] as List? ?? []).whereType<Map<String, dynamic>>();

      final ids = <String>[];
      for (final item in items) {
        final desc = (item['description'] as String? ?? '').toLowerCase();
        if (desc.contains('film') ||
            desc.contains('movie') ||
            desc.contains('cinéma') ||
            desc.contains('animation') ||
            desc.contains('long métrage')) {
          final id = item['id'] as String?;
          if (id != null) ids.add(id);
        }
        if (ids.length >= limit) break;
      }
      if (ids.isEmpty) return [];

      final entUri = Uri.https('www.wikidata.org', '/w/api.php', {
        'action': 'wbgetentities',
        'ids': ids.join('|'),
        'props': 'labels|descriptions|claims',
        'languages': 'fr|en',
        'format': 'json',
      });
      final entResp = await http.get(entUri, headers: headers).timeout(_timeout);
      if (entResp.statusCode != 200) return [];
      final entities =
          (jsonDecode(entResp.body) as Map<String, dynamic>)['entities'] as Map<String, dynamic>? ??
              {};

      final suggestions = <MovieSuggestion>[];
      for (final qid in ids) {
        final ent = entities[qid] as Map<String, dynamic>? ?? {};
        final labels = ent['labels'] as Map<String, dynamic>? ?? {};
        final descs = ent['descriptions'] as Map<String, dynamic>? ?? {};
        final titleFr = (labels['fr'] as Map?)?['value'] as String? ?? query;
        final titleEn = (labels['en'] as Map?)?['value'] as String? ?? titleFr;

        int? year;
        final p577 = (ent['claims'] as Map?)?['P577'] as List?;
        if (p577 != null && p577.isNotEmpty) {
          final tVal =
              ((p577.first as Map?)?['mainsnak'] as Map?)?['datavalue']?['value']?['time'];
          year = _extractYear(tVal?.toString());
        }
        year ??= _extractYear((descs['fr'] as Map?)?['value'] as String?);

        suggestions.add(
          MovieSuggestion(
            titleFr: titleFr,
            titleOriginal: titleEn,
            year: year,
            source: 'Wikidata (FR→EN)',
            sourceUrl: 'https://www.wikidata.org/wiki/$qid',
            synopsis: (descs['fr'] as Map?)?['value'] as String?,
          ),
        );
      }
      return suggestions;
    } catch (_) {
      return [];
    }
  }

  Future<List<MovieSuggestion>> _searchImdb(String query, {int limit = 5}) async {
    final cleaned = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final prefix = cleaned.isNotEmpty ? cleaned[0] : 'a';
    final uri = Uri.parse(
      'https://v3.sg.media-imdb.com/suggestion/$prefix/${Uri.encodeQueryComponent(query)}.json',
    );
    try {
      final resp =
          await http.get(uri, headers: {'User-Agent': 'SafeTorrent/1.0'}).timeout(_timeout);
      if (resp.statusCode != 200) return [];
      final list = (jsonDecode(resp.body) as Map<String, dynamic>)['d'] as List? ?? [];
      final out = <MovieSuggestion>[];
      for (final raw in list.whereType<Map<String, dynamic>>()) {
        final id = raw['id']?.toString() ?? '';
        if (!id.startsWith('tt')) continue;
        final title = raw['l']?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        final img = raw['i'] as Map?;
        out.add(
          MovieSuggestion(
            titleFr: title,
            titleOriginal: title,
            year: raw['y'] is int ? raw['y'] as int : null,
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
