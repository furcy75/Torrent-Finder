/// Movie title & metadata resolved from AlloCiné (or Wikidata / IMDb fallback).
class MovieSuggestion {
  const MovieSuggestion({
    required this.titleFr,
    required this.titleOriginal,
    this.year,
    this.posterUrl,
    this.source = 'AlloCiné',
    this.sourceUrl,
    this.synopsis,
  });

  final String titleFr;
  final String titleOriginal;
  final int? year;
  final String? posterUrl;
  final String source;
  final String? sourceUrl;
  final String? synopsis;
}
