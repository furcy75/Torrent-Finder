/// Local Seedr OAuth session (password is NEVER persisted on disk).
class SeedrSession {
  const SeedrSession({
    required this.accessToken,
    this.refreshToken,
    required this.authMode, // 'device' or 'password'
    this.username,
    this.email,
    this.packageName,
  });

  final String accessToken;
  final String? refreshToken;
  final String authMode;
  final String? username;
  final String? email;
  final String? packageName;

  bool get isValid => accessToken.trim().isNotEmpty;

  SeedrSession copyWith({
    String? accessToken,
    String? refreshToken,
    String? authMode,
    String? username,
    String? email,
    String? packageName,
  }) {
    return SeedrSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      authMode: authMode ?? this.authMode,
      username: username ?? this.username,
      email: email ?? this.email,
      packageName: packageName ?? this.packageName,
    );
  }

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'authMode': authMode,
        'username': username,
        'email': email,
        'packageName': packageName,
      };

  factory SeedrSession.fromJson(Map<String, dynamic> json) => SeedrSession(
        accessToken: json['accessToken'] as String? ?? '',
        refreshToken: json['refreshToken'] as String?,
        authMode: json['authMode'] as String? ?? 'device',
        username: json['username'] as String?,
        email: json['email'] as String?,
        packageName: json['packageName'] as String?,
      );
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
