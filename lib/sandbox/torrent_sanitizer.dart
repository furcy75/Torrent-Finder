import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:safetorrent/models/safety_report.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/sandbox/bencode.dart';

/// Anti-malware `.torrent` inspector and clean rebuilder.
///
/// Inspects every single file declared inside `info` and blocks:
/// - Executables, scripts, installers, shortcuts, disk images, macro documents
/// - Double-extension spoofing (`Movie.mkv.exe`) and trailing space/dot tricks
/// - Unicode Right-To-Left Override (RTLO `\u202e`) filename spoofing
/// - Path traversal (`..`, absolute paths, Windows drive letters, control chars)
/// - Optional blocking of password-scam archives (`.zip`, `.rar`, `.7z`)
/// - Fake torrents containing zero video files (in strict video mode)
///
/// Rebuilds a minimal clean `.torrent` keeping only valid `announce`,
/// `announce-list`, and the bit-exact `info` dictionary (preserving SHA-1 info_hash).
class TorrentSanitizer {
  static const Set<String> blockedExtensions = {
    // Windows executables & installers
    '.exe', '.msi', '.msp', '.com', '.scr', '.pif', '.bat', '.cmd',
    '.cpl', '.dll', '.sys', '.drv', '.ocx', '.inf', '.reg', '.msc',
    '.application',
    // Shortcuts & launchers
    '.lnk', '.url', '.desktop', '.webloc',
    // Scripts & runtimes
    '.vbs', '.vbe', '.js', '.jse', '.wsf', '.wsh', '.ps1', '.psm1',
    '.psd1', '.hta', '.jar', '.jnlp', '.py', '.pyw', '.rb', '.pl',
    '.php', '.sh', '.bash', '.zsh', '.csh', '.ksh',
    // Mobile / desktop packages
    '.apk', '.ipa', '.dmg', '.pkg', '.app', '.deb', '.rpm',
    '.appimage', '.run', '.bin', '.elf',
    // Disk images & help files
    '.iso', '.img', '.vhd', '.vhdx', '.chm', '.cab',
    // Macro office docs & active web pages
    '.docm', '.xlsm', '.pptm', '.dotm', '.html', '.htm', '.svg', '.swf',
  };

  static const Set<String> archiveExtensions = {
    '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.tgz', '.z',
  };

  static const Set<String> videoExtensions = {
    '.mkv', '.mp4', '.avi', '.mov', '.m4v', '.webm', '.ts', '.m2ts',
    '.mts', '.mpg', '.mpeg', '.ogv', '.ogm', '.flv', '.wmv', '.vob',
  };

  static const Set<String> subtitleExtensions = {
    '.srt', '.sub', '.idx', '.ass', '.ssa', '.vtt', '.sup', '.smi',
  };

  static const Set<String> benignMetadataExtensions = {
    '.nfo', '.txt', '.jpg', '.jpeg', '.png', '.webp', '.sfv', '.md5',
  };

  static const Set<String> allowedTrackerSchemes = {
    'http', 'https', 'udp', 'ws', 'wss',
  };

  static const Set<int> bidiControlRunes = {
    0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
    0x2066, 0x2067, 0x2068, 0x2069,
  };

  static final List<RegExp> suspiciousNamePatterns = [
    RegExp(r'\bcodec[\s._-]*(required|install|setup|pack)\b', caseSensitive: false),
    RegExp(r'\bpassword[\s._-]*(\.txt|here|read)\b', caseSensitive: false),
    RegExp(r'\bread[\s._-]*me[\s._-]*to[\s._-]*watch\b', caseSensitive: false),
  ];

  static final RegExp _winDrivePattern = RegExp(r'^[A-Za-z]:');

  static SandboxExecutionResult inspectAndSanitize(
    Uint8List rawBytes, {
    bool strictVideoOnly = true,
    bool blockArchives = true,
    String sandboxMode = 'Isolate mémoire isolé',
  }) {
    late final DecodedTorrentRoot decoded;
    try {
      decoded = Bencode.decodeWithInfoBytes(rawBytes);
    } on BencodeException catch (e) {
      return SandboxExecutionResult(
        report: SafetyReport(
          status: SafetyStatus.blocked,
          safeToDownload: false,
          blockedReasons: ['Fichier .torrent invalide ou corrompu : ${e.message}'],
          sandboxMode: sandboxMode,
        ),
      );
    }

    final root = decoded.root;
    final rawInfoBytes = decoded.rawInfoBytes;
    final info = root['info'] as Map<String, Object?>;
    final infoHash = sha1.convert(rawInfoBytes).toString().toLowerCase();

    final rawName = info['name.utf-8'] ?? info['name'];
    if (rawName is! Uint8List || rawName.isEmpty) {
      return SandboxExecutionResult(
        report: SafetyReport(
          status: SafetyStatus.blocked,
          safeToDownload: false,
          infoHash: infoHash,
          blockedReasons: ['Champ "info.name" absent ou invalide'],
          sandboxMode: sandboxMode,
        ),
      );
    }

    final pieceLength = info['piece length'];
    final pieces = info['pieces'];
    if (pieceLength is! int || pieceLength <= 0) {
      return SandboxExecutionResult(
        report: SafetyReport(
          status: SafetyStatus.blocked,
          safeToDownload: false,
          infoHash: infoHash,
          blockedReasons: ['Champ "piece length" invalide'],
          sandboxMode: sandboxMode,
        ),
      );
    }
    if (pieces is! Uint8List || pieces.isEmpty || pieces.length % 20 != 0) {
      return SandboxExecutionResult(
        report: SafetyReport(
          status: SafetyStatus.blocked,
          safeToDownload: false,
          infoHash: infoHash,
          blockedReasons: ['Champ "pieces" (empreintes SHA-1 des blocs) invalide'],
          sandboxMode: sandboxMode,
        ),
      );
    }

    final torrentName = utf8.decode(rawName, allowMalformed: true);
    final blockedReasons = <String>[];
    final warnings = <String>[];
    final entries = <TorrentFileEntry>[];

    final rootNameErr = _validateSegments([torrentName]);
    if (rootNameErr != null) {
      blockedReasons.add('Nom racine dangereux : $rootNameErr');
    }

    final rawFiles = <(List<String>, int)>[];
    final infoFiles = info['files'];
    if (infoFiles is List) {
      for (final fObj in infoFiles) {
        if (fObj is! Map<String, Object?>) {
          blockedReasons.add('Entrée de fichier malformée dans info.files');
          continue;
        }
        final fLen = fObj['length'];
        final fPath = fObj['path.utf-8'] ?? fObj['path'];
        if (fLen is! int || fLen < 0 || fPath is! List) {
          blockedReasons.add('Métadonnées de fichier invalides dans info.files');
          continue;
        }
        final segs = fPath
            .whereType<Uint8List>()
            .map((b) => utf8.decode(b, allowMalformed: true))
            .toList();
        rawFiles.add((segs, fLen));
      }
    } else if (info['length'] is int) {
      final fLen = info['length'] as int;
      if (fLen < 0) {
        blockedReasons.add('Taille de fichier négative');
      } else {
        rawFiles.add(([torrentName], fLen));
      }
    } else {
      blockedReasons.add('Aucun fichier déclaré dans le dictionnaire info');
    }

    var totalSize = 0;
    var videoCount = 0;

    for (final (segments, sizeBytes) in rawFiles) {
      totalSize += sizeBytes;
      final relPath = segments.join('/');
      final pathErr = _validateSegments(segments);
      final fileName = segments.isNotEmpty ? segments.last : '';
      final ext = _extractExtension(fileName);

      String? flaggedReason;
      FileCategory category;

      if (pathErr != null) {
        category = FileCategory.blocked;
        flaggedReason = pathErr;
        blockedReasons.add('$relPath : $pathErr');
      } else if (blockedExtensions.contains(ext)) {
        category = FileCategory.blocked;
        flaggedReason = 'Extension dangereuse interdite ($ext)';
        blockedReasons.add('Fichier exécutable/script bloqué : $relPath');
      } else if (blockArchives && archiveExtensions.contains(ext)) {
        category = FileCategory.blocked;
        flaggedReason = 'Archive potentiellement piégée bloquée ($ext)';
        blockedReasons.add('Archive bloquée par sécurité : $relPath');
      } else if (videoExtensions.contains(ext)) {
        category = FileCategory.video;
        videoCount++;
      } else if (subtitleExtensions.contains(ext)) {
        category = FileCategory.subtitle;
      } else if (benignMetadataExtensions.contains(ext)) {
        category = FileCategory.metadata;
        for (final pat in suspiciousNamePatterns) {
          if (pat.hasMatch(fileName)) {
            flaggedReason = 'Nom de fichier potentiellement trompeur';
            warnings.add('Fichier texte suspect détecté : $relPath');
            break;
          }
        }
      } else {
        category = FileCategory.unknown;
        if (strictVideoOnly) {
          flaggedReason =
              'Extension non reconnue en mode strict (${ext.isEmpty ? 'sans extension' : ext})';
          warnings.add('Extension inhabituelle : $relPath');
        }
      }

      if (entries.length < 200) {
        entries.add(
          TorrentFileEntry(
            path: relPath,
            sizeBytes: sizeBytes,
            extension: ext,
            category: category,
            flaggedReason: flaggedReason,
          ),
        );
      }
    }

    if (videoCount == 0 && blockedReasons.isEmpty) {
      if (strictVideoOnly) {
        blockedReasons.add(
          'Aucun fichier vidéo (.mkv, .mp4, .avi...) trouvé dans ce torrent — probablement un faux torrent.',
        );
      } else {
        warnings.add('Aucun fichier vidéo détecté dans ce torrent.');
      }
    }

    if (totalSize > 0 && totalSize < 15 * 1024 * 1024 && videoCount > 0) {
      final mb = (totalSize / (1024 * 1024)).toStringAsFixed(1);
      warnings.add('Taille totale très faible ($mb Mo) pour un film complet.');
    }

    if (blockedReasons.isNotEmpty) {
      return SandboxExecutionResult(
        report: SafetyReport(
          status: SafetyStatus.blocked,
          safeToDownload: false,
          infoHash: infoHash,
          torrentName: torrentName,
          totalSizeBytes: totalSize,
          fileCount: rawFiles.length,
          videoFileCount: videoCount,
          files: entries,
          blockedReasons: blockedReasons,
          warnings: warnings,
          sandboxMode: sandboxMode,
        ),
      );
    }

    final (sanitizedBytes, removedFields) = _rebuildCleanTorrent(root, rawInfoBytes);
    final status = warnings.isNotEmpty ? SafetyStatus.warning : SafetyStatus.safe;

    return SandboxExecutionResult(
      report: SafetyReport(
        status: status,
        safeToDownload: true,
        infoHash: infoHash,
        torrentName: torrentName,
        totalSizeBytes: totalSize,
        fileCount: rawFiles.length,
        videoFileCount: videoCount,
        files: entries,
        warnings: warnings,
        sanitizedFieldsRemoved: removedFields,
        sandboxMode: sandboxMode,
      ),
      sanitizedBytes: sanitizedBytes,
    );
  }

  static String? _validateSegments(List<String> segments) {
    if (segments.isEmpty) return 'Chemin de fichier vide';
    for (final seg in segments) {
      if (seg.isEmpty || seg == '.' || seg == '..') {
        return 'Tentative de traversée de répertoire détectée ("$seg")';
      }
      if (seg.contains('/') || seg.contains(r'\')) {
        return 'Séparateur de chemin interdit dans "$seg"';
      }
      if (_winDrivePattern.hasMatch(seg)) {
        return 'Chemin absolu Windows interdit ("$seg")';
      }
      for (final rune in seg.runes) {
        if (rune < 32 || rune == 127) {
          return 'Caractères de contrôle interdits dans le nom de fichier';
        }
        if (bidiControlRunes.contains(rune)) {
          return 'Caractère Unicode RTLO (usurpation d\'extension) détecté';
        }
      }
    }
    return null;
  }

  static String _extractExtension(String fileName) {
    final trimmed = fileName.replaceFirst(RegExp(r'[\s.]+$'), '');
    final dot = trimmed.lastIndexOf('.');
    if (dot <= 0 || dot == trimmed.length - 1) return '';
    return trimmed.substring(dot).toLowerCase();
  }

  static bool _isValidTrackerUrl(Uint8List rawUrl) {
    try {
      final url = utf8.decode(rawUrl, allowMalformed: false);
      final uri = Uri.tryParse(url);
      if (uri == null) return false;
      return allowedTrackerSchemes.contains(uri.scheme.toLowerCase()) &&
          uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static (Uint8List, List<String>) _rebuildCleanTorrent(
    Map<String, Object?> root,
    Uint8List rawInfoBytes,
  ) {
    const kept = {'announce', 'announce-list', 'info'};
    final removed = root.keys.where((k) => !kept.contains(k)).toList()..sort();

    final encodedEntries = <(String, Uint8List)>[];

    final announce = root['announce'];
    if (announce is Uint8List && _isValidTrackerUrl(announce)) {
      encodedEntries.add(('announce', Bencode.encode(announce)));
    }

    final announceList = root['announce-list'];
    if (announceList is List) {
      final cleanTiers = <List<Uint8List>>[];
      for (final tier in announceList) {
        if (tier is List) {
          final valid = tier
              .whereType<Uint8List>()
              .where(_isValidTrackerUrl)
              .toList();
          if (valid.isNotEmpty) {
            cleanTiers.add(valid);
          }
        }
      }
      if (cleanTiers.isNotEmpty) {
        encodedEntries.add(('announce-list', Bencode.encode(cleanTiers)));
      }
    }

    // Inject raw `info` dictionary bytes verbatim to preserve bit-exact SHA-1 info_hash
    encodedEntries.add(('info', rawInfoBytes));
    encodedEntries.sort((a, b) => a.$1.compareTo(b.$1));

    final out = BytesBuilder(copy: false);
    out.addByte(0x64); // 'd'
    for (final (key, encodedVal) in encodedEntries) {
      final keyBytes = Uint8List.fromList(latin1.encode(key));
      out.add(ascii.encode('${keyBytes.length}:'));
      out.add(keyBytes);
      out.add(encodedVal);
    }
    out.addByte(0x65); // 'e'

    return (out.toBytes(), removed);
  }
}
