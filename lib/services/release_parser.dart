import 'package:safetorrent/models/torrent_result.dart';

/// Extracts video quality, codec, language flags (FR/EN/ES/MULTI),
/// human-readable size, and static pre-scan warnings from torrent titles.
class ReleaseParser {
  static final List<(String, RegExp)> _resolutions = [
    ('4K 2160p', RegExp(r'\b(2160p|4k|uhd)\b', caseSensitive: false)),
    ('1080p', RegExp(r'\b1080[pi]\b', caseSensitive: false)),
    ('720p', RegExp(r'\b720p\b', caseSensitive: false)),
    ('480p', RegExp(r'\b(480p|576p)\b', caseSensitive: false)),
  ];

  static final List<(String, RegExp)> _sources = [
    ('REMUX', RegExp(r'\bremux\b', caseSensitive: false)),
    ('BluRay', RegExp(r'\b(blu[\s._-]?ray|bdrip|brrip|bdremux)\b', caseSensitive: false)),
    ('WEB-DL', RegExp(r'\bweb[\s._-]?dl\b', caseSensitive: false)),
    ('WEBRip', RegExp(r'\bweb[\s._-]?rip\b', caseSensitive: false)),
    ('HDRip', RegExp(r'\bhdrip\b', caseSensitive: false)),
    ('DVDRip', RegExp(r'\bdvd[\s._-]?rip\b', caseSensitive: false)),
    ('HDTV', RegExp(r'\bhdtv\b', caseSensitive: false)),
    (
      'CAM/TS',
      RegExp(
        r'\b(hdcam|camrip|cam|telesync|hdts|ts|tc|telecine|screener|dvdscr)\b',
        caseSensitive: false,
      ),
    ),
  ];

  static final List<(String, RegExp)> _extraTags = [
    ('HDR', RegExp(r'\b(hdr10\+?|hdr|dolby[\s._-]?vision|dv)\b', caseSensitive: false)),
    ('x265', RegExp(r'\b(x265|h\.?265|hevc)\b', caseSensitive: false)),
    ('x264', RegExp(r'\b(x264|h\.?264|avc)\b', caseSensitive: false)),
    ('AV1', RegExp(r'\bav1\b', caseSensitive: false)),
  ];

  static final RegExp _langFr = RegExp(
    r'\b(truefrench|french|vff|vfq|vfi|vf2|vf|vostfr|subfrench|fr[\s._-]?sub|fre|fra)\b',
    caseSensitive: false,
  );
  static final RegExp _langEs = RegExp(
    r'\b(spanish|castellano|latino|espanol|español|esp|spa|subesp|vose|lat)\b',
    caseSensitive: false,
  );
  static final RegExp _langEn = RegExp(
    r'\b(english|eng|vo|usa|uk)\b',
    caseSensitive: false,
  );
  static final RegExp _langMulti = RegExp(
    r'\b(multi|dual[\s._-]?audio)\b',
    caseSensitive: false,
  );

  static final List<(String, RegExp)> _suspiciousTitlePatterns = [
    (
      'Extension exécutable dans le titre',
      RegExp(r'\.(exe|msi|bat|cmd|scr|lnk|vbs|ps1|apk|iso)\b', caseSensitive: false),
    ),
    (
      'Archive compressée suspecte',
      RegExp(r'\.(zip|rar|7z)\b', caseSensitive: false),
    ),
    (
      'Mention suspecte (mot de passe / codec)',
      RegExp(r'\b(password|pass\s*word|codec[\s._-]?pack|setup)\b', caseSensitive: false),
    ),
  ];

  static final RegExp _camWarningPattern = RegExp(
    r'\b(hdcam|camrip|cam|telesync|hdts)\b',
    caseSensitive: false,
  );

  static String formatSize(int sizeBytes) {
    if (sizeBytes <= 0) return '—';
    const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
    var val = sizeBytes.toDouble();
    var idx = 0;
    while (val >= 1024 && idx < units.length - 1) {
      val /= 1024;
      idx++;
    }
    return idx <= 1 ? '${val.round()} ${units[idx]}' : '${val.toStringAsFixed(2)} ${units[idx]}';
  }

  static (String, List<String>) parseQuality(String title, {String? explicitQuality}) {
    var resolution = '';
    for (final (label, pat) in _resolutions) {
      if (pat.hasMatch(title) || (explicitQuality != null && pat.hasMatch(explicitQuality))) {
        resolution = label;
        break;
      }
    }

    var source = '';
    for (final (label, pat) in _sources) {
      if (pat.hasMatch(title) || (explicitQuality != null && pat.hasMatch(explicitQuality))) {
        source = label;
        break;
      }
    }

    final tags = <String>[];
    if (resolution.isNotEmpty) tags.add(resolution);
    if (source.isNotEmpty) tags.add(source);
    for (final (label, pat) in _extraTags) {
      if (pat.hasMatch(title)) tags.add(label);
    }

    String primary;
    if (resolution.isNotEmpty && source.isNotEmpty) {
      primary = '$resolution $source';
    } else if (resolution.isNotEmpty) {
      primary = resolution;
    } else if (source.isNotEmpty) {
      primary = source;
    } else if (explicitQuality != null && explicitQuality.trim().isNotEmpty) {
      primary = explicitQuality.trim();
    } else {
      primary = 'Standard';
    }
    return (primary, tags);
  }

  static List<String> detectLanguages(String title, {String? defaultLang}) {
    final found = <String>[];
    if (_langMulti.hasMatch(title)) found.add('MULTI');
    if (_langFr.hasMatch(title)) found.add('FR');
    if (_langEs.hasMatch(title)) found.add('ES');
    if (_langEn.hasMatch(title)) found.add('EN');
    if (found.isEmpty && defaultLang != null && defaultLang.isNotEmpty) {
      found.add(defaultLang.toUpperCase());
    }
    return found;
  }

  static bool matchesLanguage(List<String> detected, LanguageFilter requested) {
    if (requested == LanguageFilter.all) return true;
    final upper = detected.map((e) => e.toUpperCase()).toSet();
    if (upper.contains('MULTI')) return true;
    if (upper.contains(requested.code.toUpperCase())) return true;
    if (requested == LanguageFilter.en && !upper.contains('FR') && !upper.contains('ES')) {
      return true;
    }
    return false;
  }

  static (SafetyStatus, List<String>) preScanTitle(
    String title,
    int sizeBytes,
    int seeders,
  ) {
    for (final (reason, pat) in _suspiciousTitlePatterns) {
      if (pat.hasMatch(title)) {
        return (SafetyStatus.blocked, [reason]);
      }
    }
    final warnings = <String>[];
    if (_camWarningPattern.hasMatch(title)) {
      warnings.add('Qualité cinéma filmée (CAM/TS)');
    }
    if (sizeBytes > 0 && sizeBytes < 50 * 1024 * 1024) {
      warnings.add('Taille très petite (< 50 Mo) — vérifiez dans le bac à sable');
    }
    if (seeders == 0) {
      warnings.add('Aucun seeder actif');
    }
    if (warnings.isNotEmpty) return (SafetyStatus.warning, warnings);
    return (SafetyStatus.unverified, const []);
  }

  static int qualityRank(String quality) {
    final q = quality.toLowerCase();
    if (q.contains('2160p') || q.contains('4k')) return 400;
    if (q.contains('1080p')) return 300;
    if (q.contains('720p')) return 200;
    if (q.contains('cam') || q.contains('ts')) return 20;
    return 100;
  }
}
