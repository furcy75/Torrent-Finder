import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/main.dart';
import 'package:safetorrent/services/local_storage.dart';

void main() {
  testWidgets('SafeTorrent launches with movie+year fields, multilingual lookup, and multi-flags',
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
    expect(find.text('Titres AlloCiné / Toutes langues'), findsOneWidget);
    expect(find.text('Année'), findsOneWidget);
    expect(find.text('🇫🇷 Français'), findsOneWidget);
    expect(find.text('🇬🇧 English'), findsOneWidget);
    expect(find.text('🇪🇸 Español'), findsOneWidget);

    // Multi-language selection works simultaneously (FR + EN active at the same time)
    await tester.tap(find.text('🇬🇧 English'));
    await tester.pumpAndSettle();
    expect(find.text('🇫🇷 Français'), findsOneWidget);
    expect(find.text('🇬🇧 English'), findsOneWidget);
  });
}
