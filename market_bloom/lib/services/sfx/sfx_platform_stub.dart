import 'sfx_backend.dart';

SfxBackend createSfxBackend() => _SilentSfxBackend();

final class _SilentSfxBackend implements SfxBackend {
  @override
  Future<void> play(SfxCue cue) async {}

  @override
  Future<void> playAmbient(MusicPhase phase) async {}

  @override
  Future<void> stopAmbient() async {}

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> dispose() async {}
}
