import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/main.dart';
import 'package:safetorrent/services/local_storage.dart';

void main() {
  testWidgets('SafeTorrent launches with guided 3-step search, AlloCiné lookup, and multi-flags',
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
    expect(find.text('1. Film'), findsOneWidget);
    expect(find.text('2. Correspondance'), findsOneWidget);
    expect(find.text('3. Torrents'), findsOneWidget);
    expect(find.text('Identifier le film (AlloCiné / Bases)'), findsOneWidget);
    expect(find.text('Année'), findsOneWidget);
    expect(find.text('🇫🇷 Français'), findsOneWidget);
    expect(find.text('🇬🇧 English'), findsOneWidget);
    expect(find.text('🇪🇸 Español'), findsOneWidget);

    // Typing a film title reveals the "Nouvelle recherche" reset button
    await tester.enterText(find.byType(TextField).first, 'Inception');
    await tester.pumpAndSettle();
    expect(find.text('Nouvelle recherche'), findsOneWidget);

    // Tapping reset clears the field back to zero
    await tester.tap(find.text('Nouvelle recherche'));
    await tester.pumpAndSettle();
    expect(find.text('Inception'), findsNothing);
  });
}
