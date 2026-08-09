import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'; // Import for compute
import 'package:shared_preferences/shared_preferences.dart';

// Top-level function for jsonDecode to be used with compute
Future<Map<String, dynamic>?> _decodeAndCastJson(String rawJson) async {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } on FormatException {
    // A damaged save should never prevent the game from opening.
  }
  return null;
}

// Top-level function for jsonEncode to be used with compute
String _encodeJson(Map<String, dynamic> data) {
  return jsonEncode(data);
}

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

  Future<String?> _readString(String key) async {
    try {
      return await _preferences.getString(key).timeout(_startupTimeout);
    } on TimeoutException {
      return null;
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'PoMarket storage',
          context: ErrorDescription('while reading saved progress from storage'),
        ),
      );
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> load() async {
    try {
      final currentRaw = await _readString(_saveKey);
      final raw = currentRaw ?? await _readString(_legacySaveKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }

      final decoded = await compute(_decodeAndCastJson, raw);
      if (decoded != null) {
        if (currentRaw == null) {
          // If loaded from legacy, save to new key and remove legacy.
          // Any storage failure here should never block startup.
          try {
            await _preferences.setString(_saveKey, raw);
            await _preferences.remove(_legacySaveKey);
          } on Object catch (error, stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'PoMarket storage',
                context: ErrorDescription('while migrating saved progress'),
              ),
            );
          }
        }
        return decoded;
      }
      return null;
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'PoMarket storage',
          context: ErrorDescription('while loading saved progress'),
        ),
      );
      return null;
    }
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    try {
      final encoded = await compute(_encodeJson, data);
      await _preferences.setString(_saveKey, encoded);
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'PoMarket storage',
          context: ErrorDescription('while saving progress'),
        ),
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _preferences.remove(_saveKey);
      await _preferences.remove(_legacySaveKey);
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'PoMarket storage',
          context: ErrorDescription('while clearing saved progress'),
        ),
      );
    }
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
