import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/services/custom_site_service.dart';
import 'package:safetorrent/services/local_storage.dart';

void main() {
  final service = CustomSiteService();

  group('CustomSiteService.buildSearchUri', () {
    test('expands {query}, {query_plus}, and {query_dash}', () {
      expect(
        CustomSiteService.buildSearchUri('https://example.org/search?q={query}', 'dune part two')
            .toString(),
        equals('https://example.org/search?q=dune%20part%20two'),
      );
      expect(
        CustomSiteService.buildSearchUri(
          'https://example.org/find?s={query_plus}',
          'dune part two',
        ).toString(),
        equals('https://example.org/find?s=dune+part+two'),
      );
      expect(
        CustomSiteService.buildSearchUri(
          'https://example.org/search/{query_dash}/1/',
          'dune part two',
        ).toString(),
        equals('https://example.org/search/dune-part-two/1/'),
      );
    });

    test('appends ?q= or &q= when no placeholder is provided', () {
      expect(
        CustomSiteService.buildSearchUri('https://example.org/search', 'ubuntu lts').toString(),
        equals('https://example.org/search?q=ubuntu+lts'),
      );
      expect(
        CustomSiteService.buildSearchUri('https://example.org/search?cat=all', 'ubuntu lts')
            .toString(),
        equals('https://example.org/search?cat=all&q=ubuntu+lts'),
      );
    });

    test('rejects invalid or non-HTTP(S) schemes', () {
      expect(CustomSiteService.buildSearchUri('javascript:alert(1)', 'test'), isNull);
      expect(CustomSiteService.buildSearchUri('ftp://example.org/{query}', 'test'), isNull);
      expect(CustomSiteService.buildSearchUri('', 'test'), isNull);
    });
  });

  group('CustomSiteService HTML / CSS / 2-step / RSS / JSON extraction', () {
    const hash1 = '0123456789ABCDEF0123456789ABCDEF01234567';
    const hash2 = 'FEDCBA9876543210FEDCBA9876543210FEDCBA98';

    test('smart auto-extracts torrents from standard HTML table without CSS selectors', () async {
      const html = '''
      <html><body>
        <table>
          <tr>
            <td><a href="/torrent/1">Ubuntu.24.04.LTS.Desktop.amd64.iso</a></td>
            <td><a href="magnet:?xt=urn:btih:$hash1&dn=Ubuntu">Magnet</a></td>
            <td>5.7 GB</td>
            <td class="seeders">412</td>
          </tr>
          <tr>
            <td><a href="/torrent/2">Big.Buck.Bunny.2008.1080p.FRENCH.BluRay</a></td>
            <td><a href="/download/bunny.torrent">DL</a></td>
            <td>1.25 Go</td>
            <td>88</td>
          </tr>
        </table>
      </body></html>
      ''';

      const cfg = CustomSiteConfig(
        id: 'auto_1',
        name: 'AutoTracker',
        searchUrlTemplate: 'https://tracker.example/search?q={query}',
      );

      final results = await service.extractFromResponse(
        config: cfg,
        pageUri: Uri.parse('https://tracker.example/search?q=ubuntu'),
        body: html,
        contentType: 'text/html',
      );

      expect(results.length, equals(2));
      expect(results[0].indexer, equals('AutoTracker'));
      expect(results[0].title, equals('Ubuntu.24.04.LTS.Desktop.amd64.iso'));
      expect(results[0].infoHash, equals(hash1));
      expect(results[0].seeders, equals(412));
      expect(results[0].sizeBytes, greaterThan(5 * 1024 * 1024 * 1024));

      expect(results[1].title, equals('Big.Buck.Bunny.2008.1080p.FRENCH.BluRay'));
      expect(results[1].torrentUrl, equals('https://tracker.example/download/bunny.torrent'));
      expect(results[1].detectedLanguages, contains('FR'));
      expect(results[1].seeders, equals(88));
    });

    test('supports explicit Cardigann-style CSS selectors', () async {
      const html = '''
      <html><body>
        <div class="listing">
          <div class="card-row">
            <span class="release-name">Linux.Mint.22.Cinnamon.64bit</span>
            <a class="mag-btn" href="magnet:?xt=urn:btih:$hash2">M</a>
            <span class="sz">2.8 GB</span>
            <span class="sd">195</span>
          </div>
        </div>
      </body></html>
      ''';

      const cfg = CustomSiteConfig(
        id: 'css_1',
        name: 'CssTracker',
        searchUrlTemplate: 'https://css.example/s?q={query}',
        rowSelector: 'div.card-row',
        titleSelector: '.release-name',
        linkSelector: 'a.mag-btn',
        sizeSelector: '.sz',
        seedersSelector: '.sd',
      );

      final results = await service.extractFromResponse(
        config: cfg,
        pageUri: Uri.parse('https://css.example/s?q=mint'),
        body: html,
        contentType: 'text/html',
      );

      expect(results.length, equals(1));
      expect(results.first.title, equals('Linux.Mint.22.Cinnamon.64bit'));
      expect(results.first.infoHash, equals(hash2));
      expect(results.first.seeders, equals(195));
      expect(results.first.sizeBytes, greaterThan(2 * 1024 * 1024 * 1024));
    });

    test('supports 2-step detail page extraction when followDetailPages is true', () async {
      const listingHtml = '''
      <html><body>
        <table>
          <tr>
            <td><a href="/torrent/detail-42.html">Severance.S02E01.1080p.MULTI.WEB-DL</a></td>
            <td>1.8 GB</td>
            <td class="seeds">340</td>
          </tr>
        </table>
      </body></html>
      ''';

      const detailHtml = '''
      <html><body>
        <h1>Severance.S02E01.1080p.MULTI.WEB-DL</h1>
        <a href="magnet:?xt=urn:btih:$hash1&dn=Severance">Download Magnet</a>
        <a href="/files/severance.torrent">Direct .torrent</a>
      </body></html>
      ''';

      const cfg = CustomSiteConfig(
        id: 'two_step',
        name: 'TwoStepSite',
        searchUrlTemplate: 'https://twostep.example/search?q={query}',
        followDetailPages: true,
      );

      final visited = <Uri>[];
      final results = await service.extractFromResponse(
        config: cfg,
        pageUri: Uri.parse('https://twostep.example/search?q=severance'),
        body: listingHtml,
        contentType: 'text/html',
        detailFetcher: (uri) async {
          visited.add(uri);
          return detailHtml;
        },
      );

      expect(visited, equals([Uri.parse('https://twostep.example/torrent/detail-42.html')]));
      expect(results.length, equals(1));
      expect(results.first.title, equals('Severance.S02E01.1080p.MULTI.WEB-DL'));
      expect(results.first.infoHash, equals(hash1));
      expect(results.first.torrentUrl, equals('https://twostep.example/files/severance.torrent'));
      expect(results.first.seeders, equals(340));
    });

    test('auto-detects RSS XML feeds', () async {
      const rss = '''
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"><channel>
        <item>
          <title>Debian.12.7.0.amd64.netinst.iso</title>
          <link>https://rss.example/dl/debian.torrent</link>
          <enclosure url="https://rss.example/dl/debian.torrent" length="660602880" type="application/x-bittorrent" />
          <description>Seeders: 512 | Hash: $hash1</description>
        </item>
      </channel></rss>
      ''';

      const cfg = CustomSiteConfig(
        id: 'rss_1',
        name: 'RssFeed',
        searchUrlTemplate: 'https://rss.example/rss?q={query}',
      );

      final results = await service.extractFromResponse(
        config: cfg,
        pageUri: Uri.parse('https://rss.example/rss?q=debian'),
        body: rss,
        contentType: 'application/rss+xml',
      );

      expect(results.length, equals(1));
      expect(results.first.title, equals('Debian.12.7.0.amd64.netinst.iso'));
      expect(results.first.torrentUrl, equals('https://rss.example/dl/debian.torrent'));
      expect(results.first.infoHash, equals(hash1));
      expect(results.first.seeders, equals(512));
    });

    test('auto-detects JSON search endpoints', () async {
      const jsonBody = '''
      {
        "results": [
          {
            "title": "Blender.Open.Movie.4K.HDR",
            "info_hash": "$hash2",
            "size_bytes": 4294967296,
            "seeders": 77,
            "leechers": 9
          }
        ]
      }
      ''';

      const cfg = CustomSiteConfig(
        id: 'json_1',
        name: 'JsonApi',
        searchUrlTemplate: 'https://api.example/search?q={query}',
      );

      final results = await service.extractFromResponse(
        config: cfg,
        pageUri: Uri.parse('https://api.example/search?q=blender'),
        body: jsonBody,
        contentType: 'application/json',
      );

      expect(results.length, equals(1));
      expect(results.first.title, equals('Blender.Open.Movie.4K.HDR'));
      expect(results.first.infoHash, equals(hash2));
      expect(results.first.seeders, equals(77));
      expect(results.first.leechers, equals(9));
      expect(results.first.magnetUrl, contains(hash2));
    });
  });

  group('CustomSiteConfig JSON import/export & LocalStorageService persistence', () {
    test('round-trips JSON export/import and persists in LocalStorageService', () async {
      final tmpDir = Directory.systemTemp.createTempSync('torrent_seeder_custom_');
      addTearDown(() {
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      });

      const original = [
        CustomSiteConfig(
          id: 'site_1',
          name: 'OpenIndex',
          searchUrlTemplate: 'https://open.example/search?q={query}',
          followDetailPages: true,
          rowSelector: 'tr.item',
          titleSelector: 'td.title a',
        ),
      ];

      final exported = CustomSiteConfig.encodeListJson(original);
      final imported = CustomSiteConfig.decodeListJson(exported);
      expect(imported.length, equals(1));
      expect(imported.first.name, equals('OpenIndex'));
      expect(imported.first.followDetailPages, isTrue);
      expect(imported.first.rowSelector, equals('tr.item'));

      final storage = LocalStorageService(overrideDirectory: tmpDir);
      await storage.load();
      await storage.updateSettings(
        storage.settings.copyWith(enableSubsPlease: false, customSites: imported),
      );

      final reloaded = LocalStorageService(overrideDirectory: tmpDir);
      await reloaded.load();
      expect(reloaded.settings.enableSubsPlease, isFalse);
      expect(reloaded.settings.customSites.length, equals(1));
      expect(reloaded.settings.customSites.first.name, equals('OpenIndex'));
      expect(reloaded.settings.customSites.first.followDetailPages, isTrue);
    });
  });
}
