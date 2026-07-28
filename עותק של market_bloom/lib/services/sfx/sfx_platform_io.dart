import 'package:flutter/services.dart';

import 'sfx_backend.dart';

SfxBackend createSfxBackend() => _MobileSfxBackend();

final class _MobileSfxBackend implements SfxBackend {
  bool _muted = false;
  bool _disposed = false;

  @override
  Future<void> play(SfxCue cue) async {
    if (_muted || _disposed) {
      return;
    }

    final (systemSound, haptic) = switch (cue) {
      SfxCue.click => (SystemSoundType.click, HapticFeedback.selectionClick),
      SfxCue.success => (SystemSoundType.click, HapticFeedback.lightImpact),
      SfxCue.milestone => (SystemSoundType.alert, HapticFeedback.mediumImpact),
      SfxCue.error => (SystemSoundType.alert, HapticFeedback.heavyImpact),
    };

    await Future.wait<void>([SystemSound.play(systemSound), haptic()]);
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
