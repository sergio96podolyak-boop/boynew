// ignore_for_file: use_null_aware_elements

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_save_models.dart';
import 'player_identity.dart';

abstract interface class CloudSaveBackend {
  bool get isAvailable;
  Future<CloudSaveEnvelope?> download(CloudPlayerIdentity identity);
  Future<CloudSaveEnvelope> upload(
    CloudPlayerIdentity identity,
    CloudSaveEnvelope envelope, {
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<void> delete(CloudPlayerIdentity identity);
}

class CloudSaveUnavailable implements Exception {
  const CloudSaveUnavailable([this.message = 'Cloud save is unavailable.']);
  final String message;
  @override
  String toString() => message;
}

class CloudSaveConflict implements Exception {
  const CloudSaveConflict();
}

class CloudSaveRequestFailed implements Exception {
  const CloudSaveRequestFailed(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'Cloud request failed ($statusCode): $message';
}

class DisabledCloudSaveBackend implements CloudSaveBackend {
  const DisabledCloudSaveBackend();

  @override
  bool get isAvailable => false;
  @override
  Future<void> delete(CloudPlayerIdentity identity) async =>
      throw const CloudSaveUnavailable();
  @override
  Future<CloudSaveEnvelope?> download(CloudPlayerIdentity identity) async =>
      throw const CloudSaveUnavailable();
  @override
  Future<CloudSaveEnvelope> upload(
    CloudPlayerIdentity identity,
    CloudSaveEnvelope envelope, {
    required int expectedRevision,
    required String idempotencyKey,
  }) async => throw const CloudSaveUnavailable();
}

/// Vendor-neutral REST transport.
/// GET/PUT/DELETE {baseUrl}/v1/saves/{accountId}
class RestCloudSaveBackend implements CloudSaveBackend {
  RestCloudSaveBackend({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  @override
  bool get isAvailable => baseUrl.isNotEmpty;

  Uri _uri(String accountId) =>
      Uri.parse('$baseUrl/v1/saves/${Uri.encodeComponent(accountId)}');

  Map<String, String> _headers(
    CloudPlayerIdentity identity, {
    String? idempotencyKey,
    int? expectedRevision,
  }) => <String, String>{
    'content-type': 'application/json',
    'accept': 'application/json',
    'x-pomarket-sync-secret': identity.syncSecret,
    'x-pomarket-device-id': identity.deviceId,
    if (idempotencyKey != null) 'idempotency-key': idempotencyKey,
    if (expectedRevision != null) 'if-match': '$expectedRevision',
  };

  @override
  Future<CloudSaveEnvelope?> download(CloudPlayerIdentity identity) async {
    if (!isAvailable) throw const CloudSaveUnavailable();
    final response = await _client
        .get(_uri(identity.accountId), headers: _headers(identity))
        .timeout(timeout);
    if (response.statusCode == 404 || response.statusCode == 204) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudSaveRequestFailed(response.statusCode, response.body);
    }
    return CloudSaveEnvelope.fromJson(
      jsonDecode(response.body),
      fallbackAccountId: identity.accountId,
    );
  }

  @override
  Future<CloudSaveEnvelope> upload(
    CloudPlayerIdentity identity,
    CloudSaveEnvelope envelope, {
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    if (!isAvailable) throw const CloudSaveUnavailable();
    final response = await _client
        .put(
          _uri(identity.accountId),
          headers: _headers(
            identity,
            idempotencyKey: idempotencyKey,
            expectedRevision: expectedRevision,
          ),
          body: jsonEncode(envelope.toJson()),
        )
        .timeout(timeout);
    if (response.statusCode == 409 || response.statusCode == 412) {
      throw const CloudSaveConflict();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudSaveRequestFailed(response.statusCode, response.body);
    }
    if (response.body.trim().isEmpty) return envelope;
    return CloudSaveEnvelope.fromJson(
      jsonDecode(response.body),
      fallbackAccountId: identity.accountId,
    );
  }

  @override
  Future<void> delete(CloudPlayerIdentity identity) async {
    if (!isAvailable) throw const CloudSaveUnavailable();
    final response = await _client
        .delete(_uri(identity.accountId), headers: _headers(identity))
        .timeout(timeout);
    if (response.statusCode == 404 || response.statusCode == 204) return;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudSaveRequestFailed(response.statusCode, response.body);
    }
  }
}
