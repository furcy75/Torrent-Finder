enum LanguageFilter {
  fr('fr', '🇫🇷', 'Français'),
  en('en', '🇬🇧', 'English'),
  es('es', '🇪🇸', 'Español'),
  all('all', '🌍', 'Toutes');

  const LanguageFilter(this.code, this.flag, this.label);

  final String code;
  final String flag;
  final String label;

  static const List<LanguageFilter> selectableFlags = [fr, en, es];

  static LanguageFilter fromCode(String? code) {
    return LanguageFilter.values.firstWhere(
      (e) => e.code == code,
      orElse: () => LanguageFilter.fr,
    );
  }

  static List<LanguageFilter> fromJsonList(dynamic rawList, String? legacyCode) {
    if (rawList is List && rawList.isNotEmpty) {
      final parsed = rawList
          .map((e) => fromCode(e?.toString()))
          .where((l) => l != LanguageFilter.all)
          .toSet()
          .toList();
      if (parsed.isNotEmpty) return parsed;
    }
    if (legacyCode == 'all') return List<LanguageFilter>.from(selectableFlags);
    if (legacyCode != null && legacyCode.isNotEmpty) {
      return [fromCode(legacyCode)];
    }
    return [LanguageFilter.fr];
  }

  static String formatFlags(Iterable<LanguageFilter> langs) {
    final set = langs.where((l) => l != LanguageFilter.all).toSet();
    if (set.isEmpty || set.length == selectableFlags.length) {
      return '🌍 Toutes (🇫🇷 🇬🇧 🇪🇸)';
    }
    return set.map((l) => '${l.flag} ${l.code.toUpperCase()}').join(' + ');
  }
}

enum SafetyStatus {
  safe,
  warning,
  blocked,
  unverified,
}

/// Normalized torrent search result displayed to the user.
class TorrentResult {
  const TorrentResult({
    required this.id,
    required this.title,
    required this.quality,
    required this.qualityTags,
    required this.sizeBytes,
    required this.sizeHuman,
    required this.seeders,
    required this.leechers,
    required this.detectedLanguages,
    required this.languageMatch,
    required this.indexer,
    this.sourceId,
    this.nfoText,
    this.infoHash,
    this.torrentUrl,
    this.magnetUrl,
    this.preScanStatus = SafetyStatus.unverified,
    this.preScanWarnings = const [],
    this.publishedAt,
  });

  final String id;
  final String title;
  final String quality;
  final List<String> qualityTags;
  final int sizeBytes;
  final String sizeHuman;
  final int seeders;
  final int leechers;
  final List<String> detectedLanguages;
  final bool languageMatch;
  final String indexer;
  final String? sourceId;
  final String? nfoText;
  final String? infoHash;
  final String? torrentUrl;
  final String? magnetUrl;
  final SafetyStatus preScanStatus;
  final List<String> preScanWarnings;
  final String? publishedAt;

  TorrentResult copyWith({
    String? torrentUrl,
    String? nfoText,
    String? sourceId,
    String? publishedAt,
  }) {
    return TorrentResult(
      id: id,
      title: title,
      quality: quality,
      qualityTags: qualityTags,
      sizeBytes: sizeBytes,
      sizeHuman: sizeHuman,
      seeders: seeders,
      leechers: leechers,
      detectedLanguages: detectedLanguages,
      languageMatch: languageMatch,
      indexer: indexer,
      sourceId: sourceId ?? this.sourceId,
      nfoText: nfoText ?? this.nfoText,
      infoHash: infoHash,
      torrentUrl: torrentUrl ?? this.torrentUrl,
      magnetUrl: magnetUrl,
      preScanStatus: preScanStatus,
      preScanWarnings: preScanWarnings,
      publishedAt: publishedAt ?? this.publishedAt,
    );
  }
}
