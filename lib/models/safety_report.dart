import 'dart:typed_data';

import 'package:safetorrent/models/torrent_result.dart';

enum FileCategory {
  video,
  subtitle,
  metadata,
  blocked,
  unknown,
}

class TorrentFileEntry {
  const TorrentFileEntry({
    required this.path,
    required this.sizeBytes,
    required this.extension,
    required this.category,
    this.flaggedReason,
  });

  final String path;
  final int sizeBytes;
  final String extension;
  final FileCategory category;
  final String? flaggedReason;
}

class SafetyReport {
  const SafetyReport({
    required this.status,
    required this.safeToDownload,
    this.infoHash,
    this.torrentName,
    this.totalSizeBytes = 0,
    this.fileCount = 0,
    this.videoFileCount = 0,
    this.files = const [],
    this.blockedReasons = const [],
    this.warnings = const [],
    this.sanitizedFieldsRemoved = const [],
    this.sandboxMode = 'Isolate mémoire isolé',
  });

  final SafetyStatus status;
  final bool safeToDownload;
  final String? infoHash;
  final String? torrentName;
  final int totalSizeBytes;
  final int fileCount;
  final int videoFileCount;
  final List<TorrentFileEntry> files;
  final List<String> blockedReasons;
  final List<String> warnings;
  final List<String> sanitizedFieldsRemoved;
  final String sandboxMode;
}

class SandboxExecutionResult {
  const SandboxExecutionResult({
    required this.report,
    this.sanitizedBytes,
  });

  final SafetyReport report;
  final Uint8List? sanitizedBytes;
}
