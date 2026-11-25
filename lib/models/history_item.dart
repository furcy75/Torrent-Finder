import 'package:safetorrent/models/torrent_result.dart';

class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.query,
    this.originalTitle,
    required this.language,
    required this.resultCount,
    required this.createdAt,
  });

  final String id;
  final String query;
  final String? originalTitle;
  final LanguageFilter language;
  final int resultCount;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'query': query,
        'originalTitle': originalTitle,
        'language': language.code,
        'resultCount': resultCount,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: json['id'] as String? ?? '',
        query: json['query'] as String? ?? '',
        originalTitle: json['originalTitle'] as String?,
        language: LanguageFilter.fromCode(json['language'] as String?),
        resultCount: (json['resultCount'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now().toUtc(),
      );
}
