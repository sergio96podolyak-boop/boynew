import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import 'sfx_backend.dart';

/// Adds packaged PoMarket audio to an existing platform backend.
///
/// Any missing asset, decoder, or platform-plugin failure falls through to the
/// original Web/SystemSound/Haptics/Stub implementation. When Flutter services
/// have not been initialized yet (for example, in pure controller tests), audio
/// stays silent instead of invoking a platform channel and disabling SFX.
final class AssetSfxBackend implements SfxBackend {
  AssetSfxBackend(this._fallback) {
    try {
      // AudioPlayer and the mobile fallback both require Flutter services.
      // Pure controller tests intentionally have no binding, so all playback
      // must remain a safe no-op in that environment.
      WidgetsBinding.instance;
      _platformAudioAvailable = true;
      _musicPlayer = AudioPlayer();
      _ambiencePlayer = AudioPlayer();
      for (final entry in _cueAssets.entries) {
        _pools[entry.key] = _preload(entry.value);
      }
    } on Object {
      _assetAudioAvailable = false;
      _platformAudioAvailable = false;
    }
  }

  static const _cueAssets = <SfxCue, String>{
    SfxCue.click: 'audio/sfx/ui/sfx_ui_click_v01.wav',
    SfxCue.success: 'audio/sfx/ui/sfx_ui_success_v01.wav',
    SfxCue.milestone:
        'audio/sfx/progression/sfx_progress_milestone_v01.wav',
    SfxCue.error: 'audio/sfx/ui/sfx_ui_error_v01.wav',
    SfxCue.pickup: 'audio/sfx/inventory/sfx_inventory_pickup_v01.wav',
    SfxCue.restock:
        'audio/sfx/inventory/sfx_inventory_shelf_place_v01.wav',
    SfxCue.checkoutScan: 'audio/sfx/checkout/sfx_checkout_scan_v01.wav',
    SfxCue.sale:
        'audio/sfx/checkout/sfx_checkout_payment_complete_v01.wav',
    SfxCue.customerWarning:
        'audio/sfx/customers/sfx_customer_warning_v01.wav',
    SfxCue.customerLeave:
        'audio/sfx/customers/sfx_customer_leave_v01.wav',
    SfxCue.deliveryArrived:
        'audio/sfx/delivery/sfx_delivery_arrived_v01.wav',
    SfxCue.bakeryReady: 'audio/sfx/bakery/sfx_bakery_ready_v01.wav',
    SfxCue.registerOpen:
        'audio/sfx/checkout/sfx_checkout_register_open_v01.wav',
    SfxCue.registerClose:
        'audio/sfx/checkout/sfx_checkout_register_close_v01.wav',
  };

  static const _shopAmbience =
      'audio/ambience/ambience_shop_day_loop_v01.mp3';
  static const _openMusic = 'audio/music/music_market_open_loop_v01.mp3';
  static const _rushMusic = 'audio/music/music_market_rush_loop_v01.mp3';

  final SfxBackend _fallback;
  final Map<SfxCue, Future<AudioPool?>> _pools =
      <SfxCue, Future<AudioPool?>>{};
  AudioPlayer? _musicPlayer;
  AudioPlayer? _ambiencePlayer;
  bool _assetAudioAvailable = true;
  bool _platformAudioAvailable = false;
  bool _muted = false;
  bool _disposed = false;

  Future<AudioPool?> _preload(String path) async {
    try {
      return await AudioPool.create(
        source: AssetSource(path),
        maxPlayers: 4,
        minPlayers: 1,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> play(SfxCue cue) async {
    if (_muted || _disposed) return;
    if (!_assetAudioAvailable) {
      await _playFallback(cue);
      return;
    }
    try {
      final pool = await _pools[cue];
      if (pool == null) {
        await _playFallback(cue);
        return;
      }
      await pool.start();
    } on Object {
      await _playFallback(cue);
    }
  }

  @override
  Future<void> playAmbient(MusicPhase phase) async {
    if (_disposed) return;
    if (phase == MusicPhase.silent) {
      await stopAmbient();
      return;
    }
    if (_muted) return;
    final musicPlayer = _musicPlayer;
    final ambiencePlayer = _ambiencePlayer;
    if (!_assetAudioAvailable || musicPlayer == null || ambiencePlayer == null) {
      await _playAmbientFallback(phase);
      return;
    }

    final musicPath = phase == MusicPhase.rush ? _rushMusic : _openMusic;
    try {
      await musicPlayer.stop();
      await musicPlayer.setReleaseMode(ReleaseMode.loop);
      await musicPlayer.play(AssetSource(musicPath), volume: 0.32);
    } on Object {
      await _playAmbientFallback(phase);
      return;
    }

    try {
      if (ambiencePlayer.state != PlayerState.playing) {
        await ambiencePlayer.setReleaseMode(ReleaseMode.loop);
        await ambiencePlayer.play(
          AssetSource(_shopAmbience),
          volume: 0.12,
        );
      }
    } on Object {
      // Ambience is optional; music playback and the game continue normally.
    }
  }

  @override
  Future<void> stopAmbient() async {
    final musicPlayer = _musicPlayer;
    final ambiencePlayer = _ambiencePlayer;
    if (musicPlayer != null) await _ignoreFailure(musicPlayer.stop);
    if (ambiencePlayer != null) await _ignoreFailure(ambiencePlayer.stop);
    if (_platformAudioAvailable) {
      await _ignoreFailure(_fallback.stopAmbient);
    }
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    if (muted) {
      final musicPlayer = _musicPlayer;
      final ambiencePlayer = _ambiencePlayer;
      if (musicPlayer != null) await _ignoreFailure(musicPlayer.stop);
      if (ambiencePlayer != null) await _ignoreFailure(ambiencePlayer.stop);
    }
    if (_platformAudioAvailable) {
      await _ignoreFailure(() => _fallback.setMuted(muted));
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final futurePool in _pools.values) {
      final pool = await futurePool;
      if (pool != null) await _ignoreFailure(pool.dispose);
    }
    _pools.clear();
    final musicPlayer = _musicPlayer;
    final ambiencePlayer = _ambiencePlayer;
    _musicPlayer = null;
    _ambiencePlayer = null;
    if (musicPlayer != null) await _ignoreFailure(musicPlayer.dispose);
    if (ambiencePlayer != null) await _ignoreFailure(ambiencePlayer.dispose);
    if (_platformAudioAvailable) {
      await _ignoreFailure(_fallback.dispose);
    }
  }

  Future<void> _playFallback(SfxCue cue) async {
    if (_platformAudioAvailable) {
      await _fallback.play(cue);
    }
  }

  Future<void> _playAmbientFallback(MusicPhase phase) async {
    if (_platformAudioAvailable) {
      await _fallback.playAmbient(phase);
    }
  }

  Future<void> _ignoreFailure(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Asset audio is optional and must never interrupt simulation.
    }
  }
}
