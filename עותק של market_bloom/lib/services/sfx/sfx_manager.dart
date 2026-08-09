import 'package:flutter/foundation.dart';

import 'sfx_backend.dart';
import 'sfx_platform.dart';

/// Small, fail-safe sound facade for gameplay and UI feedback.
///
/// Callers may await cue methods, but normally do not need to: playback errors
/// are contained here and never interrupt a game action.
final class SfxManager {
  SfxManager._(this._backend);

  static final SfxManager instance = SfxManager._(createSfxBackend());

  final SfxBackend _backend;
  final Map<SfxCue, DateTime> _lastPlayedAt = <SfxCue, DateTime>{};
  bool _muted = false;
  bool _disposed = false;
  bool _reportedFailure = false;
  bool _backendFailed = false;

  bool get isMuted => _muted;

  Future<void> setMuted(bool muted, {bool playFeedback = true}) async {
    if (_disposed || muted == _muted) {
      return;
    }

    _muted = muted;
    await _safely(() => _backend.setMuted(muted));
    if (!muted && playFeedback) {
      await click();
    }
  }

  Future<void> toggleMuted() => setMuted(!_muted);

  Future<void> click() => _play(SfxCue.click);

  Future<void> success() => _play(SfxCue.success);

  Future<void> milestone() => _play(SfxCue.milestone);

  Future<void> error() => _play(SfxCue.error);

  Future<void> _play(SfxCue cue) async {
    if (_muted || _disposed || _backendFailed || _isThrottled(cue)) {
      return;
    }
    await _safely(() => _backend.play(cue));
  }

  bool _isThrottled(SfxCue cue) {
    final now = DateTime.now();
    final previous = _lastPlayedAt[cue];
    final minimumGap = switch (cue) {
      SfxCue.click => const Duration(milliseconds: 35),
      SfxCue.success => const Duration(milliseconds: 70),
      SfxCue.milestone => const Duration(milliseconds: 220),
      SfxCue.error => const Duration(milliseconds: 110),
    };
    if (previous != null && now.difference(previous) < minimumGap) {
      return true;
    }
    _lastPlayedAt[cue] = now;
    return false;
  }

  Future<void> _safely(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      _backendFailed = true;
      if (!_reportedFailure) {
        _reportedFailure = true;
        debugPrint('PoMarket SFX disabled after playback failure: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _lastPlayedAt.clear();
    await _safely(_backend.dispose);
  }
}
