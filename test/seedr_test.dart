import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/models/seedr_models.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/seedr_service.dart';

void main() {
  test('SeedrSession persists locally and wipes cleanly on logout', () async {
    final tmpDir = await Directory.systemTemp.createTemp('safetorrent_seedr_');
    addTearDown(() => tmpDir.delete(recursive: true));

    final storage = LocalStorageService(overrideDirectory: tmpDir);
    await storage.load();
    final service = SeedrService(storage: storage);

    expect(service.isConnected, isFalse);

    await storage.setSeedrSession(
      const SeedrSession(
        accessToken: 'tok_device_123',
        authMode: 'device',
        username: 'demo_user',
        packageName: 'Free',
      ),
    );
    expect(service.isConnected, isTrue);

    final reloaded = LocalStorageService(overrideDirectory: tmpDir);
    await reloaded.load();
    expect(reloaded.seedrSession?.accessToken, equals('tok_device_123'));
    expect(reloaded.seedrSession?.authMode, equals('device'));
    expect(reloaded.seedrSession?.username, equals('demo_user'));

    await SeedrService(storage: reloaded).logout();
    expect(reloaded.seedrSession, isNull);
  });

  test('SeedrFolderContents parses quota, transfers, folders, and files accurately', () {
    final contents = SeedrFolderContents.fromJson({
      'folder_id': 0,
      'name': 'Root',
      'parent': -1,
      'space_used': 1500000000,
      'space_max': 4500000000,
      'torrents': [
        {
          'id': 99,
          'name': 'Dune.2024.1080p.FRENCH',
          'size': 2100000000,
          'progress': '65.5',
          'download_rate': 5242880,
          'seeders': 42,
          'leechers': 3,
        }
      ],
      'folders': [
        {'id': 10, 'name': 'Inception (2010)', 'size': 1900000000, 'play_video': true}
      ],
      'files': [
        {
          'folder_file_id': 777,
          'name': 'Inception.2010.1080p.mkv',
          'size': 1899000000,
          'play_video': true,
        }
      ],
    });

    expect(contents.parentId, isNull);
    expect(contents.usedRatio, closeTo(0.333, 0.01));
    expect(contents.torrents.length, equals(1));
    expect(contents.torrents.first.progress, equals(65.5));
    expect(contents.folders.first.name, equals('Inception (2010)'));
    expect(contents.files.first.folderFileId, equals('777'));
    expect(contents.files.first.playVideo, isTrue);
  });
}
