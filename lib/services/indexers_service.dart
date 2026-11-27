import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/models/movie_suggestion.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/services/custom_site_service.dart';
import 'package:safetorrent/services/release_parser.dart';
import 'package:xml/xml.dart';

class SearchSummary {
  const SearchSummary({
    required this.results,
    required this.indexersQueried,
    required this.countsByIndexer,
    required this.errors,
  });

  final List<TorrentResult> results;
  final List<String> indexersQueried;
  final Map<String, int> countsByIndexer;
  final Map<String, String> errors;
}

/// Full-catalog parallel on-device torrent search aggregator (pure HTTP — zero ads, zero JS).
///
/// Searches the ENTIRE catalog (Movies, Series, Anime, Music, Books, Software, Games, etc.)
/// across 11 built-in sources + optional Torznab (Jackett/Prowlarr) + user Custom Websites:
/// 1. Knaben (Multi-tracker JSON API: 1337x, TPB, TGx, RuTracker, YTS, EZTV, LimeTorrents, Nyaa...)
/// 2. APIBay (Full-catalog JSON API — real NFO via `t.php`)
/// 3. TorrentCSV (Full-catalog open-source JSON API)
/// 4. YTS (Multi-mirror JSON API — direct `.torrent`)
/// 5. EZTV (HTML + JSON API — direct `.torrent` + magnet)
/// 6. BitSearch (HTML parser + smart fallback)
/// 7. Nyaa (Full-catalog RSS XML — direct `.torrent`)
/// 8. SubsPlease (JSON API — direct `.torrent` + magnet)
/// 9. SolidTorrents (Multi-mirror full-catalog JSON API)
/// 10. LimeTorrents (Multi-mirror RSS XML — direct `.torrent`)
/// 11. Internet Archive (Full-catalog BitTorrent items + `.torrent` / `.nfo`)
/// + Optional Torznab (Jackett / Prowlarr — full catalog)
/// + Optional Custom Websites (generic HTML/CSS/RSS/JSON/2-step extractor)
class IndexersService {
  static const Duration _timeout = Duration(seconds: 12);
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept': 'application/json, application/xml, text/html;q=0.9, */*;q=0.8',
  };

  final CustomSiteService _customSiteService = CustomSiteService();

  static String buildMagnet(String infoHash, String title) =>
      CustomSiteService.buildMagnet(infoHash, title);

  static int _parseHumanSizeToBytes(String raw) =>
      CustomSiteService.parseHumanSizeToBytes(raw);

  Future<SearchSummary> search({
    required String query,
    List<String> extraTitles = const [],
    MediaType mediaType = MediaType.movie,
    String? seasonQueryTag,
    Set<LanguageFilter> languages = const {LanguageFilter.all},
    int? year,
    bool includeAllLanguages = true,
    required AppSettings settings,
  }) async {
    final seenQ = <String>{};
    final queries = <String>[];
    final suffix = (seasonQueryTag != null && seasonQueryTag.trim().isNotEmpty)
        ? ' ${seasonQueryTag.trim()}'
        : '';

    for (final raw in [query, ...extraTitles]) {
      final clean = '${raw.trim()}$suffix'.trim();
      if (clean.isNotEmpty && seenQ.add(clean.toLowerCase())) {
        queries.add(clean);
      }
    }
    if (queries.isEmpty) {
      return const SearchSummary(
        results: [],
        indexersQueried: [],
        countsByIndexer: {},
        errors: {},
      );
    }

    final effectiveLangs = includeAllLanguages || languages.isEmpty
        ? const {LanguageFilter.all}
        : languages;

    final tasks = <Future<(String, List<TorrentResult>, String?)>>[];
    final queriedNames = <String>[];

    // Full-catalog search: EVERY enabled source runs without movie/series gating!
    if (settings.enableKnaben) {
      queriedNames.add('Knaben');
      tasks.add(_safeRun('Knaben', () => _searchKnaben(queries, effectiveLangs)));
    }
    if (settings.enableApibay) {
      queriedNames.add('APIBay');
      tasks.add(_safeRun('APIBay', () => _searchApibay(queries, effectiveLangs)));
    }
    if (settings.enableTorrentCsv) {
      queriedNames.add('TorrentCSV');
      tasks.add(_safeRun('TorrentCSV', () => _searchTorrentCsv(queries, effectiveLangs)));
    }
    if (settings.enableYts) {
      queriedNames.add('YTS');
      tasks.add(_safeRun('YTS', () => _searchYts(queries, effectiveLangs)));
    }
    if (settings.enableEztv) {
      queriedNames.add('EZTV');
      tasks.add(_safeRun('EZTV', () => _searchEztv(queries, effectiveLangs)));
    }
    if (settings.enableBitSearch) {
      queriedNames.add('BitSearch');
      tasks.add(_safeRun('BitSearch', () => _searchBitSearch(queries, effectiveLangs)));
    }
    if (settings.enableNyaa) {
      queriedNames.add('Nyaa');
      tasks.add(_safeRun('Nyaa', () => _searchNyaa(queries, effectiveLangs)));
    }
    if (settings.enableSubsPlease) {
      queriedNames.add('SubsPlease');
      tasks.add(_safeRun('SubsPlease', () => _searchSubsPlease(queries, effectiveLangs)));
    }
    if (settings.enableSolidTorrents) {
      queriedNames.add('SolidTorrents');
      tasks.add(_safeRun('SolidTorrents', () => _searchSolidTorrents(queries, effectiveLangs)));
    }
    if (settings.enableLimeTorrents) {
      queriedNames.add('LimeTorrents');
      tasks.add(_safeRun('LimeTorrents', () => _searchLimeTorrents(queries, effectiveLangs)));
    }
    if (settings.enableArchiveOrg) {
      queriedNames.add('Internet Archive');
      tasks.add(_safeRun('Internet Archive', () => _searchArchiveOrg(queries, effectiveLangs)));
    }
    for (final tz in settings.torznabIndexers.where((c) => c.enabled)) {
      final label = 'Torznab: ${tz.name}';
      queriedNames.add(label);
      tasks.add(_safeRun(label, () => _searchTorznab(tz, queries, effectiveLangs)));
    }
    for (final site in settings.customSites.where((s) => s.enabled)) {
      queriedNames.add(site.name);
      tasks.add(
        _safeRun(
          site.name,
          () => _customSiteService.searchSite(site, queries.first),
        ),
      );
    }

    final batches = await Future.wait(tasks);
    final errors = <String, String>{};
    final countsByIndexer = <String, int>{};
    final deduped = <String, TorrentResult>{};

    for (final (name, items, err) in batches) {
      if (err != null) {
        errors[name] = err;
        countsByIndexer[name] = 0;
        continue;
      }
      countsByIndexer[name] = items.length;
      for (final item in items) {
        final key = (item.infoHash ?? item.id).toLowerCase();
        final existing = deduped[key];
        if (existing == null) {
          deduped[key] = item;
        } else if ((item.torrentUrl != null && existing.torrentUrl == null) ||
            item.seeders > existing.seeders) {
          deduped[key] = item.copyWith(
            torrentUrl: item.torrentUrl ?? existing.torrentUrl,
            nfoText: item.nfoText ?? existing.nfoText,
            sourceId: item.sourceId ?? existing.sourceId,
          );
        }
      }
    }

    final results = deduped.values.toList();
    results.sort((a, b) {
      final aOk = a.preScanStatus == SafetyStatus.blocked ? 0 : 1;
      final bOk = b.preScanStatus == SafetyStatus.blocked ? 0 : 1;
      if (aOk != bOk) return bOk.compareTo(aOk);
      if (a.seeders != b.seeders) return b.seeders.compareTo(a.seeders);
      return ReleaseParser.qualityRank(b.quality).compareTo(ReleaseParser.qualityRank(a.quality));
    });

    return SearchSummary(
      results: results,
      indexersQueried: queriedNames,
      countsByIndexer: countsByIndexer,
      errors: errors,
    );
  }

  Future<(String, List<TorrentResult>, String?)> _safeRun(
    String name,
    Future<List<TorrentResult>> Function() fn,
  ) async {
    try {
      return (name, await fn(), null);
    } catch (e) {
      return (name, const <TorrentResult>[], e.toString());
    }
  }

  // 1. Knaben JSON API — Full catalog (NO category restriction, aggregates 1337x, TPB, TGx, RuTracker, YTS, EZTV, Nyaa...)
  Future<List<TorrentResult>> _searchKnaben(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    final out = <TorrentResult>[];
    final seen = <String>{};
    final uri = Uri.parse('https://api.knaben.org/v1');

    for (final q in queries.take(3)) {
      final body = jsonEncode({
        'search_type': '100%',
        'search_field': 'title',
        'query': q,
        'order_by': 'seeders',
        'order_direction': 'desc',
        'from': 0,
        'size': 80,
        'hide_unsafe': true,
        'hide_xxx': true,
      });
      final resp = await http
          .post(
            uri,
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) continue;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final hits = (data['hits'] as List? ?? []).whereType<Map<String, dynamic>>();

      for (final hit in hits) {
        final title = (hit['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final rawHash = (hit['hash'] ?? '').toString().trim().toUpperCase();
        final magnet = hit['magnetUrl']?.toString();
        final hash = rawHash.length == 40 ? rawHash : _extractHashFromMagnet(magnet);
        final uid = hash ?? 'knaben-${title.hashCode.abs()}';
        if (!seen.add(uid)) continue;

        final sizeBytes = (hit['bytes'] as num?)?.toInt() ?? 0;
        final seeders = (hit['seeders'] as num?)?.toInt() ?? 0;
        final leechers = (hit['peers'] as num?)?.toInt() ?? 0;
        final origin = (hit['cachedOrigin'] ?? 'Knaben').toString();
        final category = (hit['category'] ?? '').toString().trim();
        final link = hit['link']?.toString();
        final torrentUrl =
            link != null && link.startsWith('http') && link.toLowerCase().contains('.torrent')
                ? link
                : null;

        var (quality, tags) = ReleaseParser.parseQuality(title);
        if (quality == 'Standard' && category.isNotEmpty) {
          quality = category;
        }
        final langs = ReleaseParser.detectLanguages(title);
        final (preStatus, preWarn) = ReleaseParser.preScanTitle(title, sizeBytes, seeders);

        out.add(
          TorrentResult(
            id: 'kn-${uid.substring(0, uid.length >= 12 ? 12 : uid.length).toLowerCase()}',
            title: title,
            quality: quality,
            qualityTags: tags,
            sizeBytes: sizeBytes,
            sizeHuman: ReleaseParser.formatSize(sizeBytes),
            seeders: seeders,
            leechers: leechers,
            detectedLanguages: langs,
            languageMatch: ReleaseParser.matchesAnyLanguage(langs, languages),
            indexer: origin == 'Knaben' ? 'Knaben' : 'Knaben ($origin)',
            infoHash: hash,
            torrentUrl: torrentUrl,
            magnetUrl: (magnet != null && magnet.startsWith('magnet:'))
                ? magnet
                : (hash != null ? buildMagnet(hash, title) : null),
            preScanStatus: preStatus,
            preScanWarnings: preWarn,
            publishedAt: hit['date']?.toString(),
          ),
        );
      }
    }
    return out;
  }

  // 2. APIBay JSON API — Full catalog (cat=0: ALL categories + real NFO via t.php)
  Future<List<TorrentResult>> _searchApibay(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final term in queries.take(3)) {
      final uri = Uri.https('apibay.org', '/q.php', {'q': term});
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) continue;
      final items = jsonDecode(resp.body);
      if (items is! List) continue;

      for (final item in items.whereType<Map<String, dynamic>>().take(60)) {
        final name = (item['name'] ?? '').toString().trim();
        final hash = (item['info_hash'] ?? '').toString().toUpperCase();
        if (name.isEmpty || hash.isEmpty || hash == '0' * 40 || !seen.add(hash)) continue;

        final sizeBytes = int.tryParse(item['size']?.toString() ?? '0') ?? 0;
        final seeders = int.tryParse(item['seeders']?.toString() ?? '0') ?? 0;
        final leechers = int.tryParse(item['leechers']?.toString() ?? '0') ?? 0;
        final (quality, tags) = ReleaseParser.parseQuality(name);
        final langs = ReleaseParser.detectLanguages(name);
        final (preStatus, preWarn) = ReleaseParser.preScanTitle(name, sizeBytes, seeders);

        out.add(
          TorrentResult(
            id: 'apibay-${hash.substring(0, hash.length >= 12 ? 12 : hash.length).toLowerCase()}',
            title: name,
            quality: quality,
            qualityTags: tags,
            sizeBytes: sizeBytes,
            sizeHuman: ReleaseParser.formatSize(sizeBytes),
            seeders: seeders,
            leechers: leechers,
            detectedLanguages: langs,
            languageMatch: ReleaseParser.matchesAnyLanguage(langs, languages),
            indexer: 'APIBay',
            sourceId: item['id']?.toString(),
            infoHash: hash,
            torrentUrl: null,
            magnetUrl: buildMagnet(hash, name),
            preScanStatus: preStatus,
            preScanWarnings: preWarn,
          ),
        );
      }
    }
    return out;
  }

  // 3. TorrentCSV Open-Source JSON API — Full catalog
  Future<List<TorrentResult>> _searchTorrentCsv(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final q in queries.take(3)) {
      final uri = Uri.https('torrents-csv.com', '/service/search', {'q': q, 'size': '60'});
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) continue;
      final decoded = jsonDecode(resp.body);
      final list = decoded is List
          ? decoded
          : (decoded is Map<String, dynamic> ? (decoded['torrents'] as List? ?? []) : const []);

      for (final item in list.whereType<Map<String, dynamic>>()) {
        final name = (item['name'] ?? '').toString().trim();
        final hash = (item['infohash'] ?? '').toString().trim().toUpperCase();
        if (name.isEmpty || hash.length != 40 || !seen.add(hash)) continue;

        final sizeBytes = (item['size_bytes'] as num?)?.toInt() ?? 0;
        final seeders = (item['seeders'] as num?)?.toInt() ?? 0;
        final leechers = (item['leechers'] as num?)?.toInt() ?? 0;
        final (quality, tags) = ReleaseParser.parseQuality(name);
        final langs = ReleaseParser.detectLanguages(name);
        final (preStatus, preWarn) = ReleaseParser.preScanTitle(name, sizeBytes, seeders);

        out.add(
          TorrentResult(
            id: 'tcsv-${hash.substring(0, 12).toLowerCase()}',
            title: name,
            quality: quality,
            qualityTags: tags,
            sizeBytes: sizeBytes,
            sizeHuman: ReleaseParser.formatSize(sizeBytes),
            seeders: seeders,
            leechers: leechers,
            detectedLanguages: langs,
            languageMatch: ReleaseParser.matchesAnyLanguage(langs, languages),
            indexer: 'TorrentCSV',
            infoHash: hash,
            torrentUrl: null,
            magnetUrl: buildMagnet(hash, name),
            preScanStatus: preStatus,
            preScanWarnings: preWarn,
          ),
        );
      }
    }
    return out;
  }

  // 4. YTS Multi-Mirror JSON API (working mirrors first, runs on every search)
  Future<List<TorrentResult>> _searchYts(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    const mirrors = [
      'https://movies-api.accel.li/api/v2/list_movies.json',
      'https://yts.rs/api/v2/list_movies.json',
      'https://yts.mx/api/v2/list_movies.json',
      'https://yts.lt/api/v2/list_movies.json',
    ];
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final q in queries.take(3)) {
      Map<String, dynamic>? payload;
      for (final mirror in mirrors) {
        try {
          final uri = Uri.parse(mirror).replace(queryParameters: {
            'query_term': q,
            'limit': '25',
            'sort_by': 'seeds',
          });
          final resp = await http.get(uri, headers: _headers).timeout(_timeout);
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            if (data['status'] == 'ok') {
              payload = data;
              break;
            }
          }
        } catch (_) {
          continue;
        }
      }
      if (payload == null) continue;

      final movies = ((payload['data'] as Map?)?['movies'] as List? ?? [])
          .whereType<Map<String, dynamic>>();
      for (final movie in movies) {
        final movieId = movie['id']?.toString();
        final movieTitle = (movie['title_long'] ?? movie['title'] ?? q).toString();
        final mLang = (movie['language'] ?? 'en').toString().toLowerCase();
        final defaultLang = mLang.length >= 2 ? mLang.substring(0, 2).toUpperCase() : 'EN';

        for (final t in (movie['torrents'] as List? ?? []).whereType<Map<String, dynamic>>()) {
          final hash = (t['hash'] ?? '').toString().toUpperCase();
          if (hash.isEmpty || !seen.add(hash)) continue;

          final qStr = (t['quality'] ?? '').toString();
          final typeStr = (t['type'] ?? '').toString();
          final vCodec = (t['video_codec'] ?? '').toString();
          final bitDepth = (t['bit_depth'] ?? '').toString();
          final audioCh = (t['audio_channels'] ?? '').toString();

          final fullTitle =
              '$movieTitle [$qStr $typeStr${vCodec.isNotEmpty ? ' $vCodec' : ''}]'.trim();
          final (quality, tags) = ReleaseParser.parseQuality(
            fullTitle,
            explicitQuality: '$qStr $typeStr',
          );
          final sizeBytes = (t['size_bytes'] as num?)?.toInt() ?? 0;
          final seeders = (t['seeds'] as num?)?.toInt() ?? 0;
          final leechers = (t['peers'] as num?)?.toInt() ?? 0;
          final langs = ReleaseParser.detectLanguages(fullTitle, defaultLang: defaultLang);
          final (preStatus, preWarn) = ReleaseParser.preScanTitle(fullTitle, sizeBytes, seeders);

          final nfoLines = <String>[
            'Release     : $fullTitle',
            'Quality     : $qStr ($typeStr)',
            if (vCodec.isNotEmpty)
              'Video       : $vCodec${bitDepth.isNotEmpty ? ' ($bitDepth-bit)' : ''}',
            if (audioCh.isNotEmpty) 'Audio       : $audioCh ch ($defaultLang)',
            'Size        : ${t['size'] ?? ReleaseParser.formatSize(sizeBytes)}',
            'Uploaded    : ${t['date_uploaded'] ?? '—'}',
            'Info-Hash   : $hash',
          ];

          out.add(
            TorrentResult(
              id: 'yts-${hash.substring(0, hash.length >= 12 ? 12 : hash.length).toLowerCase()}',
              title: fullTitle,
              quality: quality,
              qualityTags: tags,
              sizeBytes: sizeBytes,
              sizeHuman: t['size']?.toString() ?? ReleaseParser.formatSize(sizeBytes),
              seeders: seeders,
              leechers: leechers,
              detectedLanguages: langs,
              languageMatch: ReleaseParser.matchesAnyLanguage(langs, languages),
              indexer: 'YTS',
              sourceId: movieId,
              nfoText: nfoLines.join('\n'),
              infoHash: hash,
              torrentUrl: t['url']?.toString(),
              magnetUrl: buildMagnet(hash, fullTitle),
              preScanStatus: preStatus,
              preScanWarnings: preWarn,
              publishedAt: t['date_uploaded']?.toString(),
            ),
          );
        }
      }
    }
    return out;
  }

  // 5. EZTV (HTML search + JSON API fallback — direct `.torrent` + magnet)
  Future<List<TorrentResult>> _searchEztv(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    const mirrors = ['https://eztvx.to', 'https://eztv.re'];
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final q in queries.take(2)) {
      final slug = q.trim().replaceAll(RegExp(r'\s+'), '-');
      String? body;
      for (final mirror in mirrors) {
        try {
          final uri = Uri.parse('$mirror/search/${Uri.encodeComponent(slug)}');
          final resp = await http.get(uri, headers: _headers).timeout(_timeout);
          if (resp.statusCode == 200 && resp.body.contains('forum_header_border')) {
            body = resp.body;
            break;
          }
        } catch (_) {
          continue;
        }
      }
      if (body == null) continue;

      final doc = html_parser.parse(body);
      for (final row in doc.querySelectorAll('tr.forum_header_border').take(40)) {
        final titleEl = row.querySelector('a.epinfo');
        final title = titleEl?.text.trim() ?? '';
        if (title.isEmpty) continue;

        final magnet = row.querySelector('a.magnet')?.attributes['href'];
        final torrentUrl = row.querySelector('a.download_1')?.attributes['href'];
        final hash = _extractHashFromMagnet(magnet);
        final uid = hash ?? 'eztv-${title.hashCode.abs()}';
        if (!seen.add(uid)) continue;

        final cells = row.querySelectorAll('td.forum_thread_post');
        final sizeText = cells.length >= 4 ? cells[3].text.trim() : '';
        final sizeBytes = _parseHumanSizeToBytes(sizeText);
        final seedsEl = row.querySelector('td.forum_thread_post_end font, td.forum_thread_post_end');
        final seeders = int.tryParse(seedsEl?.text.replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;

        final (quality, tags) = ReleaseParser.parseQuality(title);
        final langs = ReleaseParser.detectLanguages(title, defaultLang: 'EN');
        final (preStatus, preWarn) = ReleaseParser.preScanTitle(title, sizeBytes, seeders);

        out.add(
          TorrentResult(
            id: 'eztv-${uid.substring(0, uid.length >= 12 ? 12 : uid.length).toLowerCase()}',
            title: title,
            quality: quality,
            qualityTags: tags,
            sizeBytes: sizeBytes,
            sizeHuman: sizeBytes > 0
                ? ReleaseParser.formatSize(sizeBytes)
                : (sizeText.isNotEmpty ? sizeText : '—'),
            seeders: seeders,
            leechers: 0,
            detectedLanguages: langs,
            languageMatch: ReleaseParser.matchesAnyLanguage(langs, languages),
            indexer: 'EZTV',
            infoHash: hash,
            torrentUrl: torrentUrl,
            magnetUrl: magnet ?? (hash != null ? buildMagnet(hash, title) : null),
            preScanStatus: preStatus,
            preScanWarnings: preWarn,
          ),
        );
      }
    }
    return out;
  }

  // 6. BitSearch (Pure HTML parser + smart auto-extractor fallback, full catalog)
  Future<List<TorrentResult>> _searchBitSearch(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    const hosts = ['bitsearch.to', 'bitsearch.eu'];
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final q in queries.take(2)) {
      Uri? activeUri;
      String? body;
      for (final host in hosts) {
        try {
          final uri = Uri.https(host, '/search', {'q': q, 'sort': 'seeders'});
          final resp = await http.get(uri, headers: _headers).timeout(_timeout);
          if (resp.statusCode == 200 && resp.body.isNotEmpty) {
            activeUri = uri;
            body = resp.body;
            break;
          }
        } catch (_) {
          continue;
        }
      }
      if (body == null || activeUri == null) continue;

      final doc = html_parser.parse(body);
      final legacyCards = doc.querySelectorAll('li.search-result');
      if (legacyCards.isNotEmpty) {
        for (final card in legacyCards.take(35)) {
          final titleEl = card.querySelector('h5 a');
          final title = titleEl?.text.trim() ?? '';
          if (title.isEmpty) continue;

          final magnet = card.querySelector('a.dl-magnet')?.attributes['href'];
          final dlTorrent = card.querySelector('a.dl-torrent')?.attributes['href'];
          final hash = _extractHashFromMagnet(magnet);
          final uid = hash ?? 'bit-${title.hashCode.abs()}';
          if (!seen.add(uid)) continue;

          final stats = card.querySelectorAll('.stats div');
          var sizeBytes = 0;
          var seeders = 0;
          var leechers = 0;
          if (stats.length >= 4) {
            sizeBytes = _parseHumanSizeToBytes(stats[1].text.trim());
            seeders = int.tryParse(stats[2].text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            leechers = int.tryParse(stats[3].text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          }

          final (quality, tags) = ReleaseParser.parseQuality(title);
          final langs = ReleaseParser.detectLanguages(title);
          final (preStatus, preWarn) = ReleaseParser.preScanTitle(title, sizeBytes, seeders);

          out.add(
            TorrentResult(
              id: 'bit-${uid.substring(0, uid.length >= 12 ? 12 : uid.length).toLowerCase()}',
              title: title,
              quality: quality,
              qualityTags: tags,
              sizeBytes: sizeBytes,
              sizeHuman: ReleaseParser.formatSize(sizeBytes),
              seeders: seeders,
              leechers: leechers,
              detectedLanguages: langs,
              languageMatch: ReleaseParser.matchesAnyLanguage(langs, languages),
              indexer: 'BitSearch',
              infoHash: hash,
              torrentUrl: (dlTorrent != null && dlTorrent.startsWith('http')) ? dlTorrent : null,
              magnetUrl: magnet ?? (hash != null ? buildMagnet(hash, title) : null),
              preScanStatus: preStatus,
              preScanWarnings: preWarn,
            ),
          );
        }
      } else {
        // Fallback to smart generic HTML/2-step extractor for BitSearch's updated layout
        final extracted = await _customSiteService.extractFromResponse(
          config: const CustomSiteConfig(
            id: 'builtin_bitsearch',
            name: 'BitSearch',
            searchUrlTemplate: 'https://bitsearch.to/search?q={query}&sort=seeders',
            followDetailPages: true,
          ),
          pageUri: activeUri,
          body: body,
        );
        for (final item in extracted) {
          final uid = item.infoHash ?? item.id;
          if (seen.add(uid)) out.add(item);
        }
      }
    }
    return out;
  }

  // 7. Nyaa RSS XML — Full catalog (c=0_0: ALL categories, direct `.torrent`)
  Future<List<TorrentResult>> _searchNyaa(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final q in queries.take(2)) {
      final uri = Uri.https('nyaa.si', '/', {'page': 'rss', 'q': q, 'c': '0_0', 'f': '0'});
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) continue;

      final doc = XmlDocument.parse(resp.body);
      for (final item in doc.findAllElements('item').take(40)) {
        final title = item.getElement('title')?.innerText.trim() ?? '';
        if (title.isEmpty) continue;
        final link = item.getElement('link')?.innerText.trim();
        final hash = _firstXmlText(item, 'infoHash')?.toUpperCase();
        final uid = (hash != null && hash.length == 40) ? hash : 'nyaa-${title.hashCode.abs()}';
        if (!seen.add(uid)) continue;

        final seeders = int.tryParse(_firstXmlText(item, 'seeders') ?? '0') ?? 0;
        final leechers = int.tryParse(_firstXmlText(item, 'leechers') ?? '0') ?? 0;
        final sizeStr = _firstXmlText(item, 'size') ?? '';
        final sizeBytes = _parseHumanSizeToBytes(sizeStr);

        final (quality, tags) = ReleaseParser.parseQuality(title);
        final langs = ReleaseParser.detectLanguages(title);
        final (preStatus, preWarn) = ReleaseParser.preScanTitle(title, sizeBytes, seeders);

        out.add(
          TorrentResult(
            id: 'nyaa-${uid.substring(0, uid.length >= 12 ? 12 : uid.length).toLowerCase()}',
            title: title,
            quality: quality,
            qualityTags: tags,
            sizeBytes: sizeBytes,
            sizeHuman: sizeBytes > 0 ? ReleaseParser.formatSize(sizeBytes) : sizeStr,
            seeders: seeders,
            leechers: leechers,
            detectedLanguages: langs,
            languageMatch: ReleaseParser.matchesAnyLanguage(langs, languages),
            indexer: 'Nyaa',
            infoHash: (hash != null && hash.length == 40) ? hash : null,
            torrentUrl: (link != null && link.endsWith('.torrent')) ? link : null,
            magnetUrl: (hash != null && hash.length == 40) ? buildMagnet(hash, title) : null,
            preScanStatus: preStatus,
            preScanWarnings: preWarn,
            publishedAt: item.getElement('pubDate')?.innerText.trim(),
          ),
        );
      }
    }
    return out;
  }

  // 8. SubsPlease JSON API (Direct `.torrent` + magnet)
  Future<List<TorrentResult>> _searchSubsPlease(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final q in queries.take(2)) {
      final uri = Uri.https('subsplease.org', '/api/', {
        'f': 'search',
        'tz': 'UTC',
        's': q,
      });
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) continue;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) continue;

      for (final entry in decoded.entries.take(30)) {
        final item = entry.value;
        if (item is! Map<String, dynamic>) continue;
        final show = (item['show'] ?? entry.key).toString().trim();
        final ep = (item['episode'] ?? '').toString().trim();
        final releaseDate = item['release_date']?.toString();
        final downloads = (item['downloads'] as List? ?? []).whereType<Map<String, dynamic>>();

        for (final dl in downloads) {
          final res = (dl['res'] ?? '').toString().trim();
          final magnet = dl['magnet']?.toString();
          final torrentUrl = dl['torrent']?.toString();
          final hash = _extractHashFromMagnet(magnet);
          final title = '[SubsPlease] $show${ep.isNotEmpty ? ' - $ep' : ''}${res.isNotEmpty ? ' (${res}p)' : ''}';
          final uid = hash ?? 'sp-${title.hashCode.abs()}';
          if (!seen.add(uid)) continue;

          final (quality, tags) = ReleaseParser.parseQuality(title, explicitQuality: '${res}p');
          final langs = ReleaseParser.detectLanguages(title, defaultLang: 'EN');
          final (preStatus, preWarn) = ReleaseParser.preScanTitle(title, 0, 10);

          out.add(
            TorrentResult(
              id: 'sp-${uid.substring(0, uid.length >= 12 ? 12 : uid.length).toLowerCase()}',
              title: title,
              quality: quality,
              qualityTags: tags,
              sizeBytes: 0,
              sizeHuman: '—',
              seeders: 10,
              leechers: 0,
              detectedLanguages: langs,
              languageMatch: ReleaseParser.matchesAnyLanguage(langs, languages),
              indexer: 'SubsPlease',
              infoHash: hash,
              torrentUrl: (torrentUrl != null && torrentUrl.startsWith('http')) ? torrentUrl : null,
              magnetUrl: (magnet != null && magnet.startsWith('magnet:'))
                  ? magnet
                  : (hash != null ? buildMagnet(hash, title) : null),
              preScanStatus: preStatus,
              preScanWarnings: preWarn,
              publishedAt: releaseDate,
            ),
          );
        }
      }
    }
    return out;
  }

  // 9. SolidTorrents Multi-Mirror Full-Catalog JSON API
  Future<List<TorrentResult>> _searchSolidTorrents(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    const hosts = ['solidtorrents.to', 'solidtorrents.eu', 'solidtorrents.net'];
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final q in queries.take(2)) {
      Map<String, dynamic>? decoded;
      for (final host in hosts) {
        try {
          final uri = Uri.https(host, '/api/v1/search', {
            'q': q,
            'sort': 'seeders',
          });
          final resp = await http.get(uri, headers: _headers).timeout(_timeout);
          if (resp.statusCode == 200) {
            decoded = jsonDecode(resp.body) as Map<String, dynamic>;
            break;
          }
        } catch (_) {
          continue;
        }
      }
      if (decoded == null) continue;

      final items = (decoded['results'] as List? ?? []).whereType<Map<String, dynamic>>();
      for (final item in items.take(40)) {
        final title = (item['title'] ?? '').toString().trim();
        final hash = (item['infohash'] ?? '').toString().trim().toUpperCase();
        if (title.isEmpty || hash.length != 40 || !seen.add(hash)) continue;

        final swarm = item['swarm'] as Map<String, dynamic>? ?? const {};
        final sizeBytes = (item['size'] as num?)?.toInt() ?? 0;
        final seeders = (swarm['seeders'] as num?)?.toInt() ?? 0;
        final leechers = (swarm['leechers'] as num?)?.toInt() ?? 0;
        final magnet = item['magnet']?.toString();

        final (quality, tags) = ReleaseParser.parseQuality(title);
        final langs = ReleaseParser.detectLanguages(title);
        final (preStatus, preWarn) = ReleaseParser.preScanTitle(title, sizeBytes, seeders);

        out.add(
          TorrentResult(
            id: 'solid-${hash.substring(0, 12).toLowerCase()}',
            title: title,
            quality: quality,
            qualityTags: tags,
            sizeBytes: sizeBytes,
            sizeHuman: ReleaseParser.formatSize(sizeBytes),
            seeders: seeders,
            leechers: leechers,
            detectedLanguages: langs,
            languageMatch: ReleaseParser.matchesAnyLanguage(langs, languages),
            indexer: 'SolidTorrents',
            infoHash: hash,
            torrentUrl: null,
            magnetUrl: (magnet != null && magnet.startsWith('magnet:'))
                ? magnet
                : buildMagnet(hash, title),
            preScanStatus: preStatus,
            preScanWarnings: preWarn,
            publishedAt: item['imported']?.toString(),
          ),
        );
      }
    }
    return out;
  }

  // 10. LimeTorrents Multi-Mirror RSS XML — Full catalog
  Future<List<TorrentResult>> _searchLimeTorrents(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    const mirrors = [
      'https://www.limetorrents.lol',
      'https://www.limetorrents.cc',
      'https://www.limetorrents.fun',
    ];
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final q in queries.take(2)) {
      String? xmlBody;
      for (final mirror in mirrors) {
        try {
          final uri = Uri.parse('$mirror/searchrss/${Uri.encodeComponent(q)}/');
          final resp = await http.get(uri, headers: _headers).timeout(_timeout);
          if (resp.statusCode == 200 && resp.body.contains('<item>')) {
            xmlBody = resp.body;
            break;
          }
        } catch (_) {
          continue;
        }
      }
      if (xmlBody == null) continue;

      final doc = XmlDocument.parse(xmlBody);
      for (final item in doc.findAllElements('item').take(35)) {
        final title = item.getElement('title')?.innerText.trim() ?? '';
        if (title.isEmpty) continue;
        final enc = item.getElement('enclosure');
        final torrentUrl = enc?.getAttribute('url');
        final sizeBytes = int.tryParse(enc?.getAttribute('length') ?? '0') ?? 0;
        final descr = item.getElement('description')?.innerText ?? '';
        final seedsMatch = RegExp(r'Seeds:\s*(\d+)', caseSensitive: false).firstMatch(descr);
        final leechMatch = RegExp(r'Leechers:\s*(\d+)', caseSensitive: false).firstMatch(descr);
        final seeders = int.tryParse(seedsMatch?.group(1) ?? '0') ?? 0;
        final leechers = int.tryParse(leechMatch?.group(1) ?? '0') ?? 0;

        final hashMatch = RegExp(r'([0-9A-Fa-f]{40})\.torrent').firstMatch(torrentUrl ?? '');
        final hash = hashMatch?.group(1)?.toUpperCase();
        final uid = hash ?? 'lime-${title.hashCode.abs()}';
        if (!seen.add(uid)) continue;

        final (quality, tags) = ReleaseParser.parseQuality(title);
        final langs = ReleaseParser.detectLanguages(title);
        final (preStatus, preWarn) = ReleaseParser.preScanTitle(title, sizeBytes, seeders);

        out.add(
          TorrentResult(
            id: 'lime-${uid.substring(0, uid.length >= 12 ? 12 : uid.length).toLowerCase()}',
            title: title,
            quality: quality,
            qualityTags: tags,
            sizeBytes: sizeBytes,
            sizeHuman: ReleaseParser.formatSize(sizeBytes),
            seeders: seeders,
            leechers: leechers,
            detectedLanguages: langs,
            languageMatch: ReleaseParser.matchesAnyLanguage(langs, languages),
            indexer: 'LimeTorrents',
            infoHash: hash,
            torrentUrl: (torrentUrl != null && torrentUrl.startsWith('http')) ? torrentUrl : null,
            magnetUrl: hash != null ? buildMagnet(hash, title) : null,
            preScanStatus: preStatus,
            preScanWarnings: preWarn,
            publishedAt: item.getElement('pubDate')?.innerText.trim(),
          ),
        );
      }
    }
    return out;
  }

  // 11. Internet Archive — Full catalog (Movies, Books, Music, Software, Archives with BitTorrent)
  Future<List<TorrentResult>> _searchArchiveOrg(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    if (queries.isEmpty) return [];
    final cleanQ = queries.first.replaceAll('"', '').trim();
    if (cleanQ.isEmpty) return [];

    final lucene = '($cleanQ) AND format:BitTorrent';
    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': lucene,
      'fl[]': ['identifier', 'title', 'year', 'mediatype', 'item_size', 'downloads', 'language'],
      'sort[]': 'downloads desc',
      'rows': '15',
      'page': '1',
      'output': 'json',
    });

    final resp = await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) return [];
    final docs =
        ((jsonDecode(resp.body) as Map<String, dynamic>)['response'] as Map?)?['docs'] as List? ??
            [];

    final out = <TorrentResult>[];
    for (final doc in docs.whereType<Map<String, dynamic>>()) {
      final id = (doc['identifier'] ?? '').toString().trim();
      final title = (doc['title'] ?? id).toString().trim();
      if (id.isEmpty) continue;

      final docYear = doc['year']?.toString();
      final mediaKind = (doc['mediatype'] ?? '').toString().trim();
      final fullTitle = docYear != null ? '$title ($docYear)' : title;
      final sizeBytes = (doc['item_size'] as num?)?.toInt() ?? 0;
      final downloads = (doc['downloads'] as num?)?.toInt() ?? 0;
      final seeds = (downloads ~/ 500 + 1).clamp(1, 50);

      String defaultLang = 'EN';
      final rawLang = doc['language'];
      final langStr = rawLang is List && rawLang.isNotEmpty
          ? rawLang.first.toString().toLowerCase()
          : rawLang?.toString().toLowerCase() ?? '';
      if (langStr.contains('fr')) {
        defaultLang = 'FR';
      } else if (langStr.contains('es') || langStr.contains('spa')) {
        defaultLang = 'ES';
      } else if (langStr.contains('de') || langStr.contains('ger')) {
        defaultLang = 'DE';
      } else if (langStr.contains('nl') || langStr.contains('dut')) {
        defaultLang = 'NL';
      } else if (langStr.contains('it')) {
        defaultLang = 'IT';
      }

      final langs = ReleaseParser.detectLanguages(fullTitle, defaultLang: defaultLang);
      var (quality, tags) = ReleaseParser.parseQuality(fullTitle);
      if (quality == 'Standard') {
        quality = mediaKind.isNotEmpty ? 'Archive ($mediaKind)' : 'Archive';
      }
      final (preStatus, preWarn) = ReleaseParser.preScanTitle(fullTitle, sizeBytes, seeds);

      out.add(
        TorrentResult(
          id: 'ia-${id.length > 24 ? id.substring(0, 24) : id}',
          title: fullTitle,
          quality: quality,
          qualityTags: tags.isEmpty ? const ['Archive'] : tags,
          sizeBytes: sizeBytes,
          sizeHuman: ReleaseParser.formatSize(sizeBytes),
          seeders: seeds,
          leechers: 0,
          detectedLanguages: langs,
          languageMatch: ReleaseParser.matchesAnyLanguage(langs, languages),
          indexer: 'Internet Archive',
          sourceId: id,
          torrentUrl: 'https://archive.org/download/$id/${id}_archive.torrent',
          preScanStatus: preStatus,
          preScanWarnings: preWarn,
          publishedAt: docYear,
        ),
      );
    }
    return out;
  }

  // 12. Optional Torznab XML (Jackett / Prowlarr — full catalog, no category lock!)
  Future<List<TorrentResult>> _searchTorznab(
    TorznabConfig config,
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final q in queries.take(3)) {
      final base = Uri.tryParse(config.baseUrl);
      if (base == null) continue;
      final uri = base.replace(queryParameters: {
        ...base.queryParameters,
        't': 'search',
        'q': q,
        if (config.apiKey.isNotEmpty) 'apikey': config.apiKey,
      });

      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) continue;

      final doc = XmlDocument.parse(resp.body);
      var idx = 0;
      for (final item in doc.findAllElements('item').take(60)) {
        idx++;
        final title = item.getElement('title')?.innerText.trim() ?? '';
        if (title.isEmpty) continue;

        final description = item.getElement('description')?.innerText.trim();
        final link = item.getElement('link')?.innerText.trim();
        final enc = item.getElement('enclosure');
        final rawLink = (link != null && link.isNotEmpty) ? link : enc?.getAttribute('url');

        final sizeBytes = int.tryParse(
              item.getElement('size')?.innerText.trim() ?? enc?.getAttribute('length') ?? '0',
            ) ??
            0;

        final attrs = <String, String>{};
        for (final attr in item.findElements('attr', namespace: '*')) {
          final k = attr.getAttribute('name')?.toLowerCase();
          final v = attr.getAttribute('value');
          if (k != null && v != null) attrs[k] = v;
        }

        final seeders = int.tryParse(attrs['seeders'] ?? '0') ?? 0;
        final peers = int.tryParse(attrs['peers'] ?? '0') ?? 0;
        final leechers = peers >= seeders ? peers - seeders : peers;
        final infoHash = attrs['infohash']?.toUpperCase();
        var magnet = attrs['magneturl'] ??
            (rawLink != null && rawLink.startsWith('magnet:') ? rawLink : null);
        if (magnet == null && infoHash != null && infoHash.length == 40) {
          magnet = buildMagnet(infoHash, title);
        }
        final torrentUrl =
            rawLink != null && (rawLink.startsWith('http://') || rawLink.startsWith('https://'))
                ? rawLink
                : null;

        final uid = infoHash ?? '${config.id}-$idx-$title';
        if (!seen.add(uid)) continue;

        final (quality, tags) = ReleaseParser.parseQuality(title);
        final langs = ReleaseParser.detectLanguages(title);
        final (preStatus, preWarn) = ReleaseParser.preScanTitle(title, sizeBytes, seeders);

        out.add(
          TorrentResult(
            id: 'tz-${uid.hashCode.abs()}',
            title: title,
            quality: quality,
            qualityTags: tags,
            sizeBytes: sizeBytes,
            sizeHuman: ReleaseParser.formatSize(sizeBytes),
            seeders: seeders,
            leechers: leechers,
            detectedLanguages: langs,
            languageMatch: ReleaseParser.matchesAnyLanguage(langs, languages),
            indexer: 'Torznab: ${config.name}',
            nfoText: (description != null && description.isNotEmpty) ? description : null,
            infoHash: infoHash,
            torrentUrl: torrentUrl,
            magnetUrl: magnet,
            preScanStatus: preStatus,
            preScanWarnings: preWarn,
          ),
        );
      }
    }
    return out;
  }

  static String? _extractHashFromMagnet(String? magnet) {
    if (magnet == null) return null;
    final m = RegExp(r'btih:([0-9a-fA-F]{40})').firstMatch(magnet);
    return m?.group(1)?.toUpperCase();
  }

  static String? _firstXmlText(XmlElement item, String tagName) {
    final matches = item.findElements(tagName, namespace: '*');
    if (matches.isEmpty) return null;
    final text = matches.first.innerText.trim();
    return text.isEmpty ? null : text;
  }
}
