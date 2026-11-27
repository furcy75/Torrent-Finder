import 'dart:convert';

class TorznabConfig {
  const TorznabConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final bool enabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'enabled': enabled,
      };

  factory TorznabConfig.fromJson(Map<String, dynamic> json) => TorznabConfig(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
      );
}

/// User-defined website search & HTML/RSS/JSON data extractor (like Cardigann /
/// qBittorrent search plugins, 100% on-device via pure HTTP with zero JS/ads).
///
/// Supports:
/// - URL templates with `{query}` (URL-encoded), `{query_plus}` (`+`), `{query_dash}` (`-`)
/// - Smart auto-extraction when CSS selectors are left blank
/// - Optional CSS selectors (`rowSelector`, `titleSelector`, `linkSelector`,
///   `sizeSelector`, `seedersSelector`)
/// - Optional 2-step extraction (`followDetailPages`) for sites where magnet /
///   `.torrent` links only appear on individual result detail pages.
class CustomSiteConfig {
  const CustomSiteConfig({
    required this.id,
    required this.name,
    required this.searchUrlTemplate,
    this.followDetailPages = false,
    this.rowSelector = '',
    this.titleSelector = '',
    this.linkSelector = '',
    this.sizeSelector = '',
    this.seedersSelector = '',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String searchUrlTemplate;
  final bool followDetailPages;
  final String rowSelector;
  final String titleSelector;
  final String linkSelector;
  final String sizeSelector;
  final String seedersSelector;
  final bool enabled;

  CustomSiteConfig copyWith({
    String? id,
    String? name,
    String? searchUrlTemplate,
    bool? followDetailPages,
    String? rowSelector,
    String? titleSelector,
    String? linkSelector,
    String? sizeSelector,
    String? seedersSelector,
    bool? enabled,
  }) {
    return CustomSiteConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      searchUrlTemplate: searchUrlTemplate ?? this.searchUrlTemplate,
      followDetailPages: followDetailPages ?? this.followDetailPages,
      rowSelector: rowSelector ?? this.rowSelector,
      titleSelector: titleSelector ?? this.titleSelector,
      linkSelector: linkSelector ?? this.linkSelector,
      sizeSelector: sizeSelector ?? this.sizeSelector,
      seedersSelector: seedersSelector ?? this.seedersSelector,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'searchUrlTemplate': searchUrlTemplate,
        'followDetailPages': followDetailPages,
        'rowSelector': rowSelector,
        'titleSelector': titleSelector,
        'linkSelector': linkSelector,
        'sizeSelector': sizeSelector,
        'seedersSelector': seedersSelector,
        'enabled': enabled,
      };

  factory CustomSiteConfig.fromJson(Map<String, dynamic> json) => CustomSiteConfig(
        id: (json['id'] as String? ?? '').trim().isNotEmpty
            ? (json['id'] as String).trim()
            : 'site_${DateTime.now().microsecondsSinceEpoch}',
        name: (json['name'] as String? ?? '').trim(),
        searchUrlTemplate: (json['searchUrlTemplate'] as String? ?? '').trim(),
        followDetailPages: json['followDetailPages'] as bool? ?? false,
        rowSelector: (json['rowSelector'] as String? ?? '').trim(),
        titleSelector: (json['titleSelector'] as String? ?? '').trim(),
        linkSelector: (json['linkSelector'] as String? ?? '').trim(),
        sizeSelector: (json['sizeSelector'] as String? ?? '').trim(),
        seedersSelector: (json['seedersSelector'] as String? ?? '').trim(),
        enabled: json['enabled'] as bool? ?? true,
      );

  static String encodeListJson(List<CustomSiteConfig> sites) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(sites.map((s) => s.toJson()).toList());
  }

  static List<CustomSiteConfig> decodeListJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is List ? decoded : (decoded is Map ? [decoded] : const []);
      final out = <CustomSiteConfig>[];
      for (final item in list.whereType<Map<String, dynamic>>()) {
        final cfg = CustomSiteConfig.fromJson(item);
        if (cfg.name.isNotEmpty && cfg.searchUrlTemplate.isNotEmpty) {
          out.add(cfg);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

class AppSettings {
  const AppSettings({
    this.appLanguage = '',
    this.strictVideoOnly = true,
    this.blockArchives = true,
    this.enableYts = true,
    this.enableApibay = true,
    this.enableKnaben = true,
    this.enableTorrentCsv = true,
    this.enableSolidTorrents = true,
    this.enableEztv = true,
    this.enableBitSearch = true,
    this.enableNyaa = true,
    this.enableSubsPlease = true,
    this.enableLimeTorrents = true,
    this.enableArchiveOrg = true,
    this.torznabIndexers = const [],
    this.customSites = const [],
  });

  /// Explicit UI language code (`en`, `fr`, `es`, `de`, `nl`, `it`), or `''` for auto-detect.
  final String appLanguage;
  final bool strictVideoOnly;
  final bool blockArchives;
  final bool enableYts;
  final bool enableApibay;
  final bool enableKnaben;
  final bool enableTorrentCsv;
  final bool enableSolidTorrents;
  final bool enableEztv;
  final bool enableBitSearch;
  final bool enableNyaa;
  final bool enableSubsPlease;
  final bool enableLimeTorrents;
  final bool enableArchiveOrg;
  final List<TorznabConfig> torznabIndexers;
  final List<CustomSiteConfig> customSites;

  AppSettings copyWith({
    String? appLanguage,
    bool? strictVideoOnly,
    bool? blockArchives,
    bool? enableYts,
    bool? enableApibay,
    bool? enableKnaben,
    bool? enableTorrentCsv,
    bool? enableSolidTorrents,
    bool? enableEztv,
    bool? enableBitSearch,
    bool? enableNyaa,
    bool? enableSubsPlease,
    bool? enableLimeTorrents,
    bool? enableArchiveOrg,
    List<TorznabConfig>? torznabIndexers,
    List<CustomSiteConfig>? customSites,
  }) {
    return AppSettings(
      appLanguage: appLanguage ?? this.appLanguage,
      strictVideoOnly: strictVideoOnly ?? this.strictVideoOnly,
      blockArchives: blockArchives ?? this.blockArchives,
      enableYts: enableYts ?? this.enableYts,
      enableApibay: enableApibay ?? this.enableApibay,
      enableKnaben: enableKnaben ?? this.enableKnaben,
      enableTorrentCsv: enableTorrentCsv ?? this.enableTorrentCsv,
      enableSolidTorrents: enableSolidTorrents ?? this.enableSolidTorrents,
      enableEztv: enableEztv ?? this.enableEztv,
      enableBitSearch: enableBitSearch ?? this.enableBitSearch,
      enableNyaa: enableNyaa ?? this.enableNyaa,
      enableSubsPlease: enableSubsPlease ?? this.enableSubsPlease,
      enableLimeTorrents: enableLimeTorrents ?? this.enableLimeTorrents,
      enableArchiveOrg: enableArchiveOrg ?? this.enableArchiveOrg,
      torznabIndexers: torznabIndexers ?? this.torznabIndexers,
      customSites: customSites ?? this.customSites,
    );
  }

  Map<String, dynamic> toJson() => {
        'appLanguage': appLanguage,
        'strictVideoOnly': strictVideoOnly,
        'blockArchives': blockArchives,
        'enableYts': enableYts,
        'enableApibay': enableApibay,
        'enableKnaben': enableKnaben,
        'enableTorrentCsv': enableTorrentCsv,
        'enableSolidTorrents': enableSolidTorrents,
        'enableEztv': enableEztv,
        'enableBitSearch': enableBitSearch,
        'enableNyaa': enableNyaa,
        'enableSubsPlease': enableSubsPlease,
        'enableLimeTorrents': enableLimeTorrents,
        'enableArchiveOrg': enableArchiveOrg,
        'torznabIndexers': torznabIndexers.map((e) => e.toJson()).toList(),
        'customSites': customSites.map((e) => e.toJson()).toList(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        appLanguage: json['appLanguage'] as String? ?? '',
        strictVideoOnly: json['strictVideoOnly'] as bool? ?? true,
        blockArchives: json['blockArchives'] as bool? ?? true,
        enableYts: json['enableYts'] as bool? ?? true,
        enableApibay: json['enableApibay'] as bool? ?? true,
        enableKnaben: json['enableKnaben'] as bool? ?? true,
        enableTorrentCsv: json['enableTorrentCsv'] as bool? ?? true,
        enableSolidTorrents: json['enableSolidTorrents'] as bool? ?? true,
        enableEztv: json['enableEztv'] as bool? ?? true,
        enableBitSearch: json['enableBitSearch'] as bool? ?? true,
        enableNyaa: json['enableNyaa'] as bool? ?? true,
        enableSubsPlease: json['enableSubsPlease'] as bool? ?? true,
        enableLimeTorrents: json['enableLimeTorrents'] as bool? ?? true,
        enableArchiveOrg: json['enableArchiveOrg'] as bool? ?? true,
        torznabIndexers: ((json['torznabIndexers'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TorznabConfig.fromJson)
            .toList(),
        customSites: ((json['customSites'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CustomSiteConfig.fromJson)
            .where((s) => s.name.isNotEmpty && s.searchUrlTemplate.isNotEmpty)
            .toList(),
      );
}
