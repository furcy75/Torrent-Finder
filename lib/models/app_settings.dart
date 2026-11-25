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
    this.enableLimeTorrents = true,
    this.enableArchiveOrg = true,
    this.torznabIndexers = const [],
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
  final bool enableLimeTorrents;
  final bool enableArchiveOrg;
  final List<TorznabConfig> torznabIndexers;

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
    bool? enableLimeTorrents,
    bool? enableArchiveOrg,
    List<TorznabConfig>? torznabIndexers,
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
      enableLimeTorrents: enableLimeTorrents ?? this.enableLimeTorrents,
      enableArchiveOrg: enableArchiveOrg ?? this.enableArchiveOrg,
      torznabIndexers: torznabIndexers ?? this.torznabIndexers,
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
        'enableLimeTorrents': enableLimeTorrents,
        'enableArchiveOrg': enableArchiveOrg,
        'torznabIndexers': torznabIndexers.map((e) => e.toJson()).toList(),
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
        enableLimeTorrents: json['enableLimeTorrents'] as bool? ?? true,
        enableArchiveOrg: json['enableArchiveOrg'] as bool? ?? true,
        torznabIndexers: ((json['torznabIndexers'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TorznabConfig.fromJson)
            .toList(),
      );
}
