import 'package:safetorrent/models/torrent_result.dart';

class WatchlistItem {
  const WatchlistItem({
    required this.id,
    required this.titleFr,
    this.titleOriginal,
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
  final List<LanguageFilter> languages;
  final int? year;
  final String? notes;
  final bool found;
  final int lastResultCount;
  final DateTime createdAt;
  final DateTime? lastCheckedAt;

  WatchlistItem copyWith({
    bool? found,
    int? lastResultCount,
    DateTime? lastCheckedAt,
  }) {
    return WatchlistItem(
      id: id,
      titleFr: titleFr,
      titleOriginal: titleOriginal,
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
        'languages': languages.map((e) => e.code).toList(),
        'language': languages.isNotEmpty ? languages.first.code : 'fr',
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
