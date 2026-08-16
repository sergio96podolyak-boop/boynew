import 'dart:convert';

const cloudEnvelopeSchemaVersion = 1;

class CloudSaveEnvelope {
  const CloudSaveEnvelope({
    required this.schemaVersion,
    required this.accountId,
    required this.deviceId,
    required this.revision,
    required this.modifiedAt,
    required this.contentHash,
    required this.payload,
  });

  factory CloudSaveEnvelope.create({
    required String accountId,
    required String deviceId,
    required int revision,
    required DateTime modifiedAt,
    required Map<String, dynamic> payload,
  }) {
    final copy = deepCopyMap(payload);
    return CloudSaveEnvelope(
      schemaVersion: cloudEnvelopeSchemaVersion,
      accountId: accountId,
      deviceId: deviceId,
      revision: revision < 0 ? 0 : revision,
      modifiedAt: modifiedAt.toUtc(),
      contentHash: stableSaveHash(copy),
      payload: copy,
    );
  }

  factory CloudSaveEnvelope.fromJson(
    Object? value, {
    String fallbackAccountId = '',
  }) {
    if (value is! Map) {
      throw const FormatException('Cloud save envelope must be a map.');
    }
    final json = <String, dynamic>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final rawPayload = json['payload'];
    final payload = rawPayload is Map
        ? <String, dynamic>{
            for (final entry in rawPayload.entries)
              if (entry.key is String) entry.key as String: entry.value,
          }
        : _looksLikeLegacyGameSave(json)
        ? Map<String, dynamic>.from(json)
        : <String, dynamic>{};
    if (payload.isEmpty) {
      throw const FormatException('Cloud save payload is missing.');
    }

    final schemaVersion = _safeInt(json['schemaVersion'], fallback: 0);
    if (schemaVersion > cloudEnvelopeSchemaVersion) {
      throw FormatException(
        'Unsupported cloud save schema version: $schemaVersion.',
      );
    }
    final modifiedAt =
        DateTime.tryParse(
          '${json['modifiedAt'] ?? json['savedAt'] ?? ''}',
        )?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final calculatedHash = stableSaveHash(payload);
    final suppliedHash = '${json['contentHash'] ?? ''}'.trim();
    if (suppliedHash.isNotEmpty && suppliedHash != calculatedHash) {
      throw const FormatException('Cloud save content hash is invalid.');
    }
    return CloudSaveEnvelope(
      schemaVersion: schemaVersion,
      accountId: '${json['accountId'] ?? fallbackAccountId}'.trim(),
      deviceId: '${json['deviceId'] ?? 'legacy'}'.trim(),
      revision: _safeInt(json['revision']),
      modifiedAt: modifiedAt,
      contentHash: calculatedHash,
      payload: deepCopyMap(payload),
    );
  }

  final int schemaVersion;
  final String accountId;
  final String deviceId;
  final int revision;
  final DateTime modifiedAt;
  final String contentHash;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'accountId': accountId,
    'deviceId': deviceId,
    'revision': revision,
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
    'contentHash': contentHash,
    'payload': deepCopyMap(payload),
  };
}

class CloudSyncMetadata {
  const CloudSyncMetadata({
    this.remoteRevision = 0,
    this.lastSyncedHash,
    this.lastSyncedAt,
    this.preferRemoteOnce = false,
    this.pendingDelete = false,
  });

  factory CloudSyncMetadata.fromJson(Object? value) {
    if (value is! Map) return const CloudSyncMetadata();
    return CloudSyncMetadata(
      remoteRevision: _safeInt(value['remoteRevision']),
      lastSyncedHash: value['lastSyncedHash'] is String
          ? value['lastSyncedHash'] as String
          : null,
      lastSyncedAt: DateTime.tryParse(
        '${value['lastSyncedAt'] ?? ''}',
      )?.toUtc(),
      preferRemoteOnce: value['preferRemoteOnce'] == true,
      pendingDelete: value['pendingDelete'] == true,
    );
  }

  final int remoteRevision;
  final String? lastSyncedHash;
  final DateTime? lastSyncedAt;
  final bool preferRemoteOnce;
  final bool pendingDelete;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'remoteRevision': remoteRevision,
    'lastSyncedHash': lastSyncedHash,
    'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
    'preferRemoteOnce': preferRemoteOnce,
    'pendingDelete': pendingDelete,
  };
}

enum CloudConflictWinner { local, remote }

class CloudSaveConflictResolver {
  const CloudSaveConflictResolver();

  CloudConflictWinner resolve(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final localRank = _rank(local);
    final remoteRank = _rank(remote);
    for (var index = 0; index < localRank.length; index++) {
      final comparison = localRank[index].compareTo(remoteRank[index]);
      if (comparison > 0) return CloudConflictWinner.local;
      if (comparison < 0) return CloudConflictWinner.remote;
    }
    return stableSaveHash(local).compareTo(stableSaveHash(remote)) >= 0
        ? CloudConflictWinner.local
        : CloudConflictWinner.remote;
  }

  List<int> _rank(Map<String, dynamic> save) => <int>[
    _safeInt(save['saveSchemaVersion']),
    _safeInt(save['version']),
    _safeInt(save['totalSales']),
    _safeInt(save['totalCoinsEarned']),
    _safeInt(save['upgradesBought']),
    _safeInt(save['totalActions']),
    DateTime.tryParse(
          '${save['savedAt'] ?? ''}',
        )?.toUtc().millisecondsSinceEpoch ??
        0,
  ];
}

// Parsed from strings so dart2js never has to represent these 64-bit values as
// JavaScript number literals. BigInt keeps the original FNV-style arithmetic
// exact on native and web targets, preserving hashes produced before this fix.
final BigInt _stableHashOffset = BigInt.parse('cbf29ce484222325', radix: 16);
final BigInt _stableHashPrime = BigInt.parse('100000001b3', radix: 16);
final BigInt _stableHashMask = BigInt.parse('7fffffffffffffff', radix: 16);

String stableSaveHash(Map<String, dynamic> value) {
  final canonical = jsonEncode(_canonicalize(value));
  var hash = _stableHashOffset;
  for (final byte in utf8.encode(canonical)) {
    hash = ((hash ^ BigInt.from(byte)) * _stableHashPrime) & _stableHashMask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

Map<String, dynamic> deepCopyMap(Map<String, dynamic> source) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map);

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.whereType<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalize).toList(growable: false);
  return value;
}

bool _looksLikeLegacyGameSave(Map<String, dynamic> value) =>
    value.containsKey('coins') || value.containsKey('totalSales');

int _safeInt(Object? value, {int fallback = 0}) {
  final parsed = switch (value) {
    int number => number,
    num number when number.isFinite => number.round(),
    String text => num.tryParse(text.trim())?.round(),
    _ => null,
  };
  return parsed == null || parsed < 0 ? fallback : parsed;
}
