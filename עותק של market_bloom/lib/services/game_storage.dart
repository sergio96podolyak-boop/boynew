import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class GameStorage {
  Future<Map<String, dynamic>?> load();

  Future<void> save(Map<String, dynamic> data);

  Future<void> clear();
}

class SharedPreferencesGameStorage implements GameStorage {
  SharedPreferencesGameStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _saveKey = 'pomarket.save.v1';
  static const _legacySaveKey = 'market_bloom.save.v1';
  static const _startupTimeout = Duration(seconds: 2);
  final SharedPreferencesAsync _preferences;

  @override
  Future<Map<String, dynamic>?> load() async {
    final currentRaw = await _preferences
        .getString(_saveKey)
        .timeout(_startupTimeout);
    final raw =
        currentRaw ??
        await _preferences.getString(_legacySaveKey).timeout(_startupTimeout);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        if (currentRaw == null) {
          await _preferences.setString(_saveKey, raw);
          await _preferences.remove(_legacySaveKey);
        }
        return decoded;
      }
    } on FormatException {
      // A damaged save should never prevent the game from opening.
    }
    return null;
  }

  @override
  Future<void> save(Map<String, dynamic> data) {
    return _preferences.setString(_saveKey, jsonEncode(data));
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(_saveKey);
    await _preferences.remove(_legacySaveKey);
  }
}

class MemoryGameStorage implements GameStorage {
  Map<String, dynamic>? data;

  @override
  Future<void> clear() async {
    data = null;
  }

  @override
  Future<Map<String, dynamic>?> load() async {
    if (data == null) {
      return null;
    }
    return Map<String, dynamic>.from(data!);
  }

  @override
  Future<void> save(Map<String, dynamic> value) async {
    data = Map<String, dynamic>.from(value);
  }
}
