import 'package:safetorrent/models/movie_suggestion.dart';
import 'package:safetorrent/models/torrent_result.dart';

class WatchlistItem {
  const WatchlistItem({
    required this.id,
    required this.titleFr,
    this.titleOriginal,
    this.titleEn,
    this.titleEs,
    this.posterUrl,
    this.mediaType = MediaType.movie,
    this.tvMazeId,
    this.seriesStatus,
    this.seasonCount,
    this.nextSeasonInfo,
    this.nextReleaseDate,
    required this.languages,
    this.year,
    this.notes,
    this.found = false,
    this.lastResultCount = 0,
    required this.createdAt,
    this.lastCheckedAt,
  });

  final String id;
  final String titleFr;
  final String? titleOriginal;
  final String? titleEn;
  final String? titleEs;
  final String? posterUrl;
  final MediaType mediaType;
  final int? tvMazeId;
  final String? seriesStatus;
  final int? seasonCount;
  final String? nextSeasonInfo;
  final String? nextReleaseDate;
  final List<LanguageFilter> languages;
  final int? year;
  final String? notes;
  final bool found;
  final int lastResultCount;
  final DateTime createdAt;
  final DateTime? lastCheckedAt;

  MovieSuggestion toMovieSuggestion() {
    return MovieSuggestion(
      titleFr: titleFr,
      titleOriginal: (titleOriginal ?? '').trim().isNotEmpty ? titleOriginal!.trim() : titleFr,
      mediaType: mediaType,
      titleEn: titleEn,
      titleEs: titleEs,
      year: year,
      posterUrl: posterUrl,
      source: 'Liste Plus tard',
      tvMazeId: tvMazeId,
      seriesStatus: seriesStatus,
      seasonCount: seasonCount,
      nextSeasonInfo: nextSeasonInfo,
      nextReleaseDate: nextReleaseDate,
    );
  }

  WatchlistItem copyWith({
    String? posterUrl,
    String? titleEn,
    String? titleEs,
    int? tvMazeId,
    String? seriesStatus,
    int? seasonCount,
    String? nextSeasonInfo,
    String? nextReleaseDate,
    bool? found,
    int? lastResultCount,
    DateTime? lastCheckedAt,
  }) {
    return WatchlistItem(
      id: id,
      titleFr: titleFr,
      titleOriginal: titleOriginal,
      titleEn: titleEn ?? this.titleEn,
      titleEs: titleEs ?? this.titleEs,
      posterUrl: posterUrl ?? this.posterUrl,
      mediaType: mediaType,
      tvMazeId: tvMazeId ?? this.tvMazeId,
      seriesStatus: seriesStatus ?? this.seriesStatus,
      seasonCount: seasonCount ?? this.seasonCount,
      nextSeasonInfo: nextSeasonInfo ?? this.nextSeasonInfo,
      nextReleaseDate: nextReleaseDate ?? this.nextReleaseDate,
      languages: languages,
      year: year,
      notes: notes,
      found: found ?? this.found,
      lastResultCount: lastResultCount ?? this.lastResultCount,
      createdAt: createdAt,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'titleFr': titleFr,
        'titleOriginal': titleOriginal,
        'titleEn': titleEn,
        'titleEs': titleEs,
        'posterUrl': posterUrl,
        'mediaType': mediaType.code,
        'tvMazeId': tvMazeId,
        'seriesStatus': seriesStatus,
        'seasonCount': seasonCount,
        'nextSeasonInfo': nextSeasonInfo,
        'nextReleaseDate': nextReleaseDate,
        'languages': languages.map((e) => e.code).toList(),
        'language': languages.isNotEmpty ? languages.first.code : 'all',
        'year': year,
        'notes': notes,
        'found': found,
        'lastResultCount': lastResultCount,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'lastCheckedAt': lastCheckedAt?.toUtc().toIso8601String(),
      };

  factory WatchlistItem.fromJson(Map<String, dynamic> json) => WatchlistItem(
        id: json['id'] as String? ?? '',
        titleFr: json['titleFr'] as String? ?? '',
        titleOriginal: json['titleOriginal'] as String?,
        titleEn: json['titleEn'] as String?,
        titleEs: json['titleEs'] as String?,
        posterUrl: json['posterUrl'] as String?,
        mediaType: MediaType.fromCode(json['mediaType'] as String?),
        tvMazeId: (json['tvMazeId'] as num?)?.toInt(),
        seriesStatus: json['seriesStatus'] as String?,
        seasonCount: (json['seasonCount'] as num?)?.toInt(),
        nextSeasonInfo: json['nextSeasonInfo'] as String?,
        nextReleaseDate: json['nextReleaseDate'] as String?,
        languages: LanguageFilter.fromJsonList(
          json['languages'],
          json['language'] as String?,
        ),
        year: (json['year'] as num?)?.toInt(),
        notes: json['notes'] as String?,
        found: json['found'] as bool? ?? false,
        lastResultCount: (json['lastResultCount'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now().toUtc(),
        lastCheckedAt: json['lastCheckedAt'] != null
            ? DateTime.tryParse(json['lastCheckedAt'] as String)
            : null,
      );
}
