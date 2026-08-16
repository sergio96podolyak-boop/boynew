import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_save/player_identity.dart';
import 'monetization_service.dart';

enum PurchaseVerificationStatus { verified, invalid, pending, unavailable }

class PurchaseVerificationRequest {
  const PurchaseVerificationRequest({
    required this.product,
    required this.productId,
    required this.transactionId,
    required this.source,
    required this.serverVerificationData,
    required this.localVerificationData,
    required this.restored,
    this.transactionDate,
  });

  final StoreProduct product;
  final String productId;
  final String transactionId;
  final String source;
  final String serverVerificationData;
  final String localVerificationData;
  final bool restored;
  final String? transactionDate;
}

class PurchaseVerificationResult {
  const PurchaseVerificationResult({
    required this.status,
    this.transactionId,
    this.productId,
  });

  const PurchaseVerificationResult.verified({
    required String transactionId,
    required String productId,
  }) : this(
         status: PurchaseVerificationStatus.verified,
         transactionId: transactionId,
         productId: productId,
       );

  const PurchaseVerificationResult.invalid()
    : this(status: PurchaseVerificationStatus.invalid);

  const PurchaseVerificationResult.pending()
    : this(status: PurchaseVerificationStatus.pending);

  const PurchaseVerificationResult.unavailable()
    : this(status: PurchaseVerificationStatus.unavailable);

  final PurchaseVerificationStatus status;
  final String? transactionId;
  final String? productId;

  bool get isVerified => status == PurchaseVerificationStatus.verified;
  bool get canRetry =>
      status == PurchaseVerificationStatus.pending ||
      status == PurchaseVerificationStatus.unavailable;
}

abstract interface class PurchaseVerificationService {
  bool get isAvailable;

  Future<PurchaseVerificationResult> verify(
    PurchaseVerificationRequest request,
  );
}

class DisabledPurchaseVerificationService
    implements PurchaseVerificationService {
  const DisabledPurchaseVerificationService();

  @override
  bool get isAvailable => false;

  @override
  Future<PurchaseVerificationResult> verify(
    PurchaseVerificationRequest request,
  ) async => const PurchaseVerificationResult.unavailable();
}

/// Client for the existing PoMarket backend.
///
/// The backend must verify App Store/Google Play data with the relevant store,
/// atomically bind the transaction to the player account, and return the same
/// verified response for repeated requests with the same idempotency key.
class RestPurchaseVerificationService
    implements PurchaseVerificationService {
  RestPurchaseVerificationService({
    required String baseUrl,
    required this.identityStore,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  final String baseUrl;
  final PlayerIdentityStore identityStore;
  final http.Client _client;
  final Duration timeout;

  @override
  bool get isAvailable => baseUrl.trim().isNotEmpty;

  @override
  Future<PurchaseVerificationResult> verify(
    PurchaseVerificationRequest request,
  ) async {
    if (!isAvailable ||
        request.transactionId.trim().isEmpty ||
        request.productId.trim().isEmpty ||
        request.source.trim().isEmpty ||
        request.serverVerificationData.trim().isEmpty) {
      return const PurchaseVerificationResult.unavailable();
    }

    try {
      final identity = await identityStore.loadOrCreate();
      final response = await _client
          .post(
            Uri.parse('$baseUrl/v1/purchases/verify'),
            headers: <String, String>{
              'content-type': 'application/json',
              'accept': 'application/json',
              'x-pomarket-sync-secret': identity.syncSecret,
              'x-pomarket-device-id': identity.deviceId,
              'idempotency-key': _idempotencyKey(identity, request),
            },
            body: jsonEncode(<String, Object?>{
              'schemaVersion': 1,
              'accountId': identity.accountId,
              'deviceId': identity.deviceId,
              'product': request.product.name,
              'productId': request.productId,
              'transactionId': request.transactionId,
              'source': request.source,
              'serverVerificationData': request.serverVerificationData,
              'localVerificationData': request.localVerificationData,
              'transactionDate': request.transactionDate,
              'restored': request.restored,
            }),
          )
          .timeout(timeout);

      if (response.statusCode == 202) {
        return const PurchaseVerificationResult.pending();
      }
      if (response.statusCode == 400 ||
          response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 409 ||
          response.statusCode == 422) {
        return const PurchaseVerificationResult.invalid();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const PurchaseVerificationResult.unavailable();
      }

      final decoded = response.body.trim().isEmpty
          ? null
          : jsonDecode(response.body);
      if (decoded is! Map) {
        return const PurchaseVerificationResult.invalid();
      }
      final status = '${decoded['status'] ?? ''}'.trim().toLowerCase();
      if (status == 'pending') {
        return const PurchaseVerificationResult.pending();
      }
      if (status == 'invalid' || decoded['valid'] == false) {
        return const PurchaseVerificationResult.invalid();
      }
      if (status != 'verified' && decoded['valid'] != true) {
        return const PurchaseVerificationResult.invalid();
      }

      final transactionId = '${decoded['transactionId'] ?? ''}'.trim();
      final productId = '${decoded['productId'] ?? ''}'.trim();
      final accountId = '${decoded['accountId'] ?? identity.accountId}'.trim();
      if (transactionId != request.transactionId ||
          productId != request.productId ||
          accountId != identity.accountId) {
        return const PurchaseVerificationResult.invalid();
      }
      return PurchaseVerificationResult.verified(
        transactionId: transactionId,
        productId: productId,
      );
    } on TimeoutException {
      return const PurchaseVerificationResult.unavailable();
    } on Object {
      return const PurchaseVerificationResult.unavailable();
    }
  }

  String _idempotencyKey(
    CloudPlayerIdentity identity,
    PurchaseVerificationRequest request,
  ) => '${identity.accountId}:${request.source}:${request.transactionId}';
}
