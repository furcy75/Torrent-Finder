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
    this.saveHistory = false,
    this.strictVideoOnly = true,
    this.blockArchives = true,
    this.enableYts = true,
    this.enableApibay = true,
    this.enableArchiveOrg = true,
    this.torznabIndexers = const [],
  });

  final bool saveHistory;
  final bool strictVideoOnly;
  final bool blockArchives;
  final bool enableYts;
  final bool enableApibay;
  final bool enableArchiveOrg;
  final List<TorznabConfig> torznabIndexers;

  AppSettings copyWith({
    bool? saveHistory,
    bool? strictVideoOnly,
    bool? blockArchives,
    bool? enableYts,
    bool? enableApibay,
    bool? enableArchiveOrg,
    List<TorznabConfig>? torznabIndexers,
  }) {
    return AppSettings(
      saveHistory: saveHistory ?? this.saveHistory,
      strictVideoOnly: strictVideoOnly ?? this.strictVideoOnly,
      blockArchives: blockArchives ?? this.blockArchives,
      enableYts: enableYts ?? this.enableYts,
      enableApibay: enableApibay ?? this.enableApibay,
      enableArchiveOrg: enableArchiveOrg ?? this.enableArchiveOrg,
      torznabIndexers: torznabIndexers ?? this.torznabIndexers,
    );
  }

  Map<String, dynamic> toJson() => {
        'saveHistory': saveHistory,
        'strictVideoOnly': strictVideoOnly,
        'blockArchives': blockArchives,
        'enableYts': enableYts,
        'enableApibay': enableApibay,
        'enableArchiveOrg': enableArchiveOrg,
        'torznabIndexers': torznabIndexers.map((e) => e.toJson()).toList(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        saveHistory: json['saveHistory'] as bool? ?? false,
        strictVideoOnly: json['strictVideoOnly'] as bool? ?? true,
        blockArchives: json['blockArchives'] as bool? ?? true,
        enableYts: json['enableYts'] as bool? ?? true,
        enableApibay: json['enableApibay'] as bool? ?? true,
        enableArchiveOrg: json['enableArchiveOrg'] as bool? ?? true,
        torznabIndexers: ((json['torznabIndexers'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TorznabConfig.fromJson)
            .toList(),
      );
}
