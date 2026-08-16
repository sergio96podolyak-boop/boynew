import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/services/sfx/asset_sfx_backend.dart';
import 'package:pomarket/services/sfx/sfx_backend.dart';

void main() {
  test('audio stays a no-op when Flutter services are not initialized', () async {
    final fallback = _RecordingBackend();
    final backend = AssetSfxBackend(fallback);

    await backend.play(SfxCue.sale);
    await backend.playAmbient(MusicPhase.open);
    await backend.stopAmbient();
    await backend.setMuted(true);
    await backend.setMuted(false);
    await backend.dispose();

    expect(fallback.cues, isEmpty);
    expect(fallback.ambientPhases, isEmpty);
    expect(fallback.stopCalls, 0);
    expect(fallback.muteValues, isEmpty);
    expect(fallback.disposeCalls, 0);
  });
}

class _RecordingBackend implements SfxBackend {
  final List<SfxCue> cues = <SfxCue>[];
  final List<MusicPhase> ambientPhases = <MusicPhase>[];
  final List<bool> muteValues = <bool>[];
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> play(SfxCue cue) async => cues.add(cue);

  @override
  Future<void> playAmbient(MusicPhase phase) async {
    ambientPhases.add(phase);
  }

  @override
  Future<void> stopAmbient() async => stopCalls++;

  @override
  Future<void> setMuted(bool muted) async => muteValues.add(muted);

  @override
  Future<void> dispose() async => disposeCalls++;
}
