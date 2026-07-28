import 'dart:io';

import 'mobile_monetization_service.dart';
import 'monetization_service.dart';

MonetizationService createPlatformMonetizationService() {
  if (Platform.isAndroid || Platform.isIOS) {
    return MobileMonetizationService();
  }
  return PreviewMonetizationService();
}
