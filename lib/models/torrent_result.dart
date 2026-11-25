enum LanguageFilter {
  fr('fr', '🇫🇷', 'Français'),
  en('en', '🇬🇧', 'English'),
  es('es', '🇪🇸', 'Español'),
  all('all', '🌍', 'Toutes');

  const LanguageFilter(this.code, this.flag, this.label);

  final String code;
  final String flag;
  final String label;

  static LanguageFilter fromCode(String? code) {
    return LanguageFilter.values.firstWhere(
      (e) => e.code == code,
      orElse: () => LanguageFilter.fr,
    );
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
  final String? infoHash;
  final String? torrentUrl;
  final String? magnetUrl;
  final SafetyStatus preScanStatus;
  final List<String> preScanWarnings;
  final String? publishedAt;

  TorrentResult copyWith({String? torrentUrl}) {
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
      infoHash: infoHash,
      torrentUrl: torrentUrl ?? this.torrentUrl,
      magnetUrl: magnetUrl,
      preScanStatus: preScanStatus,
      preScanWarnings: preScanWarnings,
      publishedAt: publishedAt,
    );
  }
}
