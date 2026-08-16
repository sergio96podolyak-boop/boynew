import 'dart:async';

import 'package:flutter/services.dart';

import 'sfx_backend.dart';

SfxBackend createSfxBackend() => _MobileSfxBackend();

final class _MobileSfxBackend implements SfxBackend {
  bool _muted = false;
  bool _disposed = false;
  MusicPhase _currentPhase = MusicPhase.silent;
  Timer? _ambientTimer;

  @override
  Future<void> play(SfxCue cue) async {
    if (_muted || _disposed) return;
    final fallback = cue.fallback;
    final (systemSound, haptic) = switch (fallback) {
      SfxCue.click => (SystemSoundType.click, HapticFeedback.selectionClick),
      SfxCue.success => (SystemSoundType.click, HapticFeedback.lightImpact),
      SfxCue.milestone => (SystemSoundType.alert, HapticFeedback.mediumImpact),
      SfxCue.error => (SystemSoundType.alert, HapticFeedback.heavyImpact),
      _ => (SystemSoundType.click, HapticFeedback.selectionClick),
    };
    await Future.wait<void>([SystemSound.play(systemSound), haptic()]);
  }

  @override
  Future<void> playAmbient(MusicPhase phase) async {
    if (_disposed || phase == _currentPhase) return;
    _currentPhase = phase;
    _ambientTimer?.cancel();
    _ambientTimer = null;
    if (_muted || phase == MusicPhase.silent) return;

    final interval = switch (phase) {
      MusicPhase.preparation => const Duration(milliseconds: 3200),
      MusicPhase.open => const Duration(milliseconds: 2400),
      MusicPhase.rush => const Duration(milliseconds: 1400),
      MusicPhase.closing => const Duration(milliseconds: 4000),
      MusicPhase.silent => null,
    };
    if (interval == null) return;
    _ambientTimer = Timer.periodic(interval, (_) async {
      if (_muted || _disposed) return;
      await switch (_currentPhase) {
        MusicPhase.rush => HapticFeedback.lightImpact(),
        _ => HapticFeedback.selectionClick(),
      };
    });
  }

  @override
  Future<void> stopAmbient() async {
    _ambientTimer?.cancel();
    _ambientTimer = null;
    _currentPhase = MusicPhase.silent;
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    if (muted) {
      _ambientTimer?.cancel();
      _ambientTimer = null;
      _currentPhase = MusicPhase.silent;
    }
  }

  @override
  Future<void> dispose() async {
    _ambientTimer?.cancel();
    _ambientTimer = null;
    _currentPhase = MusicPhase.silent;
    _disposed = true;
  }
}
