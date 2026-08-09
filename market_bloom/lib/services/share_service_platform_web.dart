import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';

import 'share_service_types.dart';

Future<ShareOutcome> deliverChallenge({
  required String title,
  required String message,
}) async {
  try {
    final navigator = globalContext['navigator'] as JSObject;
    if (navigator.has('share')) {
      final payload = JSObject()
        ..['title'] = title.toJS
        ..['text'] = message.toJS;
      final sharePromise = navigator.callMethod<JSPromise<JSAny?>>(
        'share'.toJS,
        payload,
      );
      await sharePromise.toDart;
      return ShareOutcome.shared;
    }
  } catch (_) {
    // Browsers may reject Web Share outside a trusted user gesture. In that
    // case, copying the same challenge keeps the action useful.
  }

  try {
    await Clipboard.setData(ClipboardData(text: message));
    return ShareOutcome.copiedToClipboard;
  } catch (_) {
    return ShareOutcome.failed;
  }
}
