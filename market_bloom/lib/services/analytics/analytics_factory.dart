import '../app_settings.dart';
import 'analytics_backend.dart';
import 'analytics_service.dart';

AnalyticsService createAnalyticsService(AppSettings settings) {
  const endpoint = String.fromEnvironment('POMARKET_ANALYTICS_ENDPOINT');
  final backend = endpoint.trim().isEmpty
      ? const DisabledAnalyticsBackend()
      : RestAnalyticsBackend(baseUrl: endpoint);
  return AnalyticsService(
    backend: backend,
    hasConsent: () => settings.analyticsEnabled,
  );
}
