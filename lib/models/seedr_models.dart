/// Local Seedr OAuth account session (password is NEVER persisted on disk).
/// Supports multiple named family accounts (e.g., "Moi", "Sœur", "Fille").
class SeedrSession {
  const SeedrSession({
    required this.id,
    required this.label,
    required this.accessToken,
    this.refreshToken,
    this.deviceCode,
    required this.authMode, // 'device' or 'password'
    this.username,
    this.email,
    this.packageName,
    this.lastSpaceUsed,
    this.lastSpaceMax,
  });

  final String id;
  final String label;
  final String accessToken;
  final String? refreshToken;
  final String? deviceCode;
  final String authMode;
  final String? username;
  final String? email;
  final String? packageName;
  final int? lastSpaceUsed;
  final int? lastSpaceMax;

  bool get isValid => accessToken.trim().isNotEmpty;

  String get displayName {
    final trimmed = label.trim();
    if (trimmed.isNotEmpty) return trimmed;
    if (username != null && username!.trim().isNotEmpty) return username!.trim();
    if (email != null && email!.trim().isNotEmpty) return email!.trim();
    return 'Compte Seedr';
  }

  int? get lastSpaceFree {
    if (lastSpaceMax == null || lastSpaceMax! <= 0 || lastSpaceUsed == null) {
      return null;
    }
    return (lastSpaceMax! - lastSpaceUsed!).clamp(0, lastSpaceMax!);
  }

  double get usedRatio {
    if (lastSpaceMax == null || lastSpaceMax! <= 0 || lastSpaceUsed == null) {
      return 0.0;
    }
    return (lastSpaceUsed! / lastSpaceMax!).clamp(0.0, 1.0);
  }

  /// Returns whether cached free quota is known to be enough for [requiredBytes].
  /// Returns `null` when quota or torrent size is unknown.
  bool? fitsTorrentSize(int requiredBytes) {
    final free = lastSpaceFree;
    if (free == null || requiredBytes <= 0) return null;
    return free >= requiredBytes;
  }

  SeedrSession copyWith({
    String? id,
    String? label,
    String? accessToken,
    String? refreshToken,
    String? deviceCode,
    String? authMode,
    String? username,
    String? email,
    String? packageName,
    int? lastSpaceUsed,
    int? lastSpaceMax,
  }) {
    return SeedrSession(
      id: id ?? this.id,
      label: label ?? this.label,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      deviceCode: deviceCode ?? this.deviceCode,
      authMode: authMode ?? this.authMode,
      username: username ?? this.username,
      email: email ?? this.email,
      packageName: packageName ?? this.packageName,
      lastSpaceUsed: lastSpaceUsed ?? this.lastSpaceUsed,
      lastSpaceMax: lastSpaceMax ?? this.lastSpaceMax,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'deviceCode': deviceCode,
        'authMode': authMode,
        'username': username,
        'email': email,
        'packageName': packageName,
        'lastSpaceUsed': lastSpaceUsed,
        'lastSpaceMax': lastSpaceMax,
      };

  factory SeedrSession.fromJson(Map<String, dynamic> json) {
    final username = json['username'] as String?;
    final email = json['email'] as String?;
    final rawLabel = (json['label'] as String? ?? '').trim();
    final fallbackLabel = rawLabel.isNotEmpty
        ? rawLabel
        : (username != null && username.trim().isNotEmpty
            ? username.trim()
            : (email != null && email.trim().isNotEmpty ? email.trim() : 'Compte principal'));
    return SeedrSession(
      id: (json['id'] as String? ?? 'seedr_default').trim(),
      label: fallbackLabel,
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String?,
      deviceCode: json['deviceCode'] as String?,
      authMode: json['authMode'] as String? ?? 'device',
      username: username,
      email: email,
      packageName: json['packageName'] as String?,
      lastSpaceUsed: (json['lastSpaceUsed'] as num?)?.toInt(),
      lastSpaceMax: (json['lastSpaceMax'] as num?)?.toInt(),
    );
  }
}

/// Live quota snapshot for a single Seedr account, used in the manual account picker.
class SeedrAccountQuota {
  const SeedrAccountQuota({
    required this.account,
    this.spaceUsed,
    this.spaceMax,
    this.error,
  });

  final SeedrSession account;
  final int? spaceUsed;
  final int? spaceMax;
  final String? error;

  int? get spaceFree {
    if (spaceMax == null || spaceMax! <= 0 || spaceUsed == null) return null;
    return (spaceMax! - spaceUsed!).clamp(0, spaceMax!);
  }

  double get usedRatio {
    if (spaceMax == null || spaceMax! <= 0 || spaceUsed == null) return 0.0;
    return (spaceUsed! / spaceMax!).clamp(0.0, 1.0);
  }

  /// Whether this account has enough free quota for [requiredBytes].
  /// Returns `null` when either quota or size is unknown.
  bool? canFit(int requiredBytes) {
    final free = spaceFree;
    if (free == null || requiredBytes <= 0) return null;
    return free >= requiredBytes;
  }
}

class SeedrDeviceCode {
  const SeedrDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.intervalSeconds,
    required this.expiresInSeconds,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int intervalSeconds;
  final int expiresInSeconds;
}

class SeedrTorrentTransfer {
  const SeedrTorrentTransfer({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.progress,
    required this.downloadRate,
    required this.seeders,
    required this.leechers,
    this.warnings,
  });

  final String id;
  final String name;
  final int sizeBytes;
  final double progress;
  final int downloadRate;
  final int seeders;
  final int leechers;
  final String? warnings;

  factory SeedrTorrentTransfer.fromJson(Map<String, dynamic> json) {
    final progRaw = json['progress'];
    final prog = progRaw is num
        ? progRaw.toDouble()
        : double.tryParse(progRaw?.toString() ?? '0') ?? 0.0;
    return SeedrTorrentTransfer(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Transfert').toString(),
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
      progress: prog.clamp(0.0, 100.0),
      downloadRate: (json['download_rate'] as num?)?.toInt() ?? 0,
      seeders: (json['seeders'] as num?)?.toInt() ?? 0,
      leechers: (json['leechers'] as num?)?.toInt() ?? 0,
      warnings: json['warnings']?.toString(),
    );
  }
}

class SeedrFolderEntry {
  const SeedrFolderEntry({
    required this.id,
    required this.name,
    required this.sizeBytes,
    this.lastUpdate,
    this.playVideo = false,
  });

  final String id;
  final String name;
  final int sizeBytes;
  final String? lastUpdate;
  final bool playVideo;

  factory SeedrFolderEntry.fromJson(Map<String, dynamic> json) => SeedrFolderEntry(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? json['fullname'] ?? 'Dossier').toString(),
        sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
        lastUpdate: json['last_update']?.toString(),
        playVideo: json['play_video'] == true,
      );
}

class SeedrFileEntry {
  const SeedrFileEntry({
    required this.folderFileId,
    required this.name,
    required this.sizeBytes,
    this.playVideo = false,
    this.playAudio = false,
  });

  final String folderFileId;
  final String name;
  final int sizeBytes;
  final bool playVideo;
  final bool playAudio;

  factory SeedrFileEntry.fromJson(Map<String, dynamic> json) => SeedrFileEntry(
        folderFileId: (json['folder_file_id'] ?? json['file_id'] ?? '').toString(),
        name: (json['name'] ?? 'Fichier').toString(),
        sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
        playVideo: json['play_video'] == true,
        playAudio: json['play_audio'] == true,
      );
}

class SeedrFolderContents {
  const SeedrFolderContents({
    required this.folderId,
    required this.name,
    required this.parentId,
    required this.spaceUsed,
    required this.spaceMax,
    required this.torrents,
    required this.folders,
    required this.files,
  });

  final String folderId;
  final String name;
  final String? parentId;
  final int spaceUsed;
  final int spaceMax;
  final List<SeedrTorrentTransfer> torrents;
  final List<SeedrFolderEntry> folders;
  final List<SeedrFileEntry> files;

  int get spaceFree => spaceMax > 0 ? (spaceMax - spaceUsed).clamp(0, spaceMax) : 0;

  double get usedRatio => spaceMax > 0 ? (spaceUsed / spaceMax).clamp(0.0, 1.0) : 0.0;

  factory SeedrFolderContents.fromJson(Map<String, dynamic> json) {
    final parentRaw = json['parent']?.toString();
    return SeedrFolderContents(
      folderId: (json['folder_id'] ?? '0').toString(),
      name: (json['name'] ?? 'Mon espace Seedr').toString(),
      parentId: (parentRaw != null && parentRaw != '-1' && parentRaw.isNotEmpty) ? parentRaw : null,
      spaceUsed: (json['space_used'] as num?)?.toInt() ?? 0,
      spaceMax: (json['space_max'] as num?)?.toInt() ?? 0,
      torrents: (json['torrents'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SeedrTorrentTransfer.fromJson)
          .toList(),
      folders: (json['folders'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SeedrFolderEntry.fromJson)
          .toList(),
      files: (json['files'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SeedrFileEntry.fromJson)
          .toList(),
    );
  }
}
