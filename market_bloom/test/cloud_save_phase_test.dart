import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/game_controller.dart';
import 'package:pomarket/services/app_settings.dart';
import 'package:pomarket/services/cloud_save/cloud_save_backend.dart';
import 'package:pomarket/services/cloud_save/cloud_save_models.dart';
import 'package:pomarket/services/cloud_save/cloud_save_status.dart';
import 'package:pomarket/services/cloud_save/cloud_synchronized_game_storage.dart';
import 'package:pomarket/services/cloud_save/player_identity.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';
import 'package:pomarket/ui/widgets/cloud_save_status_layer.dart';

void main() {
  test('cloud envelope serialization is versioned and stable', () {
    final payload = _save(sales: 12, savedAt: DateTime.utc(2026, 8, 14));
    final envelope = CloudSaveEnvelope.create(
      accountId: 'player-one',
      deviceId: 'device-one',
      revision: 3,
      modifiedAt: DateTime.utc(2026, 8, 14),
      payload: payload,
    );
    final restored = CloudSaveEnvelope.fromJson(envelope.toJson());

    expect(restored.schemaVersion, cloudEnvelopeSchemaVersion);
    expect(restored.revision, 3);
    expect(restored.payload, payload);
    expect(restored.contentHash, stableSaveHash(payload));
    expect(stableSaveHash(Map<String, dynamic>.from(payload)), restored.contentHash);
  });

  test('unsupported or corrupted cloud envelopes are rejected defensively', () {
    final payload = _save(sales: 12);
    final json = CloudSaveEnvelope.create(
      accountId: 'player-one',
      deviceId: 'device-one',
      revision: 3,
      modifiedAt: DateTime.utc(2026, 8, 14),
      payload: payload,
    ).toJson();

    expect(
      () => CloudSaveEnvelope.fromJson(<String, dynamic>{
        ...json,
        'schemaVersion': cloudEnvelopeSchemaVersion + 1,
      }),
      throwsFormatException,
    );
    expect(
      () => CloudSaveEnvelope.fromJson(<String, dynamic>{
        ...json,
        'contentHash': 'tampered',
      }),
      throwsFormatException,
    );
  });

  test('older local-only saves load unchanged while cloud is unavailable', () async {
    final legacy = <String, dynamic>{
      'version': 3,
      'coins': 77,
      'totalSales': 4,
    };
    final local = MemoryGameStorage()..data = Map<String, dynamic>.from(legacy);
    final storage = _storage(
      local: local,
      backend: const DisabledCloudSaveBackend(),
    );

    expect(await storage.load(), legacy);
    expect(storage.status.state, CloudSaveState.localOnly);
    expect(local.data, legacy);
  });

  test('local save uploads to an empty cloud', () async {
    final backend = _MemoryCloudBackend();
    final local = MemoryGameStorage()..data = _save(sales: 8);
    final storage = _storage(local: local, backend: backend);

    final result = await storage.syncNow(localSnapshot: local.data);
    final remote = await backend.download(await storage.identity);

    expect(result.state, CloudSaveState.synced);
    expect(remote, isNotNull);
    expect(remote!.payload['totalSales'], 8);
    expect(remote.revision, 1);
    expect(backend.uploadCalls, 1);
  });

  test('cloud save downloads to an empty local store', () async {
    final backend = _MemoryCloudBackend();
    final identityStore = MemoryPlayerIdentityStore();
    backend.remote = CloudSaveEnvelope.create(
      accountId: identityStore.identity.accountId,
      deviceId: 'other-device',
      revision: 4,
      modifiedAt: DateTime.utc(2026, 8, 14, 12),
      payload: _save(sales: 30),
    );
    final local = MemoryGameStorage();
    final storage = _storage(
      local: local,
      backend: backend,
      identityStore: identityStore,
    );

    final result = await storage.syncNow();

    expect(result.remoteAppliedLocally, isTrue);
    expect(local.data!['totalSales'], 30);
    expect(storage.status.state, CloudSaveState.downloaded);
  });

  test('offline failure never prevents local save', () async {
    final backend = _MemoryCloudBackend()..fail = true;
    final local = MemoryGameStorage();
    final storage = _storage(local: local, backend: backend);
    final payload = _save(sales: 5);

    await storage.save(payload);
    final result = await storage.syncNow(localSnapshot: payload);

    expect(local.data, payload);
    expect(result.state, CloudSaveState.error);
    expect(storage.status.canRetry, isTrue);
  });

  test('conflict resolver deterministically selects stronger progression', () {
    const resolver = CloudSaveConflictResolver();
    final local = _save(sales: 40, actions: 100);
    final remote = _save(sales: 12, actions: 500);

    expect(resolver.resolve(local, remote), CloudConflictWinner.local);
    expect(resolver.resolve(remote, local), CloudConflictWinner.remote);
  });

  test('remote conflict winner is recovered locally', () async {
    final backend = _MemoryCloudBackend();
    final identityStore = MemoryPlayerIdentityStore();
    final local = MemoryGameStorage()..data = _save(sales: 2, actions: 5);
    backend.remote = CloudSaveEnvelope.create(
      accountId: identityStore.identity.accountId,
      deviceId: 'other-device',
      revision: 7,
      modifiedAt: DateTime.utc(2026, 8, 14, 14),
      payload: _save(sales: 80, actions: 500),
    );
    final storage = _storage(
      local: local,
      backend: backend,
      identityStore: identityStore,
    );

    final result = await storage.syncNow(localSnapshot: local.data);

    expect(result.state, CloudSaveState.conflictResolved);
    expect(result.remoteAppliedLocally, isTrue);
    expect(local.data!['totalSales'], 80);
  });

  test('same content synchronizes idempotently without duplicate upload', () async {
    final backend = _MemoryCloudBackend();
    final local = MemoryGameStorage()..data = _save(sales: 9);
    final storage = _storage(local: local, backend: backend);

    await storage.syncNow(localSnapshot: local.data);
    await storage.syncNow(localSnapshot: local.data);

    expect(backend.uploadCalls, 1);
    expect(backend.uniqueUploadKeys, 1);
  });

  test('failed synchronization recovers on retry', () async {
    final backend = _MemoryCloudBackend()..fail = true;
    final local = MemoryGameStorage()..data = _save(sales: 15);
    final storage = _storage(local: local, backend: backend);

    expect(
      (await storage.syncNow(localSnapshot: local.data)).state,
      CloudSaveState.error,
    );
    backend.fail = false;
    expect(
      (await storage.syncNow(localSnapshot: local.data)).state,
      CloudSaveState.synced,
    );
    expect(storage.status.canRetry, isFalse);
  });

  test('legacy cloud payload migrates without changing gameplay fields', () async {
    final legacy = <String, dynamic>{
      'version': 4,
      'coins': 91,
      'totalSales': 11,
      'savedAt': '2025-01-01T00:00:00.000Z',
    };
    final migrated = CloudSaveEnvelope.fromJson(
      legacy,
      fallbackAccountId: 'legacy-player',
    );

    expect(migrated.schemaVersion, 0);
    expect(migrated.payload['coins'], 91);
    expect(migrated.payload['totalSales'], 11);
  });

  test('recovery code adopts the same account on another device', () async {
    final first = MemoryPlayerIdentityStore();
    final second = MemoryPlayerIdentityStore(
      identity: const CloudPlayerIdentity(
        accountId: 'player-other-account',
        deviceId: 'device-two',
        syncSecret: 'another-secret-value-123456',
      ),
    );

    final adopted = await second.adoptRecoveryCode(first.identity.recoveryCode);

    expect(adopted.accountId, first.identity.accountId);
    expect(adopted.syncSecret, first.identity.syncSecret);
    expect(adopted.deviceId, 'device-two');
  });

  test('account recovery prefers recovered cloud progress over local data', () async {
    final sourceIdentity = MemoryPlayerIdentityStore();
    final targetIdentity = MemoryPlayerIdentityStore(
      identity: const CloudPlayerIdentity(
        accountId: 'player-other-account',
        deviceId: 'device-two',
        syncSecret: 'another-secret-value-123456',
      ),
    );
    final backend = _MemoryCloudBackend()
      ..remote = CloudSaveEnvelope.create(
        accountId: sourceIdentity.identity.accountId,
        deviceId: 'device-one',
        revision: 5,
        modifiedAt: DateTime.utc(2026, 8, 14, 11),
        payload: _save(sales: 12),
      );
    final local = MemoryGameStorage()..data = _save(sales: 90);
    final storage = _storage(
      local: local,
      backend: backend,
      identityStore: targetIdentity,
    );

    final result = await storage.recoverWithCode(
      sourceIdentity.identity.recoveryCode,
    );

    expect(result.remoteAppliedLocally, isTrue);
    expect(local.data!['totalSales'], 12);
    expect(backend.uploadCalls, 0);
  });

  test('account recovery remains remote-first after an offline retry', () async {
    final sourceIdentity = MemoryPlayerIdentityStore();
    final targetIdentity = MemoryPlayerIdentityStore(
      identity: const CloudPlayerIdentity(
        accountId: 'player-other-account',
        deviceId: 'device-two',
        syncSecret: 'another-secret-value-123456',
      ),
    );
    final backend = _MemoryCloudBackend()
      ..remote = CloudSaveEnvelope.create(
        accountId: sourceIdentity.identity.accountId,
        deviceId: 'device-one',
        revision: 5,
        modifiedAt: DateTime.utc(2026, 8, 14, 11),
        payload: _save(sales: 12),
      )
      ..fail = true;
    final local = MemoryGameStorage()..data = _save(sales: 90);
    final storage = _storage(
      local: local,
      backend: backend,
      identityStore: targetIdentity,
    );

    expect(
      (await storage.recoverWithCode(sourceIdentity.identity.recoveryCode)).state,
      CloudSaveState.error,
    );
    backend.fail = false;
    final result = await storage.syncNow(localSnapshot: local.data);

    expect(result.remoteAppliedLocally, isTrue);
    expect(local.data!['totalSales'], 12);
    expect(backend.uploadCalls, 0);
  });

  test('failed cloud deletion retries without restoring deleted progress', () async {
    final identityStore = MemoryPlayerIdentityStore();
    final backend = _MemoryCloudBackend()
      ..remote = CloudSaveEnvelope.create(
        accountId: identityStore.identity.accountId,
        deviceId: 'device-one',
        revision: 2,
        modifiedAt: DateTime.utc(2026, 8, 14, 11),
        payload: _save(sales: 20),
      )
      ..fail = true;
    final local = MemoryGameStorage()..data = _save(sales: 20);
    final storage = _storage(
      local: local,
      backend: backend,
      identityStore: identityStore,
    );

    await storage.clear();
    expect(local.data, isNull);
    expect(storage.status.state, CloudSaveState.error);

    backend.fail = false;
    final result = await storage.syncNow();

    expect(result.state, CloudSaveState.synced);
    expect(local.data, isNull);
    expect(backend.remote, isNull);
    expect(backend.deleteCalls, 2);
  });

  testWidgets('cloud status UI is responsive RTL and reduced-motion safe', (
    tester,
  ) async {
    const layouts = <({Size size, TextDirection direction})>[
      (size: Size(390, 844), direction: TextDirection.ltr),
      (size: Size(320, 568), direction: TextDirection.rtl),
    ];

    for (final layout in layouts) {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      final storage = _storage(
        local: MemoryGameStorage(),
        backend: _MemoryCloudBackend(),
      );
      storage.status.update(
        CloudSaveState.error,
        message: 'Offline test failure',
      );
      final game = GameController(
        storage: storage,
        monetization: PreviewMonetizationService(),
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Directionality(
              textDirection: layout.direction,
              child: child!,
            ),
          ),
          home: CloudSaveStatusLayer(
            game: game,
            settings: AppSettings(),
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('cloud-save-status-chip')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: '${layout.size}');
      await tester.pumpWidget(const SizedBox.shrink());
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Map<String, dynamic> _save({
  int sales = 0,
  int actions = 0,
  DateTime? savedAt,
}) => <String, dynamic>{
  'version': 7,
  'saveSchemaVersion': 2,
  'savedAt': (savedAt ?? DateTime.utc(2026, 8, 14, 10)).toIso8601String(),
  'coins': 25 + sales,
  'totalSales': sales,
  'totalCoinsEarned': sales * 8,
  'upgradesBought': sales ~/ 5,
  'totalActions': actions,
};

CloudSynchronizedGameStorage _storage({
  required GameStorage local,
  required CloudSaveBackend backend,
  MemoryPlayerIdentityStore? identityStore,
}) => CloudSynchronizedGameStorage(
  local: local,
  backend: backend,
  identityStore: identityStore ?? MemoryPlayerIdentityStore(),
  metadataStore: MemoryCloudSyncMetadataStore(),
  now: () => DateTime.utc(2026, 8, 14, 12),
);

class _MemoryCloudBackend implements CloudSaveBackend {
  CloudSaveEnvelope? remote;
  bool fail = false;
  int uploadCalls = 0;
  int deleteCalls = 0;
  final Set<String> _keys = <String>{};

  int get uniqueUploadKeys => _keys.length;

  @override
  bool get isAvailable => true;

  void _check() {
    if (fail) throw const CloudSaveRequestFailed(503, 'offline');
  }

  @override
  Future<void> delete(CloudPlayerIdentity identity) async {
    deleteCalls++;
    _check();
    remote = null;
  }

  @override
  Future<CloudSaveEnvelope?> download(CloudPlayerIdentity identity) async {
    _check();
    return remote;
  }

  @override
  Future<CloudSaveEnvelope> upload(
    CloudPlayerIdentity identity,
    CloudSaveEnvelope envelope, {
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    _check();
    if (_keys.contains(idempotencyKey) && remote != null) return remote!;
    final currentRevision = remote?.revision ?? 0;
    if (currentRevision != expectedRevision) throw const CloudSaveConflict();
    uploadCalls++;
    _keys.add(idempotencyKey);
    remote = envelope;
    return envelope;
  }
}
