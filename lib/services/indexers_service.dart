import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/services/release_parser.dart';
import 'package:xml/xml.dart';

class SearchSummary {
  const SearchSummary({
    required this.results,
    required this.indexersQueried,
    required this.errors,
  });

  final List<TorrentResult> results;
  final List<String> indexersQueried;
  final Map<String, String> errors;
}

/// Parallel on-device torrent search aggregator (pure HTTP JSON/XML — zero ads, zero JS).
///
/// Built-in ad-free sources:
/// 1. YTS (JSON API — direct `.torrent` URLs)
/// 2. APIBay (JSON API — real NFO via `t.php`)
/// 3. Knaben (JSON API — multi-tracker aggregator: 1337x, TPB, TGx, RuTracker...)
/// 4. TorrentCSV (open-source JSON API)
/// 5. SolidTorrents (JSON API)
/// 6. Internet Archive (JSON API — public domain classics + `.torrent` / `.nfo`)
/// 7. Optional Torznab XML (Jackett / Prowlarr)
class IndexersService {
  static const Duration _timeout = Duration(seconds: 12);
  static const Map<String, String> _headers = {
    'User-Agent': 'SafeTorrent/1.3 (Standalone)',
  };

  static const List<String> _publicTrackers = [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://tracker.openbittorrent.com:6969/announce',
  ];

  static String buildMagnet(String infoHash, String title) {
    final cleanHash = infoHash.trim().toUpperCase();
    final dn = Uri.encodeQueryComponent(title);
    final tr = _publicTrackers.map((t) => '&tr=${Uri.encodeQueryComponent(t)}').join();
    return 'magnet:?xt=urn:btih:$cleanHash&dn=$dn$tr';
  }

  Future<SearchSummary> search({
    required String query,
    List<String> extraTitles = const [],
    Set<LanguageFilter> languages = const {LanguageFilter.all},
    int? year,
    bool includeAllLanguages = true,
    required AppSettings settings,
  }) async {
    final seenQ = <String>{};
    final queries = <String>[];
    for (final raw in [query, ...extraTitles]) {
      final clean = raw.trim();
      if (clean.isNotEmpty && seenQ.add(clean.toLowerCase())) {
        queries.add(clean);
      }
    }

    final effectiveLangs = includeAllLanguages || languages.isEmpty
        ? const {LanguageFilter.all}
        : languages;

    final tasks = <Future<(String, List<TorrentResult>, String?)>>[];
    final queriedNames = <String>[];

    if (settings.enableYts) {
      queriedNames.add('YTS');
      tasks.add(_safeRun('YTS', () => _searchYts(queries, effectiveLangs, year)));
    }
    if (settings.enableApibay) {
      queriedNames.add('APIBay');
      tasks.add(_safeRun('APIBay', () => _searchApibay(queries, effectiveLangs, year)));
    }
    if (settings.enableKnaben) {
      queriedNames.add('Knaben');
      tasks.add(_safeRun('Knaben', () => _searchKnaben(queries, effectiveLangs)));
    }
    if (settings.enableTorrentCsv) {
      queriedNames.add('TorrentCSV');
      tasks.add(_safeRun('TorrentCSV', () => _searchTorrentCsv(queries, effectiveLangs)));
    }
    if (settings.enableSolidTorrents) {
      queriedNames.add('SolidTorrents');
      tasks.add(_safeRun('SolidTorrents', () => _searchSolidTorrents(queries, effectiveLangs)));
    }
    if (settings.enableArchiveOrg) {
      queriedNames.add('Internet Archive');
      tasks.add(
        _safeRun('Internet Archive', () => _searchArchiveOrg(queries, effectiveLangs, year)),
      );
    }
    for (final tz in settings.torznabIndexers.where((c) => c.enabled)) {
      final label = 'Torznab: ${tz.name}';
      queriedNames.add(label);
      tasks.add(_safeRun(label, () => _searchTorznab(tz, queries, effectiveLangs, year)));
    }

    final batches = await Future.wait(tasks);
    final errors = <String, String>{};
    final deduped = <String, TorrentResult>{};

    for (final (name, items, err) in batches) {
      if (err != null) {
        errors[name] = err;
        continue;
      }
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

  // -------------------------------------------------------------------
  // 1. YTS JSON API (Direct `.torrent` URLs + technical NFO metadata)
  // -------------------------------------------------------------------
  Future<List<TorrentResult>> _searchYts(
    List<String> queries,
    Set<LanguageFilter> languages,
    int? year,
  ) async {
    const mirrors = [
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
            'limit': '15',
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
        final movieYear = (movie['year'] as num?)?.toInt();
        if (year != null && movieYear != null && (movieYear - year).abs() > 1) continue;
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
            'Qualité     : $qStr ($typeStr)',
            if (vCodec.isNotEmpty)
              'Vidéo       : $vCodec${bitDepth.isNotEmpty ? ' ($bitDepth-bit)' : ''}',
            if (audioCh.isNotEmpty) 'Audio       : $audioCh canaux ($defaultLang)',
            'Taille      : ${t['size'] ?? ReleaseParser.formatSize(sizeBytes)}',
            'Date upload : ${t['date_uploaded'] ?? '—'}',
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

  // -------------------------------------------------------------------
  // 2. APIBay Pure JSON API (FR / EN / ES Movies + real NFO via t.php)
  // -------------------------------------------------------------------
  Future<List<TorrentResult>> _searchApibay(
    List<String> queries,
    Set<LanguageFilter> languages,
    int? year,
  ) async {
    final terms = _expandMultiTitleQueries(queries, year);
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final term in terms.take(4)) {
      try {
        final uri = Uri.https('apibay.org', '/q.php', {'q': term, 'cat': '200'});
        final resp = await http.get(uri, headers: _headers).timeout(_timeout);
        if (resp.statusCode != 200) continue;
        final items = jsonDecode(resp.body);
        if (items is! List) continue;

        for (final item in items.whereType<Map<String, dynamic>>().take(30)) {
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
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  // -------------------------------------------------------------------
  // 3. Knaben JSON API (Aggregates 1337x, TPB, TGx, RuTracker, LimeTorrents...)
  // -------------------------------------------------------------------
  Future<List<TorrentResult>> _searchKnaben(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    final out = <TorrentResult>[];
    final seen = <String>{};
    final uri = Uri.parse('https://api.knaben.org/v1');

    for (final q in queries.take(3)) {
      try {
        final body = jsonEncode({
          'search_type': '100%',
          'search_field': 'title',
          'query': q,
          'order_by': 'seeders',
          'order_direction': 'desc',
          'categories': [2000000], // Movies
          'from': 0,
          'size': 35,
          'hide_unsafe': true,
          'hide_xxx': true,
        });
        final resp = await http
            .post(
              uri,
              headers: {
                ..._headers,
                'Content-Type': 'application/json',
              },
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
          final link = hit['link']?.toString();
          final torrentUrl =
              link != null && link.startsWith('http') && link.toLowerCase().contains('.torrent')
                  ? link
                  : null;

          final (quality, tags) = ReleaseParser.parseQuality(title);
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
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  // -------------------------------------------------------------------
  // 4. TorrentCSV Open-Source JSON API
  // -------------------------------------------------------------------
  Future<List<TorrentResult>> _searchTorrentCsv(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final q in queries.take(3)) {
      try {
        final uri = Uri.https('torrents-csv.com', '/service/search', {
          'q': q,
          'size': '30',
        });
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
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  // -------------------------------------------------------------------
  // 5. SolidTorrents Public JSON API
  // -------------------------------------------------------------------
  Future<List<TorrentResult>> _searchSolidTorrents(
    List<String> queries,
    Set<LanguageFilter> languages,
  ) async {
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final q in queries.take(3)) {
      try {
        final uri = Uri.https('solidtorrents.to', '/api/v1/search', {
          'q': q,
          'category': 'video',
          'sort': 'seeders',
        });
        final resp = await http.get(uri, headers: _headers).timeout(_timeout);
        if (resp.statusCode != 200) continue;
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final items = (decoded['results'] as List? ?? []).whereType<Map<String, dynamic>>();

        for (final item in items.take(25)) {
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
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  // -------------------------------------------------------------------
  // 6. Internet Archive (Public Domain / Classic Films + .nfo support)
  // -------------------------------------------------------------------
  Future<List<TorrentResult>> _searchArchiveOrg(
    List<String> queries,
    Set<LanguageFilter> languages,
    int? year,
  ) async {
    if (queries.isEmpty) return [];
    final cleanQ = queries.first.replaceAll('"', '').trim();
    if (cleanQ.isEmpty) return [];

    var lucene = 'title:("$cleanQ") AND mediatype:(movies)';
    if (year != null) lucene += ' AND year:($year)';

    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': lucene,
      'fl[]': ['identifier', 'title', 'year', 'item_size', 'downloads', 'language'],
      'sort[]': 'downloads desc',
      'rows': '8',
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
      }

      final langs = ReleaseParser.detectLanguages(fullTitle, defaultLang: defaultLang);
      var (quality, tags) = ReleaseParser.parseQuality(fullTitle);
      if (quality == 'Standard') quality = 'Archive HD/SD';
      final (preStatus, preWarn) = ReleaseParser.preScanTitle(fullTitle, sizeBytes, seeds);

      out.add(
        TorrentResult(
          id: 'ia-${id.length > 24 ? id.substring(0, 24) : id}',
          title: fullTitle,
          quality: quality,
          qualityTags: tags.isEmpty ? const ['Domaine Public'] : tags,
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

  // -------------------------------------------------------------------
  // 7. Optional Torznab XML (Jackett / Prowlarr)
  // -------------------------------------------------------------------
  Future<List<TorrentResult>> _searchTorznab(
    TorznabConfig config,
    List<String> queries,
    Set<LanguageFilter> languages,
    int? year,
  ) async {
    final out = <TorrentResult>[];
    final seen = <String>{};

    for (final q in queries.take(3)) {
      final base = Uri.tryParse(config.baseUrl);
      if (base == null) continue;
      final uri = base.replace(queryParameters: {
        ...base.queryParameters,
        't': 'movie',
        'q': year != null ? '$q $year' : q,
        'cat': '2000',
        if (config.apiKey.isNotEmpty) 'apikey': config.apiKey,
      });

      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) continue;

      final doc = XmlDocument.parse(resp.body);
      var idx = 0;
      for (final item in doc.findAllElements('item').take(40)) {
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

  static List<String> _expandMultiTitleQueries(List<String> queries, int? year) {
    final raw = <String>[];
    final suffix = year != null ? ' $year' : '';
    for (final q in queries) {
      raw.add('$q$suffix');
      if (suffix.isNotEmpty) raw.add(q);
    }
    if (queries.isNotEmpty) {
      raw.add('${queries.first} FRENCH');
    }
    final seen = <String>{};
    return raw.where((t) => seen.add(t.toLowerCase().trim())).toList();
  }

  static String? _extractHashFromMagnet(String? magnet) {
    if (magnet == null) return null;
    final m = RegExp(r'btih:([0-9a-fA-F]{40})').firstMatch(magnet);
    return m?.group(1)?.toUpperCase();
  }
}
