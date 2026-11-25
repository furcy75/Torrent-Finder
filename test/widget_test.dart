import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/main.dart';
import 'package:safetorrent/services/local_storage.dart';

void main() {
  testWidgets('SafeTorrent launches with movie search, AlloCiné button, and language flags',
      (tester) async {
    final tmpDir = await Directory.systemTemp.createTemp('safetorrent_widget_');
    addTearDown(() => tmpDir.delete(recursive: true));

    final storage = LocalStorageService(overrideDirectory: tmpDir);
    await tester.pumpWidget(SafeTorrentApp(storage: storage));
    await tester.pumpAndSettle();

    expect(find.text('SafeTorrent'), findsOneWidget);
    expect(find.text('AlloCiné (Titre EN)'), findsOneWidget);
    expect(find.text('🇫🇷 Français'), findsOneWidget);
    expect(find.text('🇬🇧 English'), findsOneWidget);
    expect(find.text('🇪🇸 Español'), findsOneWidget);
  });
}
