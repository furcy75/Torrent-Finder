/// Local TorBox profile backed by the user's official TorBox API key.
class TorboxProfile {
  const TorboxProfile({
    required this.id,
    required this.label,
    required this.apiKey,
    this.email,
    this.plan = 0,
    this.isSubscribed = false,
    this.cooldownUntil,
    this.totalDownloaded = 0,
    this.lastSyncedAt,
  });

  final String id;
  final String label;
  final String apiKey;
  final String? email;

  /// TorBox official plan ID: 0 = Free, 1 = Essential, 2 = Pro, 3 = Standard.
  final int plan;
  final bool isSubscribed;

  /// Official cooldown timestamp returned by `/v1/api/user/me` (if any).
  final DateTime? cooldownUntil;
  final int totalDownloaded;
  final DateTime? lastSyncedAt;

  bool get isPremium => isSubscribed || plan > 0;

  String get planLabel => switch (plan) {
        1 => 'Premium Essential',
        2 => 'Premium Pro',
        3 => 'Premium Standard',
        _ => isSubscribed ? 'Premium' : 'Gratuit',
      };

  /// Remaining cooldown duration for non-premium accounts (Duration.zero if ready or premium).
  Duration remainingCooldown([DateTime? now]) {
    if (isPremium || cooldownUntil == null) return Duration.zero;
    final ref = (now ?? DateTime.now().toUtc()).toUtc();
    final diff = cooldownUntil!.toUtc().difference(ref);
    return diff.isNegative ? Duration.zero : diff;
  }

  bool isInCooldown([DateTime? now]) => remainingCooldown(now) > Duration.zero;

  static String formatDuration(Duration d) {
    if (d <= Duration.zero) return 'Disponible';
    final hours = d.inHours;
    final mins = d.inMinutes.remainder(60);
    final secs = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${mins.toString().padLeft(2, '0')}m';
    }
    return '${mins}m ${secs.toString().padLeft(2, '0')}s';
  }

  TorboxProfile copyWith({
    String? label,
    String? apiKey,
    String? email,
    int? plan,
    bool? isSubscribed,
    DateTime? cooldownUntil,
    bool clearCooldown = false,
    int? totalDownloaded,
    DateTime? lastSyncedAt,
  }) {
    return TorboxProfile(
      id: id,
      label: label ?? this.label,
      apiKey: apiKey ?? this.apiKey,
      email: email ?? this.email,
      plan: plan ?? this.plan,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      cooldownUntil: clearCooldown ? null : (cooldownUntil ?? this.cooldownUntil),
      totalDownloaded: totalDownloaded ?? this.totalDownloaded,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'apiKey': apiKey,
        'email': email,
        'plan': plan,
        'isSubscribed': isSubscribed,
        'cooldownUntil': cooldownUntil?.toUtc().toIso8601String(),
        'totalDownloaded': totalDownloaded,
        'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
      };

  factory TorboxProfile.fromJson(Map<String, dynamic> json) => TorboxProfile(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? 'Mon compte',
        apiKey: json['apiKey'] as String? ?? '',
        email: json['email'] as String?,
        plan: (json['plan'] as num?)?.toInt() ?? 0,
        isSubscribed: json['isSubscribed'] as bool? ?? false,
        cooldownUntil: json['cooldownUntil'] != null
            ? DateTime.tryParse(json['cooldownUntil'] as String)
            : null,
        totalDownloaded: (json['totalDownloaded'] as num?)?.toInt() ?? 0,
        lastSyncedAt: json['lastSyncedAt'] != null
            ? DateTime.tryParse(json['lastSyncedAt'] as String)
            : null,
      );
}

class TorboxFileItem {
  const TorboxFileItem({
    required this.id,
    required this.name,
    required this.shortName,
    required this.sizeBytes,
  });

  final int id;
  final String name;
  final String shortName;
  final int sizeBytes;

  bool get isVideo {
    final low = name.toLowerCase();
    return low.endsWith('.mkv') ||
        low.endsWith('.mp4') ||
        low.endsWith('.avi') ||
        low.endsWith('.mov') ||
        low.endsWith('.m4v') ||
        low.endsWith('.webm');
  }

  factory TorboxFileItem.fromJson(Map<String, dynamic> json) => TorboxFileItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] ?? 'Fichier').toString(),
        shortName: (json['short_name'] ?? json['name'] ?? 'Fichier').toString(),
        sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
      );
}

class TorboxTorrentItem {
  const TorboxTorrentItem({
    required this.id,
    required this.name,
    required this.hash,
    required this.sizeBytes,
    required this.progress,
    required this.downloadSpeed,
    required this.seeds,
    required this.downloadState,
    required this.active,
    required this.downloadFinished,
    required this.cached,
    required this.files,
  });

  final int id;
  final String name;
  final String hash;
  final int sizeBytes;
  final double progress; // 0.0..1.0
  final int downloadSpeed;
  final int seeds;
  final String downloadState;
  final bool active;
  final bool downloadFinished;
  final bool cached;
  final List<TorboxFileItem> files;

  double get progressPercent => (progress * 100.0).clamp(0.0, 100.0);

  factory TorboxTorrentItem.fromJson(Map<String, dynamic> json) {
    final rawProg = (json['progress'] as num?)?.toDouble() ?? 0.0;
    final normalizedProg = rawProg > 1.0 ? (rawProg / 100.0).clamp(0.0, 1.0) : rawProg.clamp(0.0, 1.0);
    return TorboxTorrentItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? 'Torrent').toString(),
      hash: (json['hash'] ?? '').toString(),
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
      progress: normalizedProg,
      downloadSpeed: (json['download_speed'] as num?)?.toInt() ?? 0,
      seeds: (json['seeds'] as num?)?.toInt() ?? 0,
      downloadState: (json['download_state'] ?? '').toString(),
      active: json['active'] == true,
      downloadFinished: json['download_finished'] == true || json['download_present'] == true,
      cached: json['cached'] == true,
      files: (json['files'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TorboxFileItem.fromJson)
          .toList(),
    );
  }
}
