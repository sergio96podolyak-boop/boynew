import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' as native_share;

import 'share_service_types.dart';

Future<ShareOutcome> deliverChallenge({
  required String title,
  required String message,
}) async {
  try {
    final result = await native_share.SharePlus.instance.share(
      native_share.ShareParams(title: title, text: message),
    );
    if (result.status != native_share.ShareResultStatus.unavailable) {
      return ShareOutcome.shared;
    }
  } catch (_) {
    // Fall through to a clipboard copy if the platform share sheet is absent.
  }

  try {
    await Clipboard.setData(ClipboardData(text: message));
    return ShareOutcome.copiedToClipboard;
  } catch (_) {
    return ShareOutcome.failed;
  }
}
