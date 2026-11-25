/// Movie metadata with localized titles across languages (FR / EN / ES / Original).
class MovieSuggestion {
  const MovieSuggestion({
    required this.titleFr,
    required this.titleOriginal,
    this.titleEn,
    this.titleEs,
    this.year,
    this.posterUrl,
    this.source = 'AlloCiné',
    this.sourceUrl,
    this.synopsis,
  });

  final String titleFr;
  final String titleOriginal;
  final String? titleEn;
  final String? titleEs;
  final int? year;
  final String? posterUrl;
  final String source;
  final String? sourceUrl;
  final String? synopsis;

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
    String? titleEn,
    String? titleEs,
    int? year,
    String? posterUrl,
    String? source,
    String? sourceUrl,
    String? synopsis,
  }) {
    return MovieSuggestion(
      titleFr: titleFr ?? this.titleFr,
      titleOriginal: titleOriginal ?? this.titleOriginal,
      titleEn: titleEn ?? this.titleEn,
      titleEs: titleEs ?? this.titleEs,
      year: year ?? this.year,
      posterUrl: posterUrl ?? this.posterUrl,
      source: source ?? this.source,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      synopsis: synopsis ?? this.synopsis,
    );
  }
}
