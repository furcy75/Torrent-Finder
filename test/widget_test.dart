import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/main.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/ui/widgets/country_flag.dart';

void main() {
  testWidgets(
      'Torrent Seeder launches with Films/Séries toggle, Donate icon, Seedr multi-accounts, and no TorBox/history',
      (tester) async {
    final tmpDir = Directory.systemTemp.createTempSync('torrent_seeder_widget_');
    addTearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    final storage = LocalStorageService(overrideDirectory: tmpDir);
    await tester.runAsync(() => storage.load());

    await tester.pumpWidget(TorrentSeederApp(storage: storage));
    await tester.pumpAndSettle();

    expect(find.text('Torrent Seeder'), findsOneWidget);
    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Séries TV'), findsOneWidget);
    expect(find.text('Identifier le film (AlloCiné / Bases)'), findsOneWidget);
    expect(find.text('Rechercher'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
    expect(find.text('Seedr'), findsOneWidget);

    // History, year field, and TorBox are removed
    expect(find.text('Historique'), findsNothing);
    expect(find.text('Année'), findsNothing);
    expect(find.text('TorBox'), findsNothing);

    // Donate icon opens GitHub Sponsors dialog
    await tester.tap(find.byIcon(Icons.volunteer_activism_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Soutenir Torrent Seeder'), findsOneWidget);
    expect(find.text('Faire un don (GitHub Sponsors)'), findsOneWidget);
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();

    // Switch to Seedr tab and verify general account label + both auth flows
    await tester.tap(find.text('Seedr'));
    await tester.pumpAndSettle();
    expect(find.text('Nom du compte (ex : Principal, Compte 2...)'), findsOneWidget);
    expect(find.text('Code Appareil (Recommandé)'), findsOneWidget);
    expect(find.text('Email & Mot de passe'), findsOneWidget);

    // Return to Search tab
    await tester.tap(find.text('Rechercher'));
    await tester.pumpAndSettle();

    // Switch to TV Series mode
    await tester.tap(find.text('Séries TV'));
    await tester.pumpAndSettle();
    expect(find.text('Identifier la série (AlloCiné / TVMaze)'), findsOneWidget);

    // Typing reveals "Nouvelle recherche" and tapping resets to zero
    await tester.enterText(find.byType(TextField).first, 'Severance');
    await tester.pumpAndSettle();
    expect(find.text('Nouvelle recherche'), findsOneWidget);

    await tester.tap(find.text('Nouvelle recherche'));
    await tester.pumpAndSettle();
    expect(find.text('Severance'), findsNothing);
  });

  testWidgets('CountryFlag renders vector flags for FR, EN, ES, MULTI without errors',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              CountryFlag(code: 'FR'),
              CountryFlag(code: 'EN'),
              CountryFlag(code: 'ES'),
              CountryFlag(code: 'MULTI'),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(CountryFlag), findsNWidgets(4));
  });
}
