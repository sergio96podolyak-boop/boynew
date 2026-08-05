enum SfxCue { click, success, milestone, error }

/// Describes the ambient music phase tied to the current shift state.
enum MusicPhase {
  /// Store closed / game paused — silence.
  silent,

  /// Before the shift opens — slow, calm loop.
  preparation,

  /// Normal trading hours — upbeat loop.
  open,

  /// Rush hour — fast-paced, energetic loop.
  rush,

  /// Shift winding down — gentle, fading loop.
  closing,
}

abstract interface class SfxBackend {
  Future<void> play(SfxCue cue);

  /// Start or cross-fade ambient music to [phase].
  Future<void> playAmbient(MusicPhase phase);

  /// Fade-out and stop ambient music.
  Future<void> stopAmbient();

  Future<void> setMuted(bool muted);

  Future<void> dispose();
}
