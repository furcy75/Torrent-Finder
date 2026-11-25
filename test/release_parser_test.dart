import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/services/release_parser.dart';

void main() {
  test('Parses 4K and 1080p quality badges accurately', () {
    final (q1, tags1) =
        ReleaseParser.parseQuality('Dune.Part.Two.2024.2160p.BluRay.HDR.x265.TRUEFRENCH');
    expect(q1, equals('4K 2160p BluRay'));
    expect(tags1, containsAll(['HDR', 'x265']));

    final (q2, _) = ReleaseParser.parseQuality('The.Shawshank.Redemption.1994.1080p.WEB-DL.x264');
    expect(q2, equals('1080p WEB-DL'));
  });

  test('Detects and matches FR, EN, ES, and MULTI flags', () {
    final fr = ReleaseParser.detectLanguages('Les.Evades.1994.TRUEFRENCH.1080p.BluRay');
    expect(fr, contains('FR'));
    expect(ReleaseParser.matchesLanguage(fr, LanguageFilter.fr), isTrue);
    expect(ReleaseParser.matchesLanguage(fr, LanguageFilter.es), isFalse);

    final es = ReleaseParser.detectLanguages('Origen.2010.Castellano.1080p');
    expect(es, contains('ES'));
    expect(ReleaseParser.matchesLanguage(es, LanguageFilter.es), isTrue);

    final multi = ReleaseParser.detectLanguages('Inception.2010.MULTI.1080p.BluRay');
    expect(multi, contains('MULTI'));
    expect(ReleaseParser.matchesLanguage(multi, LanguageFilter.fr), isTrue);
    expect(ReleaseParser.matchesLanguage(multi, LanguageFilter.en), isTrue);
    expect(ReleaseParser.matchesLanguage(multi, LanguageFilter.es), isTrue);
  });

  test('Pre-scan blocks executable filenames and flags zero seeders', () {
    final (stBlocked, reasons) = ReleaseParser.preScanTitle('Avatar.3.2026.mkv.exe', 500000, 12);
    expect(stBlocked, equals(SafetyStatus.blocked));
    expect(reasons, isNotEmpty);

    final (stWarn, warnings) =
        ReleaseParser.preScanTitle('Valid.Movie.2024.1080p.FRENCH', 2000000000, 0);
    expect(stWarn, equals(SafetyStatus.warning));
    expect(warnings, isNotEmpty);
  });
}
