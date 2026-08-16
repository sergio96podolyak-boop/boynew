import 'app_settings.dart';
import 'monetization_service.dart';

MonetizationService createPlatformMonetizationService({
  AppSettings? settings,
}) => PreviewMonetizationService();
