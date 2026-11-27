import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/services/release_parser.dart';
import 'package:xml/xml.dart';

class CustomSiteTestResult {
  const CustomSiteTestResult({
    required this.results,
    this.httpStatus,
    this.error,
  });

  final List<TorrentResult> results;
  final int? httpStatus;
  final String? error;
}

/// Pure-HTTP generic torrent search extractor for user-configured websites.
///
/// Works like Cardigann / qBittorrent search plugins without executing any
/// browser engine or JavaScript:
/// - Supports `{query}`, `{query_plus}`, and `{query_dash}` URL placeholders
/// - Auto-detects RSS/Atom XML, JSON APIs, and standard HTML result lists/tables
/// - Supports optional CSS selectors (`row`, `title`, `link`, `size`, `seeders`)
/// - Supports optional 2-step extraction (`followDetailPages`) for sites where
///   magnet or `.torrent` links are only present on the detail page.
/// - Respects anti-bot / CAPTCHA pages (never attempts to bypass them).
class CustomSiteService {
  static const Duration _timeout = Duration(seconds: 12);
  static const int _maxDetailPages = 8;
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml,application/json;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,fr;q=0.8',
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

  /// Expands `{query}`, `{query_plus}`, `{query_dash}` in [template].
  /// If no placeholder is present, appends `?q=<encoded>` (or `&q=<encoded>`).
  static Uri? buildSearchUri(String template, String query) {
    final cleanTemplate = template.trim();
    final cleanQuery = query.trim();
    if (cleanTemplate.isEmpty || cleanQuery.isEmpty) return null;

    final encoded = Uri.encodeComponent(cleanQuery);
    final plus = Uri.encodeQueryComponent(cleanQuery);
    final dash = Uri.encodeComponent(cleanQuery.replaceAll(RegExp(r'\s+'), '-'));

    String built;
    if (cleanTemplate.contains('{query}') ||
        cleanTemplate.contains('{query_plus}') ||
        cleanTemplate.contains('{query_dash}')) {
      built = cleanTemplate
          .replaceAll('{query}', encoded)
          .replaceAll('{query_plus}', plus)
          .replaceAll('{query_dash}', dash);
    } else {
      final sep = cleanTemplate.contains('?') ? '&' : '?';
      built = '$cleanTemplate${sep}q=$plus';
    }

    final uri = Uri.tryParse(built);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  Future<List<TorrentResult>> searchSite(
    CustomSiteConfig config,
    String query,
  ) async {
    final res = await testSite(config, testQuery: query);
    if (res.error != null) {
      throw Exception(res.error);
    }
    return res.results;
  }

  Future<CustomSiteTestResult> testSite(
    CustomSiteConfig config, {
    String testQuery = 'ubuntu',
  }) async {
    final uri = buildSearchUri(config.searchUrlTemplate, testQuery);
    if (uri == null) {
      return const CustomSiteTestResult(
        results: [],
        error: 'Invalid search URL template (must start with http:// or https://).',
      );
    }

    try {
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode == 403 || resp.statusCode == 503) {
        return CustomSiteTestResult(
          results: const [],
          httpStatus: resp.statusCode,
          error: 'HTTP ${resp.statusCode} (site blocked or anti-bot protected).',
        );
      }
      if (resp.statusCode >= 400) {
        return CustomSiteTestResult(
          results: const [],
          httpStatus: resp.statusCode,
          error: 'HTTP ${resp.statusCode}',
        );
      }

      final body = resp.body;
      final results = await extractFromResponse(
        config: config,
        pageUri: uri,
        body: body,
        contentType: resp.headers['content-type'] ?? '',
      );
      return CustomSiteTestResult(results: results, httpStatus: resp.statusCode);
    } catch (e) {
      return CustomSiteTestResult(results: const [], error: '$e');
    }
  }

  /// Pure parser entry point (also directly unit-testable without network!).
  Future<List<TorrentResult>> extractFromResponse({
    required CustomSiteConfig config,
    required Uri pageUri,
    required String body,
    String contentType = '',
    Future<String?> Function(Uri detailUri)? detailFetcher,
  }) async {
    final trimmed = body.trimLeft();
    final ct = contentType.toLowerCase();

    // 1. JSON API response
    if (ct.contains('json') || trimmed.startsWith('{') || trimmed.startsWith('[')) {
      final fromJson = _extractFromJson(config, trimmed);
      if (fromJson.isNotEmpty) return fromJson;
    }

    // 2. RSS / Atom XML feed
    if (ct.contains('xml') ||
        trimmed.startsWith('<?xml') ||
        trimmed.startsWith('<rss') ||
        trimmed.startsWith('<feed')) {
      final fromXml = _extractFromXml(config, pageUri, trimmed);
      if (fromXml.isNotEmpty) return fromXml;
    }

    // 3. HTML search page (1-step direct extraction, with optional 2-step detail follow)
    final direct = extractFromHtml(config: config, pageUri: pageUri, htmlBody: body);
    if (direct.isNotEmpty || !config.followDetailPages) {
      return direct;
    }

    // 4. Optional 2-step extraction: follow candidate detail links from the listing page
    final detailLinks = _extractCandidateDetailLinks(config, pageUri, body);
    if (detailLinks.isEmpty) return const [];

    final fetcher = detailFetcher ?? _defaultFetchHtml;
    final fetched = await Future.wait(
      detailLinks.take(_maxDetailPages).map((entry) async {
        final html = await fetcher(entry.$1);
        if (html == null || html.isEmpty) return null;
        return _extractSingleDetailPage(
          config: config,
          detailUri: entry.$1,
          fallbackTitle: entry.$2,
          fallbackSize: entry.$3,
          fallbackSeeders: entry.$4,
          htmlBody: html,
        );
      }),
    );

    final out = <TorrentResult>[];
    final seen = <String>{};
    for (final item in fetched.whereType<TorrentResult>()) {
      final key = (item.infoHash ?? item.torrentUrl ?? item.title).toLowerCase();
      if (seen.add(key)) out.add(item);
    }
    return out;
  }

  Future<String?> _defaultFetchHtml(Uri uri) async {
    try {
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode == 200) return resp.body;
    } catch (_) {
      // ignore individual detail page failure
    }
    return null;
  }

  /// Synchronous HTML 1-step extractor supporting both custom CSS selectors and
  /// smart zero-config extraction.
  List<TorrentResult> extractFromHtml({
    required CustomSiteConfig config,
    required Uri pageUri,
    required String htmlBody,
  }) {
    final doc = html_parser.parse(htmlBody);
    final out = <TorrentResult>[];
    final seen = <String>{};

    // Case A: User provided an explicit rowSelector (Cardigann style)
    if (config.rowSelector.isNotEmpty) {
      final rows = _safeQueryAll(doc, config.rowSelector);
      for (final row in rows.take(60)) {
        final item = _parseRowElement(config, pageUri, row);
        if (item == null) continue;
        final key = (item.infoHash ?? item.torrentUrl ?? item.title).toLowerCase();
        if (seen.add(key)) out.add(item);
      }
      if (out.isNotEmpty) return out;
    }

    // Case B: Smart Auto-Extraction around magnet: or .torrent links
    final linkNodes = doc.querySelectorAll('a[href]');
    for (final a in linkNodes) {
      final href = (a.attributes['href'] ?? '').trim();
      final isMagnet = href.startsWith('magnet:?');
      final isTorrent = _looksLikeTorrentUrl(href);
      if (!isMagnet && !isTorrent) continue;

      final container = _findRowContainer(a) ?? a.parent ?? a;
      final item = _parseRowElement(config, pageUri, container, forcedLinkHref: href);
      if (item == null) continue;
      final key = (item.infoHash ?? item.torrentUrl ?? item.title).toLowerCase();
      if (seen.add(key)) out.add(item);
      if (out.length >= 60) break;
    }

    return out;
  }

  TorrentResult? _parseRowElement(
    CustomSiteConfig config,
    Uri pageUri,
    dom.Element row, {
    String? forcedLinkHref,
  }) {
    String? magnet;
    String? torrentUrl;
    String? infoHash;

    if (forcedLinkHref != null) {
      if (forcedLinkHref.startsWith('magnet:?')) {
        magnet = forcedLinkHref;
      } else if (_looksLikeTorrentUrl(forcedLinkHref)) {
        torrentUrl = _resolveUrl(pageUri, forcedLinkHref);
      }
    }

    if (config.linkSelector.isNotEmpty) {
      final customLink = _safeQueryOne(row, config.linkSelector);
      final href = customLink?.attributes['href']?.trim() ?? '';
      if (href.startsWith('magnet:?')) {
        magnet ??= href;
      } else if (_looksLikeTorrentUrl(href)) {
        torrentUrl ??= _resolveUrl(pageUri, href);
      }
    }

    for (final a in row.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').trim();
      if (magnet == null && href.startsWith('magnet:?')) {
        magnet = href;
      } else if (torrentUrl == null && _looksLikeTorrentUrl(href)) {
        torrentUrl = _resolveUrl(pageUri, href);
      }
      if (infoHash == null) {
        final h = _extractHash(href);
        if (h != null) infoHash = h;
      }
    }

    infoHash ??= _extractHash(magnet ?? '') ??
        _extractHash(torrentUrl ?? '') ??
        _extractHash(row.outerHtml);

    if (magnet == null && torrentUrl == null && infoHash == null) {
      return null;
    }

    // Extract title
    String title = '';
    if (config.titleSelector.isNotEmpty) {
      title = _safeQueryOne(row, config.titleSelector)?.text.trim() ?? '';
    }
    if (title.isEmpty) {
      title = _guessTitleFromRow(row, magnet);
    }
    if (title.isEmpty) return null;

    magnet ??= (infoHash != null ? buildMagnet(infoHash, title) : null);

    // Extract size
    var sizeBytes = 0;
    if (config.sizeSelector.isNotEmpty) {
      final szTxt = _safeQueryOne(row, config.sizeSelector)?.text.trim() ?? '';
      sizeBytes = parseHumanSizeToBytes(szTxt);
    }
    if (sizeBytes == 0) {
      sizeBytes = parseHumanSizeToBytes(row.text);
    }

    // Extract seeders
    var seeders = 0;
    if (config.seedersSelector.isNotEmpty) {
      final sTxt = _safeQueryOne(row, config.seedersSelector)?.text ?? '';
      seeders = int.tryParse(sTxt.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    } else {
      seeders = _guessSeedersFromRow(row);
    }

    return _buildResult(
      siteName: config.name,
      title: title,
      sizeBytes: sizeBytes,
      seeders: seeders,
      leechers: 0,
      infoHash: infoHash,
      torrentUrl: torrentUrl,
      magnetUrl: magnet,
    );
  }

  List<(Uri, String, int, int)> _extractCandidateDetailLinks(
    CustomSiteConfig config,
    Uri pageUri,
    String htmlBody,
  ) {
    final doc = html_parser.parse(htmlBody);
    final out = <(Uri, String, int, int)>[];
    final seen = <String>{};

    final rows = config.rowSelector.isNotEmpty
        ? _safeQueryAll(doc, config.rowSelector)
        : doc.querySelectorAll('tr, li, article');

    for (final row in rows) {
      dom.Element? linkEl;
      if (config.linkSelector.isNotEmpty) {
        linkEl = _safeQueryOne(row, config.linkSelector);
      } else {
        for (final a in row.querySelectorAll('a[href]')) {
          final href = (a.attributes['href'] ?? '').trim();
          final text = a.text.trim();
          if (text.length < 4) continue;
          if (href.startsWith('#') ||
              href.startsWith('javascript:') ||
              href.startsWith('mailto:')) {
            continue;
          }
          if (RegExp(r'/(torrent|torrents|t|details|view|download|info|file)/', caseSensitive: false)
                  .hasMatch(href) ||
              href.endsWith('.html')) {
            linkEl = a;
            break;
          }
        }
      }

      if (linkEl == null) continue;
      final resolvedStr = _resolveUrl(pageUri, linkEl.attributes['href'] ?? '');
      if (resolvedStr == null) continue;
      final resolvedUri = Uri.tryParse(resolvedStr);
      if (resolvedUri == null || resolvedUri.host != pageUri.host) continue;
      if (!seen.add(resolvedStr)) continue;

      final title = config.titleSelector.isNotEmpty
          ? (_safeQueryOne(row, config.titleSelector)?.text.trim() ?? linkEl.text.trim())
          : linkEl.text.trim();
      final sizeBytes = config.sizeSelector.isNotEmpty
          ? parseHumanSizeToBytes(_safeQueryOne(row, config.sizeSelector)?.text ?? '')
          : parseHumanSizeToBytes(row.text);
      final seeders = config.seedersSelector.isNotEmpty
          ? (int.tryParse(
                  (_safeQueryOne(row, config.seedersSelector)?.text ?? '')
                      .replaceAll(RegExp(r'[^0-9]'), ''),
                ) ??
                0)
          : _guessSeedersFromRow(row);

      out.add((resolvedUri, title, sizeBytes, seeders));
      if (out.length >= _maxDetailPages) break;
    }

    return out;
  }

  TorrentResult? _extractSingleDetailPage({
    required CustomSiteConfig config,
    required Uri detailUri,
    required String fallbackTitle,
    required int fallbackSize,
    required int fallbackSeeders,
    required String htmlBody,
  }) {
    final doc = html_parser.parse(htmlBody);
    String? magnet;
    String? torrentUrl;
    String? infoHash;

    for (final a in doc.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').trim();
      if (magnet == null && href.startsWith('magnet:?')) {
        magnet = href;
      } else if (torrentUrl == null && _looksLikeTorrentUrl(href)) {
        torrentUrl = _resolveUrl(detailUri, href);
      }
    }

    if (magnet == null) {
      final magMatch = RegExp(r'magnet:\?xt=urn:btih:[A-Za-z0-9]{32,40}[^"\x27\s<>]*')
          .firstMatch(htmlBody);
      if (magMatch != null) magnet = magMatch.group(0);
    }

    infoHash = _extractHash(magnet ?? '') ?? _extractHash(torrentUrl ?? '');
    if (magnet == null && torrentUrl == null && infoHash == null) return null;

    var title = fallbackTitle.trim();
    if (title.isEmpty) {
      title = doc.querySelector('h1')?.text.trim() ??
          doc.querySelector('title')?.text.trim() ??
          _extractDnFromMagnet(magnet) ??
          'Torrent';
    }
    magnet ??= (infoHash != null ? buildMagnet(infoHash, title) : null);

    final sizeBytes = fallbackSize > 0 ? fallbackSize : parseHumanSizeToBytes(doc.body?.text ?? '');

    return _buildResult(
      siteName: config.name,
      title: title,
      sizeBytes: sizeBytes,
      seeders: fallbackSeeders,
      leechers: 0,
      infoHash: infoHash,
      torrentUrl: torrentUrl,
      magnetUrl: magnet,
    );
  }

  List<TorrentResult> _extractFromXml(CustomSiteConfig config, Uri pageUri, String xmlBody) {
    final out = <TorrentResult>[];
    final seen = <String>{};
    try {
      final doc = XmlDocument.parse(xmlBody);
      for (final item in doc.findAllElements('item').take(50)) {
        final title = item.getElement('title')?.innerText.trim() ?? '';
        if (title.isEmpty) continue;
        final link = item.getElement('link')?.innerText.trim();
        final enc = item.getElement('enclosure');
        final encUrl = enc?.getAttribute('url')?.trim();
        final descr = item.getElement('description')?.innerText ?? '';

        String? magnet;
        String? torrentUrl;
        for (final cand in [link, encUrl]) {
          if (cand == null || cand.isEmpty) continue;
          if (cand.startsWith('magnet:?')) {
            magnet ??= cand;
          } else if (_looksLikeTorrentUrl(cand)) {
            torrentUrl ??= _resolveUrl(pageUri, cand);
          }
        }
        final hash = _extractHash(magnet ?? '') ??
            _extractHash(torrentUrl ?? '') ??
            _extractHash(item.innerXml);
        if (magnet == null && torrentUrl == null && hash == null) continue;
        magnet ??= (hash != null ? buildMagnet(hash, title) : null);

        final key = (hash ?? torrentUrl ?? title).toLowerCase();
        if (!seen.add(key)) continue;

        final sizeBytes = int.tryParse(enc?.getAttribute('length') ?? '0') ??
            parseHumanSizeToBytes(descr);
        final seedsM = RegExp(r'seed(?:er)?s?\s*[:=]?\s*(\d+)', caseSensitive: false).firstMatch(
          item.innerXml,
        );
        final seeders = int.tryParse(seedsM?.group(1) ?? '0') ?? 0;

        out.add(
          _buildResult(
            siteName: config.name,
            title: title,
            sizeBytes: sizeBytes,
            seeders: seeders,
            leechers: 0,
            infoHash: hash,
            torrentUrl: torrentUrl,
            magnetUrl: magnet,
            publishedAt: item.getElement('pubDate')?.innerText.trim() ??
                item.getElement('published')?.innerText.trim(),
          ),
        );
      }
    } catch (_) {
      return const [];
    }
    return out;
  }

  List<TorrentResult> _extractFromJson(CustomSiteConfig config, String jsonBody) {
    final out = <TorrentResult>[];
    final seen = <String>{};
    try {
      final decoded = jsonDecode(jsonBody);
      final List<dynamic> list;
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map<String, dynamic>) {
        list = (decoded['results'] ??
                decoded['hits'] ??
                decoded['torrents'] ??
                decoded['data'] ??
                decoded['items'] ??
                const []) as List<dynamic>;
      } else {
        return const [];
      }

      for (final raw in list.whereType<Map<String, dynamic>>().take(60)) {
        final title = (raw['title'] ?? raw['name'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final hash = (raw['info_hash'] ?? raw['infohash'] ?? raw['hash'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        final validHash = RegExp(r'^[0-9A-F]{40}$').hasMatch(hash) ? hash : null;
        var magnet = (raw['magnet'] ?? raw['magnetUrl'] ?? raw['magnet_url'])?.toString();
        if (magnet != null && !magnet.startsWith('magnet:?')) magnet = null;
        final link = (raw['torrent'] ?? raw['torrent_url'] ?? raw['link'])?.toString();
        final torrentUrl =
            (link != null && _looksLikeTorrentUrl(link) && link.startsWith('http')) ? link : null;

        if (magnet == null && torrentUrl == null && validHash == null) continue;
        magnet ??= (validHash != null ? buildMagnet(validHash, title) : null);

        final key = (validHash ?? torrentUrl ?? title).toLowerCase();
        if (!seen.add(key)) continue;

        final sizeBytes = (raw['size_bytes'] as num?)?.toInt() ??
            (raw['bytes'] as num?)?.toInt() ??
            (raw['size'] is num
                ? (raw['size'] as num).toInt()
                : parseHumanSizeToBytes(raw['size']?.toString() ?? ''));
        final seeders = int.tryParse((raw['seeders'] ?? raw['seeds'] ?? '0').toString()) ?? 0;
        final leechers =
            int.tryParse((raw['leechers'] ?? raw['peers'] ?? '0').toString()) ?? 0;
        final publishedAt = (raw['date'] ??
                raw['created_unix'] ??
                raw['added'] ??
                raw['uploaded'] ??
                raw['pubDate'] ??
                raw['publishedAt'])
            ?.toString();

        out.add(
          _buildResult(
            siteName: config.name,
            title: title,
            sizeBytes: sizeBytes,
            seeders: seeders,
            leechers: leechers,
            infoHash: validHash,
            torrentUrl: torrentUrl,
            magnetUrl: magnet,
            publishedAt: publishedAt,
          ),
        );
      }
    } catch (_) {
      return const [];
    }
    return out;
  }

  TorrentResult _buildResult({
    required String siteName,
    required String title,
    required int sizeBytes,
    required int seeders,
    required int leechers,
    String? infoHash,
    String? torrentUrl,
    String? magnetUrl,
    String? publishedAt,
  }) {
    final (quality, tags) = ReleaseParser.parseQuality(title);
    final langs = ReleaseParser.detectLanguages(title);
    final (preStatus, preWarn) = ReleaseParser.preScanTitle(title, sizeBytes, seeders);
    final uid = (infoHash ?? torrentUrl ?? title).hashCode.abs();

    return TorrentResult(
      id: 'cs-${siteName.hashCode.abs()}-$uid',
      title: title,
      quality: quality,
      qualityTags: tags,
      sizeBytes: sizeBytes,
      sizeHuman: ReleaseParser.formatSize(sizeBytes),
      seeders: seeders,
      leechers: leechers,
      detectedLanguages: langs,
      languageMatch: true,
      indexer: siteName,
      infoHash: infoHash,
      torrentUrl: torrentUrl,
      magnetUrl: magnetUrl,
      preScanStatus: preStatus,
      preScanWarnings: preWarn,
      publishedAt: publishedAt,
    );
  }

  static dom.Element? _findRowContainer(dom.Element node) {
    dom.Element? cur = node.parent;
    for (var depth = 0; depth < 6 && cur != null; depth++) {
      final tag = cur.localName?.toLowerCase();
      if (tag == 'tr' || tag == 'li' || tag == 'article') return cur;
      if (tag == 'div' &&
          (cur.classes.any(
            (c) =>
                c.contains('result') ||
                c.contains('card') ||
                c.contains('item') ||
                c.contains('row') ||
                c.contains('torrent'),
          ))) {
        return cur;
      }
      cur = cur.parent;
    }
    return null;
  }

  static String _guessTitleFromRow(dom.Element row, String? magnet) {
    // 1. Heading inside the row
    for (final h in row.querySelectorAll('h1, h2, h3, h4, h5')) {
      final t = h.text.trim();
      if (t.length >= 3) return t;
    }
    // 2. Longest non-magnet, non-action link text
    String best = '';
    for (final a in row.querySelectorAll('a')) {
      final href = (a.attributes['href'] ?? '').trim();
      if (href.startsWith('magnet:?') || _looksLikeTorrentUrl(href)) continue;
      final t = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.length > best.length && t.length >= 3) {
        best = t;
      }
    }
    if (best.isNotEmpty) return best;

    // 3. Fallback to `dn=` display name inside magnet URI
    return _extractDnFromMagnet(magnet) ?? '';
  }

  static int _guessSeedersFromRow(dom.Element row) {
    // Look for elements explicitly tagged with seed/seeder class
    for (final el in row.querySelectorAll('[class*="seed"], [class*="green"]')) {
      final n = int.tryParse(el.text.replaceAll(RegExp(r'[^0-9]'), ''));
      if (n != null && n < 1000000) return n;
    }
    // In standard torrent tables, numeric cells near the end often hold seeders
    final cells = row.querySelectorAll('td');
    if (cells.length >= 4) {
      for (var i = cells.length - 1; i >= 2; i--) {
        final raw = cells[i].text.trim();
        if (RegExp(r'^\d{1,6}$').hasMatch(raw)) {
          return int.tryParse(raw) ?? 0;
        }
      }
    }
    return 0;
  }

  static List<dom.Element> _safeQueryAll(dom.Document doc, String selector) {
    try {
      return doc.querySelectorAll(selector);
    } catch (_) {
      return const [];
    }
  }

  static dom.Element? _safeQueryOne(dom.Element root, String selector) {
    try {
      return root.querySelector(selector);
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeTorrentUrl(String href) {
    final low = href.toLowerCase();
    return low.endsWith('.torrent') ||
        low.contains('.torrent?') ||
        low.contains('/download/') && low.contains('torrent');
  }

  static String? _resolveUrl(Uri base, String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final resolved = base.resolve(trimmed);
      if (resolved.scheme == 'http' || resolved.scheme == 'https') {
        return resolved.toString();
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  static String? _extractHash(String text) {
    final btih = RegExp(r'btih:([0-9a-fA-F]{40})').firstMatch(text);
    if (btih != null) return btih.group(1)!.toUpperCase();
    final hex = RegExp(r'(?<![0-9a-fA-F])([0-9a-fA-F]{40})(?![0-9a-fA-F])').firstMatch(text);
    return hex?.group(1)?.toUpperCase();
  }

  static String? _extractDnFromMagnet(String? magnet) {
    if (magnet == null || magnet.isEmpty) return null;
    final uri = Uri.tryParse(magnet);
    final dn = uri?.queryParameters['dn']?.trim();
    return (dn != null && dn.isNotEmpty) ? dn : null;
  }

  static int parseHumanSizeToBytes(String raw) {
    final m = RegExp(
      r'([\d.,]+)\s*(TB|To|TiB|GB|Go|GiB|MB|Mo|MiB|KB|Ko|KiB)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (m == null) return 0;
    final numVal = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
    final unit = m.group(2)!.toLowerCase();
    if (unit.startsWith('t')) return (numVal * 1024 * 1024 * 1024 * 1024).round();
    if (unit.startsWith('g')) return (numVal * 1024 * 1024 * 1024).round();
    if (unit.startsWith('m')) return (numVal * 1024 * 1024).round();
    if (unit.startsWith('k')) return (numVal * 1024).round();
    return numVal.round();
  }
}
