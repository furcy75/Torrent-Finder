import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/services/release_parser.dart';

class NfoDetails {
  const NfoDetails({
    required this.sourceLabel,
    required this.content,
    this.hasRawNfo = false,
  });

  final String sourceLabel;
  final String content;
  final bool hasRawNfo;
}

/// Fetches plain-text NFO / MediaInfo / technical release details without ever
/// executing HTML or JavaScript (pure JSON / plain-text HTTP with 64 KiB cap).
class NfoService {
  static const Duration _timeout = Duration(seconds: 10);
  static const int _maxNfoChars = 65536;
  static const Map<String, String> _headers = {
    'User-Agent': 'TorrentSeeder/2.0 (Standalone-NFO)',
  };

  Future<NfoDetails> fetchDetails(TorrentResult torrent) async {
    // 1. Pre-populated technical details (e.g. from YTS or Torznab description)
    if (torrent.nfoText != null && torrent.nfoText!.trim().isNotEmpty) {
      // For YTS, enrich with full movie_details if sourceId is present
      if (torrent.indexer == 'YTS' && torrent.sourceId != null) {
        final ytsFull = await _fetchYtsDetails(torrent);
        if (ytsFull != null) return ytsFull;
      }
      return NfoDetails(
        sourceLabel: torrent.indexer,
        content: _sanitizePlainText(torrent.nfoText!),
        hasRawNfo: true,
      );
    }

    // 2. APIBay official torrent details endpoint (`t.php?id=...` returns real NFO/MediaInfo)
    if (torrent.indexer == 'APIBay' && torrent.sourceId != null) {
      final apiBayNfo = await _fetchApiBayNfo(torrent.sourceId!);
      if (apiBayNfo != null) return apiBayNfo;
    }

    // 3. Internet Archive metadata & `.nfo` file if present
    if (torrent.indexer == 'Internet Archive' && torrent.sourceId != null) {
      final iaNfo = await _fetchArchiveOrgNfo(torrent.sourceId!);
      if (iaNfo != null) return iaNfo;
    }

    // 4. Fallback summary from parsed metadata
    return NfoDetails(
      sourceLabel: 'Métadonnées locales (${torrent.indexer})',
      content: _buildLocalSummary(torrent),
      hasRawNfo: false,
    );
  }

  Future<NfoDetails?> _fetchApiBayNfo(String id) async {
    try {
      final uri = Uri.https('apibay.org', '/t.php', {'id': id});
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic>) return null;

      final descr = (data['descr'] ?? '').toString().trim();
      final numFiles = data['num_files'];
      final username = data['username'];
      final status = data['status'];

      final buf = StringBuffer();
      if (username != null && username.toString().isNotEmpty) {
        buf.writeln('Uploadeur : $username${status != null ? ' ($status)' : ''}');
      }
      if (numFiles != null) {
        buf.writeln('Nombre de fichiers : $numFiles');
      }
      if (buf.isNotEmpty) buf.writeln('${'─' * 42}\n');
      buf.write(descr.isNotEmpty ? descr : 'Aucune description NFO fournie par cet uploadeur.');

      return NfoDetails(
        sourceLabel: 'NFO / Description APIBay',
        content: _sanitizePlainText(buf.toString()),
        hasRawNfo: descr.isNotEmpty,
      );
    } catch (_) {
      return null;
    }
  }

  Future<NfoDetails?> _fetchYtsDetails(TorrentResult torrent) async {
    try {
      final uri = Uri.https('yts.mx', '/api/v2/movie_details.json', {
        'movie_id': torrent.sourceId!,
      });
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final movie = ((jsonDecode(resp.body) as Map<String, dynamic>)['data'] as Map?)?['movie']
          as Map<String, dynamic>?;
      if (movie == null) return null;

      final buf = StringBuffer();
      buf.writeln(torrent.nfoText ?? '');
      buf.writeln('─' * 42);
      if (movie['imdb_code'] != null) buf.writeln('IMDb      : ${movie['imdb_code']}');
      if (movie['rating'] != null) buf.writeln('Note IMDb : ${movie['rating']} / 10');
      if (movie['runtime'] != null && movie['runtime'] != 0) {
        buf.writeln('Durée     : ${movie['runtime']} min');
      }
      if (movie['genres'] is List) {
        buf.writeln('Genres    : ${(movie['genres'] as List).join(', ')}');
      }
      final desc = (movie['description_full'] ?? movie['summary'] ?? '').toString().trim();
      if (desc.isNotEmpty) {
        buf.writeln('\nSynopsis :\n$desc');
      }

      return NfoDetails(
        sourceLabel: 'Fiche technique YTS',
        content: _sanitizePlainText(buf.toString()),
        hasRawNfo: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<NfoDetails?> _fetchArchiveOrgNfo(String identifier) async {
    try {
      final uri = Uri.https('archive.org', '/metadata/$identifier');
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final meta = data['metadata'] as Map<String, dynamic>? ?? {};
      final files = (data['files'] as List? ?? []).whereType<Map<String, dynamic>>().toList();

      // If an actual `.nfo` file exists in the item, fetch its raw text
      String? rawNfoFileText;
      for (final f in files) {
        final name = (f['name'] ?? '').toString();
        if (name.toLowerCase().endsWith('.nfo')) {
          final nfoUri = Uri.https('archive.org', '/download/$identifier/$name');
          final nfoResp = await http.get(nfoUri, headers: _headers).timeout(_timeout);
          if (nfoResp.statusCode == 200 && nfoResp.body.isNotEmpty) {
            rawNfoFileText = nfoResp.body;
          }
          break;
        }
      }

      final buf = StringBuffer();
      if (rawNfoFileText != null) {
        buf.writeln(rawNfoFileText);
        buf.writeln('\n${'─' * 42}\n');
      }
      if (meta['title'] != null) buf.writeln('Titre       : ${meta['title']}');
      if (meta['year'] != null) buf.writeln('Année       : ${meta['year']}');
      if (meta['language'] != null) buf.writeln('Langue      : ${meta['language']}');
      if (meta['description'] != null) {
        final desc = meta['description'].toString().replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
        buf.writeln('\nDescription :\n$desc');
      }

      final mediaFiles = files
          .where((f) {
            final n = (f['name'] ?? '').toString().toLowerCase();
            return n.endsWith('.mp4') ||
                n.endsWith('.mkv') ||
                n.endsWith('.avi') ||
                n.endsWith('.ogv') ||
                n.endsWith('.srt');
          })
          .take(20)
          .toList();
      if (mediaFiles.isNotEmpty) {
        buf.writeln('\nFichiers média listés :');
        for (final f in mediaFiles) {
          final sz = int.tryParse(f['size']?.toString() ?? '0') ?? 0;
          buf.writeln('  • ${f['name']} (${ReleaseParser.formatSize(sz)})');
        }
      }

      return NfoDetails(
        sourceLabel: rawNfoFileText != null
            ? 'Fichier .NFO Internet Archive'
            : 'Métadonnées Internet Archive',
        content: _sanitizePlainText(buf.toString()),
        hasRawNfo: rawNfoFileText != null,
      );
    } catch (_) {
      return null;
    }
  }

  static String _buildLocalSummary(TorrentResult t) {
    final buf = StringBuffer()
      ..writeln('Titre       : ${t.title}')
      ..writeln('Source      : ${t.indexer}')
      ..writeln('Qualité     : ${t.quality}')
      ..writeln('Tags        : ${t.qualityTags.isEmpty ? '—' : t.qualityTags.join(', ')}')
      ..writeln(
        'Langues     : ${t.detectedLanguages.isEmpty ? 'Non précisée' : t.detectedLanguages.join(', ')}',
      )
      ..writeln('Taille      : ${t.sizeHuman}')
      ..writeln('Seeders     : ${t.seeders}')
      ..writeln('Leechers    : ${t.leechers}')
      ..writeln('Info-Hash   : ${t.infoHash ?? '—'}')
      ..writeln('')
      ..writeln(
        'Astuce : utilisez « Bac à sable (.torrent) » pour inspecter la liste complète des fichiers internes avant téléchargement.',
      );
    return buf.toString();
  }

  static String _sanitizePlainText(String raw) {
    // Strip control chars other than newline/tab and cap length
    final cleaned = raw.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    if (cleaned.length > _maxNfoChars) {
      return '${cleaned.substring(0, _maxNfoChars)}\n\n[... NFO tronqué à 64 Ko par sécurité ...]';
    }
    return cleaned.trim();
  }
}
