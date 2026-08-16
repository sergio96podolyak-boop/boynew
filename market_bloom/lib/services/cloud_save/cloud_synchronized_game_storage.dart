import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../game_storage.dart';
import 'cloud_save_backend.dart';
import 'cloud_save_models.dart';
import 'cloud_save_status.dart';
import 'player_identity.dart';

abstract interface class CloudSyncMetadataStore {
  Future<CloudSyncMetadata> load();
  Future<void> save(CloudSyncMetadata metadata);
  Future<void> clear();
}

class SharedPreferencesCloudSyncMetadataStore
    implements CloudSyncMetadataStore {
  SharedPreferencesCloudSyncMetadataStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _revisionKey = 'pomarket.cloud.remote_revision.v1';
  static const _hashKey = 'pomarket.cloud.last_hash.v1';
  static const _syncedAtKey = 'pomarket.cloud.last_synced_at.v1';
  static const _preferRemoteKey = 'pomarket.cloud.prefer_remote_once.v1';
  static const _pendingDeleteKey = 'pomarket.cloud.pending_delete.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<CloudSyncMetadata> load() async => CloudSyncMetadata(
    remoteRevision: await _preferences.getInt(_revisionKey) ?? 0,
    lastSyncedHash: await _preferences.getString(_hashKey),
    lastSyncedAt: DateTime.tryParse(
      await _preferences.getString(_syncedAtKey) ?? '',
    )?.toUtc(),
    preferRemoteOnce: await _preferences.getBool(_preferRemoteKey) ?? false,
    pendingDelete: await _preferences.getBool(_pendingDeleteKey) ?? false,
  );

  @override
  Future<void> save(CloudSyncMetadata metadata) async {
    await _preferences.setInt(_revisionKey, metadata.remoteRevision);
    if (metadata.lastSyncedHash case final hash?) {
      await _preferences.setString(_hashKey, hash);
    } else {
      await _preferences.remove(_hashKey);
    }
    if (metadata.lastSyncedAt case final syncedAt?) {
      await _preferences.setString(
        _syncedAtKey,
        syncedAt.toUtc().toIso8601String(),
      );
    } else {
      await _preferences.remove(_syncedAtKey);
    }
    await _preferences.setBool(_preferRemoteKey, metadata.preferRemoteOnce);
    await _preferences.setBool(_pendingDeleteKey, metadata.pendingDelete);
  }

  @override
  Future<void> clear() async {
    await Future.wait<void>([
      _preferences.remove(_revisionKey),
      _preferences.remove(_hashKey),
      _preferences.remove(_syncedAtKey),
      _preferences.remove(_preferRemoteKey),
      _preferences.remove(_pendingDeleteKey),
    ]);
  }
}

class MemoryCloudSyncMetadataStore implements CloudSyncMetadataStore {
  CloudSyncMetadata metadata = const CloudSyncMetadata();

  @override
  Future<void> clear() async => metadata = const CloudSyncMetadata();
  @override
  Future<CloudSyncMetadata> load() async => metadata;
  @override
  Future<void> save(CloudSyncMetadata value) async => metadata = value;
}

class CloudSyncResult {
  const CloudSyncResult({
    required this.state,
    this.remoteAppliedLocally = false,
  });

  final CloudSaveState state;
  final bool remoteAppliedLocally;
}

/// Offline-first decorator for the existing GameStorage abstraction.
class CloudSynchronizedGameStorage implements GameStorage {
  CloudSynchronizedGameStorage({
    required this.local,
    required this.backend,
    required this.identityStore,
    required this.metadataStore,
    CloudSaveStatus? status,
    this.conflictResolver = const CloudSaveConflictResolver(),
    DateTime Function()? now,
  }) : status = status ?? CloudSaveStatus(),
       _now = now ?? DateTime.now;

  final GameStorage local;
  final CloudSaveBackend backend;
  final PlayerIdentityStore identityStore;
  final CloudSyncMetadataStore metadataStore;
  final CloudSaveStatus status;
  final CloudSaveConflictResolver conflictResolver;
  final DateTime Function() _now;

  Future<CloudSyncResult>? _syncInProgress;
  bool _syncRequested = false;
  Map<String, dynamic>? _lastLocalSnapshot;

  bool get cloudAvailable => backend.isAvailable;
  Future<CloudPlayerIdentity> get identity => identityStore.loadOrCreate();
  Future<String> get recoveryCode async =>
      (await identityStore.loadOrCreate()).recoveryCode;

  @override
  Future<Map<String, dynamic>?> load() async {
    final value = await local.load();
    _lastLocalSnapshot = value == null ? null : deepCopyMap(value);
    if (backend.isAvailable) {
      status.update(CloudSaveState.pending, message: 'Cloud sync pending');
      unawaited(syncNow(localSnapshot: value));
    } else {
      _localOnly('Cloud endpoint is not configured');
    }
    return value;
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    final snapshot = deepCopyMap(data);
    _lastLocalSnapshot = snapshot;
    await local.save(snapshot);
    if (!backend.isAvailable) {
      _localOnly('Saved locally; cloud is unavailable');
      return;
    }
    status.update(CloudSaveState.pending, message: 'Upload pending');
    unawaited(syncNow(localSnapshot: snapshot));
  }

  @override
  Future<void> clear() async {
    _lastLocalSnapshot = null;
    await local.clear();
    await metadataStore.save(const CloudSyncMetadata(pendingDelete: true));
    if (!backend.isAvailable) {
      _localOnly('Local save cleared; cloud deletion is pending');
      return;
    }
    await syncNow();
  }

  void _localOnly(String message) =>
      status.update(CloudSaveState.localOnly, message: message);

  Future<CloudSyncResult> syncNow({Map<String, dynamic>? localSnapshot}) {
    if (!backend.isAvailable) {
      _localOnly('Cloud endpoint is not configured');
      return Future.value(
        const CloudSyncResult(state: CloudSaveState.localOnly),
      );
    }
    if (_syncInProgress case final current?) {
      _syncRequested = true;
      if (localSnapshot != null) {
        _lastLocalSnapshot = deepCopyMap(localSnapshot);
      }
      return current;
    }
    final future = _runLoop(localSnapshot);
    _syncInProgress = future;
    return future.whenComplete(() => _syncInProgress = null);
  }

  Future<CloudSyncResult> _runLoop(Map<String, dynamic>? snapshot) async {
    var next = snapshot;
    var result = const CloudSyncResult(state: CloudSaveState.synced);
    do {
      _syncRequested = false;
      result = await _syncOnce(next);
      next = _lastLocalSnapshot;
    } while (_syncRequested);
    return result;
  }

  Future<CloudSyncResult> _syncOnce(Map<String, dynamic>? supplied) async {
    status.update(CloudSaveState.syncing, message: 'Synchronizing');
    try {
      final identity = await identityStore.loadOrCreate();
      var metadata = await metadataStore.load();
      final localSave = supplied ?? _lastLocalSnapshot ?? await local.load();
      CloudSaveEnvelope? remote;
      if (metadata.pendingDelete) {
        await backend.delete(identity);
        await metadataStore.clear();
        metadata = const CloudSyncMetadata();
      } else {
        remote = await backend.download(identity);
        _validateRemoteIdentity(identity, remote);
      }
      return _resolve(identity, metadata, localSave, remote);
    } on CloudSaveUnavailable catch (error) {
      _localOnly(error.message);
      return const CloudSyncResult(state: CloudSaveState.localOnly);
    } catch (error) {
      status.update(CloudSaveState.error, message: '$error');
      return const CloudSyncResult(state: CloudSaveState.error);
    }
  }

  void _validateRemoteIdentity(
    CloudPlayerIdentity identity,
    CloudSaveEnvelope? remote,
  ) {
    if (remote == null ||
        remote.accountId.isEmpty ||
        remote.accountId == identity.accountId) {
      return;
    }
    throw const FormatException('Cloud save belongs to another account.');
  }

  Future<CloudSyncResult> _resolve(
    CloudPlayerIdentity identity,
    CloudSyncMetadata metadata,
    Map<String, dynamic>? localSave,
    CloudSaveEnvelope? remote,
  ) async {
    if (localSave == null && remote == null) {
      return _markSynced(metadata.remoteRevision, null);
    }
    if (localSave == null) return _download(remote!);
    final localHash = stableSaveHash(localSave);
    if (remote == null) {
      return _upload(identity, localSave, localHash, expectedRevision: 0);
    }
    if (metadata.preferRemoteOnce) return _download(remote);
    if (localHash == remote.contentHash) {
      return _markSynced(remote.revision, localHash);
    }
    final lastHash = metadata.lastSyncedHash;
    if (lastHash != null && localHash == lastHash) return _download(remote);
    if (lastHash != null && remote.contentHash == lastHash) {
      return _upload(
        identity,
        localSave,
        localHash,
        expectedRevision: remote.revision,
      );
    }
    if (conflictResolver.resolve(localSave, remote.payload) ==
        CloudConflictWinner.remote) {
      await _download(remote);
      status.update(
        CloudSaveState.conflictResolved,
        syncedAt: remote.modifiedAt,
        message: 'Cloud progress was newer and was recovered locally',
        remoteAppliedLocally: true,
      );
      return const CloudSyncResult(
        state: CloudSaveState.conflictResolved,
        remoteAppliedLocally: true,
      );
    }
    await _upload(
      identity,
      localSave,
      localHash,
      expectedRevision: remote.revision,
    );
    status.update(
      CloudSaveState.conflictResolved,
      syncedAt: _now().toUtc(),
      message: 'Local progress was newer and replaced the cloud save',
    );
    return const CloudSyncResult(state: CloudSaveState.conflictResolved);
  }

  Future<CloudSyncResult> _upload(
    CloudPlayerIdentity identity,
    Map<String, dynamic> localSave,
    String localHash, {
    required int expectedRevision,
  }) async {
    final envelope = CloudSaveEnvelope.create(
      accountId: identity.accountId,
      deviceId: identity.deviceId,
      revision: expectedRevision + 1,
      modifiedAt: _saveTime(localSave),
      payload: localSave,
    );
    try {
      final uploaded = await backend.upload(
        identity,
        envelope,
        expectedRevision: expectedRevision,
        idempotencyKey: '${identity.accountId}:$expectedRevision:$localHash',
      );
      _validateRemoteIdentity(identity, uploaded);
      if (uploaded.contentHash != localHash) {
        throw const FormatException(
          'Cloud upload response does not match the local save.',
        );
      }
      await _saveMetadata(uploaded);
      status.update(
        CloudSaveState.synced,
        syncedAt: uploaded.modifiedAt,
        message: 'Cloud save is up to date',
      );
      return const CloudSyncResult(state: CloudSaveState.synced);
    } on CloudSaveConflict {
      final latest = await backend.download(identity);
      _validateRemoteIdentity(identity, latest);
      if (latest == null) rethrow;
      if (conflictResolver.resolve(localSave, latest.payload) ==
          CloudConflictWinner.local) {
        return _upload(
          identity,
          localSave,
          localHash,
          expectedRevision: latest.revision,
        );
      }
      await _download(latest);
      status.update(
        CloudSaveState.conflictResolved,
        syncedAt: latest.modifiedAt,
        message: 'Cloud progress changed during sync and was recovered locally',
        remoteAppliedLocally: true,
      );
      return const CloudSyncResult(
        state: CloudSaveState.conflictResolved,
        remoteAppliedLocally: true,
      );
    }
  }

  Future<CloudSyncResult> _download(CloudSaveEnvelope remote) async {
    final payload = deepCopyMap(remote.payload);
    await local.save(payload);
    _lastLocalSnapshot = payload;
    await _saveMetadata(remote);
    status.update(
      CloudSaveState.downloaded,
      syncedAt: remote.modifiedAt,
      message: 'Cloud progress downloaded; reopen the game to apply it',
      remoteAppliedLocally: true,
    );
    return const CloudSyncResult(
      state: CloudSaveState.downloaded,
      remoteAppliedLocally: true,
    );
  }

  Future<void> _saveMetadata(CloudSaveEnvelope envelope) =>
      metadataStore.save(
        CloudSyncMetadata(
          remoteRevision: envelope.revision,
          lastSyncedHash: envelope.contentHash,
          lastSyncedAt: envelope.modifiedAt,
        ),
      );

  Future<CloudSyncResult> _markSynced(int revision, String? hash) async {
    final now = _now().toUtc();
    await metadataStore.save(
      CloudSyncMetadata(
        remoteRevision: revision,
        lastSyncedHash: hash,
        lastSyncedAt: now,
      ),
    );
    status.update(
      CloudSaveState.synced,
      syncedAt: now,
      message: 'Cloud save is up to date',
    );
    return const CloudSyncResult(state: CloudSaveState.synced);
  }

  Future<CloudSyncResult> recoverWithCode(String recoveryCode) async {
    await identityStore.adoptRecoveryCode(recoveryCode);
    await metadataStore.save(const CloudSyncMetadata(preferRemoteOnce: true));
    _lastLocalSnapshot = await local.load();
    return syncNow(localSnapshot: _lastLocalSnapshot);
  }

  DateTime _saveTime(Map<String, dynamic> save) =>
      DateTime.tryParse('${save['savedAt'] ?? ''}')?.toUtc() ?? _now().toUtc();
}
