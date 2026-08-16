import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class CloudPlayerIdentity {
  const CloudPlayerIdentity({
    required this.accountId,
    required this.deviceId,
    required this.syncSecret,
  });

  final String accountId;
  final String deviceId;
  final String syncSecret;

  String get recoveryCode => base64Url.encode(
    utf8.encode(
      jsonEncode(<String, String>{
        'v': '1',
        'accountId': accountId,
        'syncSecret': syncSecret,
      }),
    ),
  ).replaceAll('=', '');

  CloudPlayerIdentity withDeviceId(String value) => CloudPlayerIdentity(
    accountId: accountId,
    deviceId: value,
    syncSecret: syncSecret,
  );

  static ({String accountId, String syncSecret}) parseRecoveryCode(
    String value,
  ) {
    final raw = value.trim();
    if (raw.isEmpty) throw const FormatException('Recovery code is empty.');
    final padded = raw.padRight((raw.length + 3) ~/ 4 * 4, '=');
    final decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
    if (decoded is! Map) throw const FormatException('Invalid recovery code.');
    final accountId = '${decoded['accountId'] ?? ''}'.trim();
    final secret = '${decoded['syncSecret'] ?? ''}'.trim();
    if (accountId.length < 8 || secret.length < 16) {
      throw const FormatException('Invalid recovery code.');
    }
    return (accountId: accountId, syncSecret: secret);
  }
}

abstract interface class PlayerIdentityStore {
  Future<CloudPlayerIdentity> loadOrCreate();
  Future<CloudPlayerIdentity> adoptRecoveryCode(String recoveryCode);
}

class SharedPreferencesPlayerIdentityStore implements PlayerIdentityStore {
  SharedPreferencesPlayerIdentityStore({
    SharedPreferencesAsync? preferences,
    Random? random,
    DateTime Function()? now,
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _random = random ?? Random.secure(),
       _now = now ?? DateTime.now;

  static const _accountKey = 'pomarket.cloud.account_id.v1';
  static const _deviceKey = 'pomarket.cloud.device_id.v1';
  static const _secretKey = 'pomarket.cloud.sync_secret.v1';

  final SharedPreferencesAsync _preferences;
  final Random _random;
  final DateTime Function() _now;

  @override
  Future<CloudPlayerIdentity> loadOrCreate() async {
    final accountId = await _preferences.getString(_accountKey);
    final deviceId = await _preferences.getString(_deviceKey);
    final secret = await _preferences.getString(_secretKey);
    if (accountId != null && deviceId != null && secret != null) {
      return CloudPlayerIdentity(
        accountId: accountId,
        deviceId: deviceId,
        syncSecret: secret,
      );
    }
    final identity = CloudPlayerIdentity(
      accountId: _token('player'),
      deviceId: _token('device'),
      syncSecret: _randomToken(32),
    );
    await _persist(identity);
    return identity;
  }

  @override
  Future<CloudPlayerIdentity> adoptRecoveryCode(String recoveryCode) async {
    final recovered = CloudPlayerIdentity.parseRecoveryCode(recoveryCode);
    final existing = await loadOrCreate();
    final identity = CloudPlayerIdentity(
      accountId: recovered.accountId,
      deviceId: existing.deviceId,
      syncSecret: recovered.syncSecret,
    );
    await _persist(identity);
    return identity;
  }

  Future<void> _persist(CloudPlayerIdentity identity) async {
    await Future.wait<void>([
      _preferences.setString(_accountKey, identity.accountId),
      _preferences.setString(_deviceKey, identity.deviceId),
      _preferences.setString(_secretKey, identity.syncSecret),
    ]);
  }

  String _token(String prefix) =>
      '$prefix-${_now().toUtc().microsecondsSinceEpoch}-${_randomToken(10)}';

  String _randomToken(int length) {
    const alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List<String>.generate(
      length,
      (_) => alphabet[_random.nextInt(alphabet.length)],
      growable: false,
    ).join();
  }
}

class MemoryPlayerIdentityStore implements PlayerIdentityStore {
  MemoryPlayerIdentityStore({CloudPlayerIdentity? identity})
    : identity = identity ??
          const CloudPlayerIdentity(
            accountId: 'player-test-account',
            deviceId: 'device-test-one',
            syncSecret: 'test-secret-value-1234567890',
          );

  CloudPlayerIdentity identity;

  @override
  Future<CloudPlayerIdentity> loadOrCreate() async => identity;

  @override
  Future<CloudPlayerIdentity> adoptRecoveryCode(String recoveryCode) async {
    final parsed = CloudPlayerIdentity.parseRecoveryCode(recoveryCode);
    identity = CloudPlayerIdentity(
      accountId: parsed.accountId,
      deviceId: identity.deviceId,
      syncSecret: parsed.syncSecret,
    );
    return identity;
  }
}
