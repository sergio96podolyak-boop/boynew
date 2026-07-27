enum SfxCue { click, success, milestone, error }

abstract interface class SfxBackend {
  Future<void> play(SfxCue cue);

  Future<void> setMuted(bool muted);

  Future<void> dispose();
}
