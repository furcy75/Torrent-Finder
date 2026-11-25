import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/l10n/app_l10n.dart';
import 'package:safetorrent/main.dart';
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/ui/widgets/country_flag.dart';

void main() {
  testWidgets(
      'Torrent Seeder supports 6 languages via flag switcher, Donate icon, and Seedr multi-accounts',
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

    // Launches cleanly in English
    expect(find.text('Torrent Seeder'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('TV Series'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Watchlist'), findsOneWidget);
    expect(find.text('Seedr'), findsOneWidget);
    expect(find.text('TorBox'), findsNothing);

    // Switch live to French via the flag switcher next to Settings
    await tester.tap(find.byKey(const Key('language_switcher_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Séries TV'), findsOneWidget);
    expect(find.text('Rechercher'), findsOneWidget);
    expect(storage.settings.appLanguage, equals('fr'));

    // Switch live to German and verify translation
    await tester.tap(find.byKey(const Key('language_switcher_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();

    expect(find.text('Filme'), findsOneWidget);
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

    // Switch to Seedr tab and verify both auth flows
    await tester.tap(find.text('Seedr'));
    await tester.pumpAndSettle();
    expect(find.text('Gerätecode (Empfohlen)'), findsOneWidget);
    expect(find.text('E-Mail & Passwort'), findsOneWidget);

    // Return to Search tab & test reset button
    await tester.tap(find.text('Suchen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Severance');
    await tester.pumpAndSettle();
    expect(find.text('Neue Suche'), findsOneWidget);

    await tester.tap(find.text('Neue Suche'));
    await tester.pumpAndSettle();
    expect(find.text('Severance'), findsNothing);
  });

  test('AppL10n provides complete translations for all 6 languages (en, fr, es, de, nl, it)', () {
    for (final lang in AppL10n.supported) {
      final l10n = AppL10n(lang.code);
      expect(l10n.t('tab_search'), isNot(equals('tab_search')));
      expect(l10n.t('dl_done_title'), isNot(equals('dl_done_title')));
      expect(l10n.t('picker_downloading_one'), isNot(equals('picker_downloading_one')));
      expect(l10n.t('donate_cta'), isNot(equals('donate_cta')));
    }
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
