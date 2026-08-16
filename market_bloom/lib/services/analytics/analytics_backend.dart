import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'analytics_event.dart';

abstract interface class AnalyticsBackend {
  bool get isAvailable;
  Future<void> send(AnalyticsEvent event);
}

class DisabledAnalyticsBackend implements AnalyticsBackend {
  const DisabledAnalyticsBackend();

  @override
  bool get isAvailable => false;

  @override
  Future<void> send(AnalyticsEvent event) async {}
}

class RestAnalyticsBackend implements AnalyticsBackend {
  RestAnalyticsBackend({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 4),
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  @override
  bool get isAvailable => baseUrl.isNotEmpty;

  @override
  Future<void> send(AnalyticsEvent event) async {
    if (!isAvailable) return;
    final response = await _client
        .post(
          Uri.parse('$baseUrl/v1/analytics/events'),
          headers: const <String, String>{
            'content-type': 'application/json',
            'accept': 'application/json',
          },
          body: jsonEncode(<String, Object>{
            'schemaVersion': 1,
            'name': event.name.wireName,
            'parameters': event.parameters,
          }),
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Analytics backend rejected the event.');
    }
  }
}
