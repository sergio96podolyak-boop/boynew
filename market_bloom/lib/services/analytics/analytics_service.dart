import 'dart:async';

import 'analytics_backend.dart';
import 'analytics_event.dart';

class AnalyticsService {
  AnalyticsService({
    required this.backend,
    required this.hasConsent,
  });

  final AnalyticsBackend backend;
  final bool Function() hasConsent;
  final Set<String> _dedupeKeys = <String>{};

  bool get isEnabled => hasConsent() && backend.isAvailable;

  void track(
    AnalyticsEventName name, {
    Map<String, Object?> parameters = const <String, Object?>{},
    String? dedupeKey,
  }) {
    if (!isEnabled) return;
    if (dedupeKey != null && !_dedupeKeys.add('${name.wireName}:$dedupeKey')) {
      return;
    }
    final safe = _sanitize(parameters);
    unawaited(_send(AnalyticsEvent(name: name, parameters: safe)));
  }

  Future<void> _send(AnalyticsEvent event) async {
    try {
      await backend.send(event);
    } on Object {
      // Analytics is optional and must never affect gameplay or startup.
    }
  }

  Map<String, Object> _sanitize(Map<String, Object?> source) {
    final result = <String, Object>{};
    for (final entry in source.entries) {
      final key = entry.key.trim();
      final lower = key.toLowerCase();
      if (key.isEmpty ||
          lower.contains('secret') ||
          lower.contains('token') ||
          lower.contains('receipt') ||
          lower.contains('verification') ||
          lower.contains('payload') ||
          lower.contains('account') ||
          lower.contains('device') ||
          lower.contains('transaction')) {
        continue;
      }
      final value = entry.value;
      if (value is String) {
        result[key] = value.length <= 80 ? value : value.substring(0, 80);
      } else if (value is num || value is bool) {
        result[key] = value!;
      }
    }
    return result;
  }
}
