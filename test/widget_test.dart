import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/main.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/ui/widgets/country_flag.dart';

void main() {
  testWidgets('SafeTorrent launches with title-only search, no history tab, and reset button',
      (tester) async {
    final tmpDir = Directory.systemTemp.createTempSync('safetorrent_widget_');
    addTearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    final storage = LocalStorageService(overrideDirectory: tmpDir);
    await tester.runAsync(() => storage.load());

    await tester.pumpWidget(SafeTorrentApp(storage: storage));
    await tester.pumpAndSettle();

    expect(find.text('SafeTorrent'), findsOneWidget);
    expect(find.text('Identifier le film (AlloCiné / Bases)'), findsOneWidget);
    expect(find.text('Rechercher'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);

    // History, year field, and step-1 language selectors are removed
    expect(find.text('Historique'), findsNothing);
    expect(find.text('Année'), findsNothing);

    // Typing reveals "Nouvelle recherche" and tapping resets to zero
    await tester.enterText(find.byType(TextField).first, 'Inception');
    await tester.pumpAndSettle();
    expect(find.text('Nouvelle recherche'), findsOneWidget);

    await tester.tap(find.text('Nouvelle recherche'));
    await tester.pumpAndSettle();
    expect(find.text('Inception'), findsNothing);
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
