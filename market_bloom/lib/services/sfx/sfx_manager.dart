import 'package:flutter/foundation.dart';

import 'sfx_backend.dart';
import 'sfx_platform.dart';

/// Small, fail-safe sound facade for gameplay and UI feedback.
final class SfxManager {
  SfxManager._(this._backend, this._now);

  static final SfxManager instance = SfxManager._(
    createSfxBackend(),
    DateTime.now,
  );

  @visibleForTesting
  factory SfxManager.forTesting(
    SfxBackend backend, {
    DateTime Function()? now,
  }) => SfxManager._(backend, now ?? DateTime.now);

  final SfxBackend _backend;
  final DateTime Function() _now;
  final Map<SfxCue, DateTime> _lastPlayedAt = <SfxCue, DateTime>{};
  bool _muted = false;
  bool _disposed = false;
  bool _reportedFailure = false;
  bool _backendFailed = false;
  MusicPhase _ambientPhase = MusicPhase.silent;

  bool get isMuted => _muted;

  @visibleForTesting
  bool get isDisposed => _disposed;

  @visibleForTesting
  MusicPhase get ambientPhase => _ambientPhase;

  Future<void> setMuted(bool muted, {bool playFeedback = true}) async {
    if (_disposed || muted == _muted) return;
    _muted = muted;
    await _safely(() => _backend.setMuted(muted));
    if (!muted && !_backendFailed) {
      if (_ambientPhase != MusicPhase.silent) {
        await _safely(() => _backend.playAmbient(_ambientPhase));
      }
      if (playFeedback) await click();
    }
  }

  Future<void> toggleMuted() => setMuted(!_muted);

  Future<void> click() => _play(SfxCue.click);
  Future<void> success() => _play(SfxCue.success);
  Future<void> milestone() => _play(SfxCue.milestone);
  Future<void> error() => _play(SfxCue.error);
  Future<void> pickup() => _play(SfxCue.pickup);
  Future<void> restock() => _play(SfxCue.restock);
  Future<void> checkoutScan() => _play(SfxCue.checkoutScan);
  Future<void> sale() => _play(SfxCue.sale);
  Future<void> customerWarning() => _play(SfxCue.customerWarning);
  Future<void> customerLeave() => _play(SfxCue.customerLeave);
  Future<void> deliveryArrived() => _play(SfxCue.deliveryArrived);
  Future<void> bakeryReady() => _play(SfxCue.bakeryReady);
  Future<void> registerOpen() => _play(SfxCue.registerOpen);
  Future<void> registerClose() => _play(SfxCue.registerClose);

  Future<void> playAmbient(MusicPhase phase) async {
    if (_disposed) return;
    _ambientPhase = phase;
    if (_muted || _backendFailed) return;
    await _safely(() => _backend.playAmbient(phase));
  }

  Future<void> stopAmbient() async {
    if (_disposed) return;
    _ambientPhase = MusicPhase.silent;
    if (_backendFailed) return;
    await _safely(_backend.stopAmbient);
  }

  Future<void> _play(SfxCue cue) async {
    if (_muted || _disposed || _backendFailed || _isThrottled(cue)) return;
    await _safely(() => _backend.play(cue));
  }

  bool _isThrottled(SfxCue cue) {
    final now = _now();
    final previous = _lastPlayedAt[cue];
    final minimumGap = switch (cue) {
      SfxCue.click || SfxCue.pickup || SfxCue.checkoutScan =>
        const Duration(milliseconds: 35),
      SfxCue.success || SfxCue.sale || SfxCue.bakeryReady =>
        const Duration(milliseconds: 70),
      SfxCue.restock => const Duration(milliseconds: 120),
      SfxCue.milestone || SfxCue.deliveryArrived =>
        const Duration(milliseconds: 220),
      SfxCue.error || SfxCue.customerLeave =>
        const Duration(milliseconds: 110),
      SfxCue.customerWarning => const Duration(milliseconds: 900),
      SfxCue.registerOpen || SfxCue.registerClose =>
        const Duration(milliseconds: 180),
    };
    if (previous != null && now.difference(previous) < minimumGap) return true;
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
    if (_disposed) return;
    _disposed = true;
    _ambientPhase = MusicPhase.silent;
    _lastPlayedAt.clear();
    await _safely(_backend.dispose);
  }
}
