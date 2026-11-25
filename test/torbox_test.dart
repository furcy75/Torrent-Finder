import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safetorrent/models/torbox_models.dart';
import 'package:safetorrent/services/local_storage.dart';

void main() {
  test('TorboxProfile distinguishes Premium vs Free plans and official cooldown countdown', () {
    final now = DateTime.utc(2026, 11, 25, 12, 0, 0);

    final freeInCooldown = TorboxProfile(
      id: 'p1',
      label: 'Ma fille',
      apiKey: 'key_free',
      plan: 0,
      isSubscribed: false,
      cooldownUntil: now.add(const Duration(hours: 5, minutes: 30)),
    );
    expect(freeInCooldown.isPremium, isFalse);
    expect(freeInCooldown.planLabel, equals('Gratuit'));
    expect(freeInCooldown.isInCooldown(now), isTrue);
    expect(TorboxProfile.formatDuration(freeInCooldown.remainingCooldown(now)), equals('5h 30m'));

    final premium = TorboxProfile(
      id: 'p2',
      label: 'Mon compte',
      apiKey: 'key_pro',
      plan: 2,
      isSubscribed: true,
      cooldownUntil: now.add(const Duration(hours: 10)),
    );
    expect(premium.isPremium, isTrue);
    expect(premium.planLabel, equals('Premium Pro'));
    // Premium accounts have no cooldown limit
    expect(premium.isInCooldown(now), isFalse);
    expect(premium.remainingCooldown(now), equals(Duration.zero));
  });

  test('LocalStorage persists multiple TorBox profiles and active selection', () async {
    final tmpDir = await Directory.systemTemp.createTemp('safetorrent_torbox_');
    addTearDown(() => tmpDir.delete(recursive: true));

    final storage = LocalStorageService(overrideDirectory: tmpDir);
    await storage.load();

    await storage.addOrUpdateTorboxProfile(
      const TorboxProfile(id: 'a', label: 'Moi', apiKey: 'api_a', plan: 1, isSubscribed: true),
      makeActive: true,
    );
    await storage.addOrUpdateTorboxProfile(
      const TorboxProfile(id: 'b', label: 'Ma sœur', apiKey: 'api_b', plan: 0),
      makeActive: false,
    );

    expect(storage.torboxProfiles.length, equals(2));
    expect(storage.activeTorboxProfile?.id, equals('a'));

    await storage.setActiveTorboxProfile('b');
    final reloaded = LocalStorageService(overrideDirectory: tmpDir);
    await reloaded.load();
    expect(reloaded.torboxProfiles.length, equals(2));
    expect(reloaded.activeTorboxProfile?.label, equals('Ma sœur'));

    await reloaded.deleteTorboxProfile('b');
    expect(reloaded.torboxProfiles.length, equals(1));
    expect(reloaded.activeTorboxProfile?.label, equals('Moi'));
  });

  test('TorboxTorrentItem parses mylist payload accurately', () {
    final item = TorboxTorrentItem.fromJson({
      'id': 42,
      'name': 'Inception.2010.1080p.MULTI',
      'hash': 'a' * 40,
      'size': 2200000000,
      'progress': 1.0,
      'download_speed': 0,
      'seeds': 55,
      'download_state': 'cached',
      'active': true,
      'download_finished': true,
      'cached': true,
      'files': [
        {
          'id': 1,
          'name': 'Inception.2010/Inception.mkv',
          'short_name': 'Inception.mkv',
          'size': 2190000000,
        }
      ],
    });

    expect(item.id, equals(42));
    expect(item.progressPercent, equals(100.0));
    expect(item.cached, isTrue);
    expect(item.files.length, equals(1));
    expect(item.files.first.isVideo, isTrue);
  });
}
