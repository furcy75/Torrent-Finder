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
  static final RegExp _langDe = RegExp(
    r'\b(german|deutsch|ger|deu|dl[\s._-]?ger)\b',
    caseSensitive: false,
  );
  static final RegExp _langNl = RegExp(
    r'\b(dutch|nederlands|nl[\s._-]?subs?|nld|vlaams)\b',
    caseSensitive: false,
  );
  static final RegExp _langIt = RegExp(
    r'\b(italian|italiano|ita|sub[\s._-]?ita)\b',
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
    if (_langDe.hasMatch(title)) found.add('DE');
    if (_langNl.hasMatch(title)) found.add('NL');
    if (_langIt.hasMatch(title)) found.add('IT');
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

  static bool matchesAnyLanguage(List<String> detected, Set<LanguageFilter> requested) {
    if (requested.isEmpty ||
        requested.contains(LanguageFilter.all) ||
        requested.length >= LanguageFilter.selectableFlags.length) {
      return true;
    }
    return requested.any((lang) => matchesLanguage(detected, lang));
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

  static const Map<String, int> _monthMap = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  /// Parses publication dates across all indexer formats into UTC [DateTime]:
  /// ISO 8601, Unix timestamps (s/ms), RFC 2822 RSS `pubDate`, `Mon DD, YYYY`,
  /// `MM/DD/YY` (SubsPlease), relative ages (`2d 4h`, `3 weeks`), or bare year.
  static DateTime? parsePublishedDate(String? raw, {DateTime? now}) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    // 1. Bare 4-digit year (e.g. Internet Archive fallback)
    if (RegExp(r'^\d{4}$').hasMatch(s)) {
      final y = int.tryParse(s);
      if (y != null && y >= 1900 && y <= 2100) return DateTime.utc(y, 1, 1);
      return null;
    }

    // 2. Unix timestamp (9–10 digits = seconds, 12–13 digits = milliseconds)
    if (RegExp(r'^\d{9,13}$').hasMatch(s)) {
      final n = int.tryParse(s);
      if (n != null && n > 0) {
        final ms = s.length >= 12 ? n : n * 1000;
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      }
    }

    // 3. Standard ISO 8601 / SQL datetime ("2024-11-14T18:00:00Z", "2024-11-14 18:00:00")
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.toUtc();

    // 4. RFC 2822 / RSS pubDate ("Thu, 14 Nov 2024 18:00:00 -0000" or "14 Nov 2024")
    final rfc = RegExp(
      r'(?:\w{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?',
    ).firstMatch(s);
    if (rfc != null) {
      final day = int.tryParse(rfc.group(1)!);
      final month = _monthMap[rfc.group(2)!.toLowerCase()];
      final year = int.tryParse(rfc.group(3)!);
      final hour = int.tryParse(rfc.group(4) ?? '0') ?? 0;
      final minute = int.tryParse(rfc.group(5) ?? '0') ?? 0;
      final second = int.tryParse(rfc.group(6) ?? '0') ?? 0;
      if (day != null && month != null && year != null) {
        return DateTime.utc(year, month, day, hour, minute, second);
      }
    }

    // 5. English month-first format ("Nov 12, 2024")
    final mdyText = RegExp(r'([A-Za-z]{3})\s+(\d{1,2}),?\s+(\d{4})').firstMatch(s);
    if (mdyText != null) {
      final month = _monthMap[mdyText.group(1)!.toLowerCase()];
      final day = int.tryParse(mdyText.group(2)!);
      final year = int.tryParse(mdyText.group(3)!);
      if (day != null && month != null && year != null) {
        return DateTime.utc(year, month, day);
      }
    }

    // 6. Slash date ("MM/DD/YY" or "MM/DD/YYYY", e.g. SubsPlease)
    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(s);
    if (slash != null) {
      final month = int.tryParse(slash.group(1)!);
      final day = int.tryParse(slash.group(2)!);
      var year = int.tryParse(slash.group(3)!);
      if (year != null && year < 100) year += 2000;
      if (day != null && month != null && year != null && month >= 1 && month <= 12) {
        return DateTime.utc(year, month, day);
      }
    }

    // 7. Relative ages (e.g. EZTV "2d 4h", "3 weeks", "5 hours", "1 year")
    final relMatches = RegExp(
      r'(\d+)\s*(y(?:ears?|rs?)?|mo(?:nths?)?|w(?:eeks?|ks?)?|d(?:ays?)?|h(?:ours?|rs?)?|m(?:in(?:ute)?s?)?)',
      caseSensitive: false,
    ).allMatches(s);
    if (relMatches.isNotEmpty) {
      var totalMinutes = 0;
      for (final m in relMatches) {
        final v = int.tryParse(m.group(1)!) ?? 0;
        final u = m.group(2)!.toLowerCase();
        if (u.startsWith('y')) {
          totalMinutes += v * 365 * 24 * 60;
        } else if (u.startsWith('mo')) {
          totalMinutes += v * 30 * 24 * 60;
        } else if (u.startsWith('w')) {
          totalMinutes += v * 7 * 24 * 60;
        } else if (u.startsWith('d')) {
          totalMinutes += v * 24 * 60;
        } else if (u.startsWith('h')) {
          totalMinutes += v * 60;
        } else if (u.startsWith('m')) {
          totalMinutes += v;
        }
      }
      if (totalMinutes > 0) {
        final ref = (now ?? DateTime.now().toUtc()).toUtc();
        return ref.subtract(Duration(minutes: totalMinutes));
      }
    }

    return null;
  }

  /// Formats a raw publication date string into a compact `YYYY-MM-DD` label.
  static String? formatPublishedDate(String? raw, {DateTime? now}) {
    final dt = parsePublishedDate(raw, now: now);
    if (dt == null) return null;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
