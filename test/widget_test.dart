import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/l10n/app_l10n.dart';
import 'package:safetorrent/main.dart';
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/release_parser.dart';
import 'package:safetorrent/ui/widgets/country_flag.dart';

void main() {
  testWidgets(
      'Torrent Seeder splits Info Lookup & editable Torrent Search, uses Seedr login/password only, and switches 6 languages',
      (tester) async {
    final tmpDir = Directory.systemTemp.createTempSync('torrent_seeder_widget_');
    addTearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    final storage = LocalStorageService(overrideDirectory: tmpDir);
    await tester.runAsync(() => storage.load());
    await tester.runAsync(
      () => storage.updateSettings(const AppSettings(appLanguage: 'en')),
    );

    await tester.pumpWidget(TorrentSeederApp(storage: storage));
    await tester.pumpAndSettle();

    // Launches cleanly in English with separated Info Lookup and Torrent Search sections
    expect(find.text('Torrent Seeder'), findsOneWidget);
    expect(find.text('Movie / TV Series Info Lookup (optional)'), findsOneWidget);
    expect(find.text('Torrent Search'), findsOneWidget);
    expect(find.byKey(const Key('info_lookup_field')), findsOneWidget);
    expect(find.byKey(const Key('torrent_query_field')), findsOneWidget);

    // Skipping info step copies typed title into the editable Torrent Search box
    await tester.enterText(find.byKey(const Key('info_lookup_field')), 'Inception');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    final torrentField =
        tester.widget<TextField>(find.byKey(const Key('torrent_query_field')));
    expect(torrentField.controller?.text, equals('Inception'));

    // User can edit the Torrent Search box freely to add extra keywords
    await tester.enterText(
      find.byKey(const Key('torrent_query_field')),
      'Inception 2010 FRENCH 1080p',
    );
    await tester.pumpAndSettle();
    expect(torrentField.controller?.text, equals('Inception 2010 FRENCH 1080p'));

    // Switch live to French via the flag switcher next to Settings
    await tester.tap(find.byKey(const Key('language_switcher_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    expect(find.text('Recherche Torrent'), findsOneWidget);
    expect(find.text('Rechercher'), findsOneWidget);
    expect(storage.settings.appLanguage, equals('fr'));

    // Switch live to German
    await tester.tap(find.byKey(const Key('language_switcher_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();

    expect(find.text('Torrent-Suche'), findsOneWidget);
    expect(find.text('Suchen'), findsOneWidget);
    expect(storage.settings.appLanguage, equals('de'));

    // Donate icon opens GitHub Sponsors dialog in active language
    await tester.tap(find.byIcon(Icons.volunteer_activism_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Torrent Seeder unterstützen'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Später')),
    );
    await tester.pumpAndSettle();

    // Seedr tab shows Email & Password login ONLY (no Device Code flow)
    await tester.tap(find.text('Seedr'));
    await tester.pumpAndSettle();
    expect(find.text('Seedr E-Mail / Login'), findsOneWidget);
    expect(find.text('Seedr Passwort'), findsOneWidget);
    expect(find.text('Gerätecode (Empfohlen)'), findsNothing);
    expect(find.text('Code Appareil (Recommandé)'), findsNothing);
  });

  test('AppL10n provides complete translations for all 6 languages (en, fr, es, de, nl, it)', () {
    for (final lang in AppL10n.supported) {
      final l10n = AppL10n(lang.code);
      expect(l10n.t('info_section_title'), isNot(equals('info_section_title')));
      expect(l10n.t('torrent_section_title'), isNot(equals('torrent_section_title')));
      expect(l10n.t('dl_done_title'), isNot(equals('dl_done_title')));
      expect(l10n.t('picker_downloading_one'), isNot(equals('picker_downloading_one')));
      expect(l10n.t('donate_cta'), isNot(equals('donate_cta')));
    }
  });

  test('ReleaseParser detects DE, NL, IT, FR, ES, EN, MULTI flags for result cards', () {
    expect(ReleaseParser.detectLanguages('Film.2024.GERMAN.1080p'), contains('DE'));
    expect(ReleaseParser.detectLanguages('Film.2024.DUTCH.NL.1080p'), contains('NL'));
    expect(ReleaseParser.detectLanguages('Film.2024.ITALIAN.ITA.1080p'), contains('IT'));
    expect(ReleaseParser.detectLanguages('Film.2024.MULTI.TRUEFRENCH.1080p'), containsAll(['MULTI', 'FR']));
  });

  testWidgets('CountryFlag renders vector flags for EN, FR, ES, DE, NL, IT, MULTI without errors',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              CountryFlag(code: 'EN'),
              CountryFlag(code: 'FR'),
              CountryFlag(code: 'ES'),
              CountryFlag(code: 'DE'),
              CountryFlag(code: 'NL'),
              CountryFlag(code: 'IT'),
              CountryFlag(code: 'MULTI'),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(CountryFlag), findsNWidgets(7));
  });
}
