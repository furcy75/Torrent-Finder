import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/models/seedr_models.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/seedr_service.dart';

void main() {
  test('SeedrService.buildResourceUri puts access_token and func in query params (prevents HTTP 404)',
      () {
    final uri = SeedrService.buildResourceUri(
      accessToken: 'tok_abc',
      func: 'add_torrent',
    );
    expect(uri.host, equals('www.seedr.cc'));
    expect(uri.path, equals('/oauth_test/resource.php'));
    expect(uri.queryParameters['access_token'], equals('tok_abc'));
    expect(uri.queryParameters['func'], equals('add_torrent'));
  });

  test('Multiple Seedr accounts persist, switch, rename, and disconnect cleanly', () async {
    final tmpDir = await Directory.systemTemp.createTemp('safetorrent_seedr_multi_');
    addTearDown(() => tmpDir.delete(recursive: true));

    final storage = LocalStorageService(overrideDirectory: tmpDir);
    await storage.load();
    final service = SeedrService(storage: storage);

    expect(service.isConnected, isFalse);

    await storage.addOrUpdateSeedrAccount(
      const SeedrSession(
        id: 'acc_1',
        label: 'Principal',
        accessToken: 'tok_1',
        deviceCode: 'dev_1',
        authMode: 'device',
        username: 'user_1',
        lastSpaceUsed: 1500000000,
        lastSpaceMax: 4500000000,
      ),
    );
    await storage.addOrUpdateSeedrAccount(
      const SeedrSession(
        id: 'acc_2',
        label: 'Compte 2',
        accessToken: 'tok_2',
        refreshToken: 'ref_2',
        authMode: 'password',
        email: 'user2@example.com',
        lastSpaceUsed: 3800000000,
        lastSpaceMax: 4000000000,
      ),
    );

    expect(service.isConnected, isTrue);
    expect(service.accounts.length, equals(2));
    expect(storage.activeSeedrAccount?.id, equals('acc_2'));

    await storage.renameSeedrAccount('acc_2', 'Secondaire');
    await storage.setActiveSeedrAccount('acc_1');

    final reloaded = LocalStorageService(overrideDirectory: tmpDir);
    await reloaded.load();
    expect(reloaded.seedrAccounts.length, equals(2));
    expect(reloaded.activeSeedrAccount?.id, equals('acc_1'));
    expect(reloaded.activeSeedrAccount?.deviceCode, equals('dev_1'));
    expect(reloaded.seedrAccountById('acc_2')?.label, equals('Secondaire'));

    await SeedrService(storage: reloaded).disconnectAccount('acc_1');
    expect(reloaded.seedrAccounts.length, equals(1));
    expect(reloaded.activeSeedrAccount?.id, equals('acc_2'));
  });

  test('Legacy single seedrSession migrates automatically into seedrAccounts', () async {
    final tmpDir = await Directory.systemTemp.createTemp('safetorrent_seedr_legacy_');
    addTearDown(() => tmpDir.delete(recursive: true));

    final file = File('${tmpDir.path}${Platform.pathSeparator}safetorrent_data.json');
    await file.writeAsString(
      jsonEncode({
        'seedrSession': {
          'accessToken': 'legacy_tok',
          'authMode': 'device',
          'username': 'legacy_user',
        },
      }),
    );

    final storage = LocalStorageService(overrideDirectory: tmpDir);
    await storage.load();
    expect(storage.seedrAccounts.length, equals(1));
    expect(storage.activeSeedrAccount?.accessToken, equals('legacy_tok'));
    expect(storage.activeSeedrAccount?.displayName, equals('legacy_user'));
  });

  test('SeedrAccountQuota checks free space fit and tracks active downloads', () {
    const acc = SeedrSession(
      id: 'acc_1',
      label: 'Principal',
      accessToken: 'tok',
      authMode: 'device',
    );
    const idleQuota = SeedrAccountQuota(
      account: acc,
      spaceUsed: 1500000000, // 1.5 GB used
      spaceMax: 4000000000, // 4.0 GB max -> 2.5 GB free
      activeDownloadsCount: 0,
    );
    const busyQuota = SeedrAccountQuota(
      account: acc,
      spaceUsed: 1500000000,
      spaceMax: 4000000000,
      activeDownloadsCount: 2,
    );

    expect(idleQuota.spaceFree, equals(2500000000));
    expect(idleQuota.canFit(2000000000), isTrue);
    expect(idleQuota.canFit(3000000000), isFalse);
    expect(idleQuota.canFit(0), isNull);
    expect(idleQuota.hasActiveDownloads, isFalse);
    expect(busyQuota.hasActiveDownloads, isTrue);
    expect(busyQuota.activeDownloadsCount, equals(2));
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
    expect(contents.spaceFree, equals(3000000000));
    expect(contents.usedRatio, closeTo(0.333, 0.01));
    expect(contents.torrents.length, equals(1));
    expect(contents.torrents.first.progress, equals(65.5));
    expect(contents.folders.first.name, equals('Inception (2010)'));
    expect(contents.files.first.folderFileId, equals('777'));
    expect(contents.files.first.playVideo, isTrue);
  });
}
