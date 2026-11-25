import 'package:safetorrent/models/torrent_result.dart';

class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.query,
    this.originalTitle,
    this.year,
    required this.languages,
    required this.resultCount,
    required this.createdAt,
  });

  final String id;
  final String query;
  final String? originalTitle;
  final int? year;
  final List<LanguageFilter> languages;
  final int resultCount;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'query': query,
        'originalTitle': originalTitle,
        'year': year,
        'languages': languages.map((e) => e.code).toList(),
        'language': languages.isNotEmpty ? languages.first.code : 'fr',
        'resultCount': resultCount,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: json['id'] as String? ?? '',
        query: json['query'] as String? ?? '',
        originalTitle: json['originalTitle'] as String?,
        year: (json['year'] as num?)?.toInt(),
        languages: LanguageFilter.fromJsonList(
          json['languages'],
          json['language'] as String?,
        ),
        resultCount: (json['resultCount'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now().toUtc(),
      );
}
