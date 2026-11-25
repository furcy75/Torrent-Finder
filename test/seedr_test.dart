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

  test('Multiple family Seedr accounts persist, switch, rename, and disconnect cleanly', () async {
    final tmpDir = await Directory.systemTemp.createTemp('safetorrent_seedr_multi_');
    addTearDown(() => tmpDir.delete(recursive: true));

    final storage = LocalStorageService(overrideDirectory: tmpDir);
    await storage.load();
    final service = SeedrService(storage: storage);

    expect(service.isConnected, isFalse);

    await storage.addOrUpdateSeedrAccount(
      const SeedrSession(
        id: 'acc_moi',
        label: 'Moi',
        accessToken: 'tok_moi',
        deviceCode: 'dev_moi',
        authMode: 'device',
        username: 'user_moi',
        lastSpaceUsed: 1500000000,
        lastSpaceMax: 4500000000,
      ),
    );
    await storage.addOrUpdateSeedrAccount(
      const SeedrSession(
        id: 'acc_soeur',
        label: 'Sœur',
        accessToken: 'tok_soeur',
        refreshToken: 'ref_soeur',
        authMode: 'password',
        email: 'soeur@example.com',
        lastSpaceUsed: 3800000000,
        lastSpaceMax: 4000000000,
      ),
    );

    expect(service.isConnected, isTrue);
    expect(service.accounts.length, equals(2));
    expect(storage.activeSeedrAccount?.id, equals('acc_soeur'));

    await storage.renameSeedrAccount('acc_soeur', 'Ma Sœur');
    await storage.setActiveSeedrAccount('acc_moi');

    final reloaded = LocalStorageService(overrideDirectory: tmpDir);
    await reloaded.load();
    expect(reloaded.seedrAccounts.length, equals(2));
    expect(reloaded.activeSeedrAccount?.id, equals('acc_moi'));
    expect(reloaded.activeSeedrAccount?.deviceCode, equals('dev_moi'));
    expect(reloaded.seedrAccountById('acc_soeur')?.label, equals('Ma Sœur'));

    await SeedrService(storage: reloaded).disconnectAccount('acc_moi');
    expect(reloaded.seedrAccounts.length, equals(1));
    expect(reloaded.activeSeedrAccount?.id, equals('acc_soeur'));
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

  test('SeedrAccountQuota accurately checks whether free space fits a torrent size', () {
    const acc = SeedrSession(
      id: 'acc_1',
      label: 'Moi',
      accessToken: 'tok',
      authMode: 'device',
    );
    const quota = SeedrAccountQuota(
      account: acc,
      spaceUsed: 1500000000, // 1.5 GB used
      spaceMax: 4000000000, // 4.0 GB max -> 2.5 GB free
    );

    expect(quota.spaceFree, equals(2500000000));
    expect(quota.canFit(2000000000), isTrue); // 2.0 GB fits
    expect(quota.canFit(3000000000), isFalse); // 3.0 GB does not fit
    expect(quota.canFit(0), isNull); // Unknown torrent size
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
