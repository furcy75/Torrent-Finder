enum MediaType {
  movie('movie', 'Film'),
  series('series', 'Série');

  const MediaType(this.code, this.label);

  final String code;
  final String label;

  static MediaType fromCode(String? code) {
    return MediaType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => MediaType.movie,
    );
  }
}

/// Movie or TV series metadata with localized titles (FR / EN / ES / VO),
/// poster thumbnail, and (for TV series) season count & upcoming release dates.
class MovieSuggestion {
  const MovieSuggestion({
    required this.titleFr,
    required this.titleOriginal,
    this.mediaType = MediaType.movie,
    this.titleEn,
    this.titleEs,
    this.year,
    this.posterUrl,
    this.source = 'AlloCiné',
    this.sourceUrl,
    this.synopsis,
    this.tvMazeId,
    this.seriesStatus,
    this.seasonCount,
    this.nextSeasonInfo,
    this.nextReleaseDate,
  });

  final String titleFr;
  final String titleOriginal;
  final MediaType mediaType;
  final String? titleEn;
  final String? titleEs;
  final int? year;
  final String? posterUrl;
  final String source;
  final String? sourceUrl;
  final String? synopsis;

  // TV Series metadata (populated from TVMaze / AlloCiné)
  final int? tvMazeId;
  final String? seriesStatus;
  final int? seasonCount;
  final String? nextSeasonInfo;
  final String? nextReleaseDate;

  /// All distinct non-empty titles across languages.
  List<String> get allDistinctTitles {
    final seen = <String>{};
    final out = <String>[];
    for (final candidate in [titleFr, titleEn, titleEs, titleOriginal]) {
      final clean = (candidate ?? '').trim();
      if (clean.isNotEmpty && seen.add(clean.toLowerCase())) {
        out.add(clean);
      }
    }
    return out;
  }

  MovieSuggestion copyWith({
    String? titleFr,
    String? titleOriginal,
    MediaType? mediaType,
    String? titleEn,
    String? titleEs,
    int? year,
    String? posterUrl,
    String? source,
    String? sourceUrl,
    String? synopsis,
    int? tvMazeId,
    String? seriesStatus,
    int? seasonCount,
    String? nextSeasonInfo,
    String? nextReleaseDate,
  }) {
    return MovieSuggestion(
      titleFr: titleFr ?? this.titleFr,
      titleOriginal: titleOriginal ?? this.titleOriginal,
      mediaType: mediaType ?? this.mediaType,
      titleEn: titleEn ?? this.titleEn,
      titleEs: titleEs ?? this.titleEs,
      year: year ?? this.year,
      posterUrl: posterUrl ?? this.posterUrl,
      source: source ?? this.source,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      synopsis: synopsis ?? this.synopsis,
      tvMazeId: tvMazeId ?? this.tvMazeId,
      seriesStatus: seriesStatus ?? this.seriesStatus,
      seasonCount: seasonCount ?? this.seasonCount,
      nextSeasonInfo: nextSeasonInfo ?? this.nextSeasonInfo,
      nextReleaseDate: nextReleaseDate ?? this.nextReleaseDate,
    );
  }
}
