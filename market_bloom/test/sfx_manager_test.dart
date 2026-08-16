import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/services/sfx/sfx_backend.dart';
import 'package:pomarket/services/sfx/sfx_manager.dart';

void main() {
  test('mute suppresses cues and unmute restores playback', () async {
    final backend = _RecordingBackend();
    final manager = SfxManager.forTesting(backend);

    await manager.click();
    await manager.setMuted(true);
    await manager.sale();
    expect(manager.isMuted, isTrue);
    expect(backend.cues, <SfxCue>[SfxCue.click]);
    expect(backend.muteValues, <bool>[true]);

    await manager.setMuted(false, playFeedback: false);
    await manager.sale();
    expect(manager.isMuted, isFalse);
    expect(backend.cues, <SfxCue>[SfxCue.click, SfxCue.sale]);
    expect(backend.muteValues, <bool>[true, false]);
  });

  test('toggle mute and unmute feedback use the regular click path', () async {
    var now = DateTime(2026, 1, 1);
    final backend = _RecordingBackend();
    final manager = SfxManager.forTesting(backend, now: () => now);

    await manager.toggleMuted();
    expect(manager.isMuted, isTrue);
    await manager.toggleMuted();
    await manager.click();
    now = now.add(const Duration(milliseconds: 35));
    await manager.click();

    expect(manager.isMuted, isFalse);
    expect(backend.cues, <SfxCue>[SfxCue.click, SfxCue.click]);
    expect(backend.muteValues, <bool>[true, false]);
  });

  test('every semantic cue has a public playback path', () async {
    final backend = _RecordingBackend();
    final manager = SfxManager.forTesting(backend);

    await manager.click();
    await manager.success();
    await manager.milestone();
    await manager.error();
    await manager.pickup();
    await manager.restock();
    await manager.checkoutScan();
    await manager.sale();
    await manager.customerWarning();
    await manager.customerLeave();
    await manager.deliveryArrived();
    await manager.bakeryReady();
    await manager.registerOpen();
    await manager.registerClose();

    expect(backend.cues, SfxCue.values);
  });

  test('cue throttling suppresses spam and allows the boundary', () async {
    var now = DateTime(2026, 1, 1);
    final backend = _RecordingBackend();
    final manager = SfxManager.forTesting(backend, now: () => now);

    await manager.checkoutScan();
    await manager.checkoutScan();
    now = now.add(const Duration(milliseconds: 34));
    await manager.checkoutScan();
    now = now.add(const Duration(milliseconds: 1));
    await manager.checkoutScan();

    await manager.restock();
    now = now.add(const Duration(milliseconds: 119));
    await manager.restock();
    now = now.add(const Duration(milliseconds: 1));
    await manager.restock();

    expect(
      backend.cues,
      <SfxCue>[
        SfxCue.checkoutScan,
        SfxCue.checkoutScan,
        SfxCue.restock,
        SfxCue.restock,
      ],
    );
  });

  test('throttling is tracked independently for each cue', () async {
    var now = DateTime(2026, 1, 1);
    final backend = _RecordingBackend();
    final manager = SfxManager.forTesting(backend, now: () => now);

    await manager.customerWarning();
    await manager.customerWarning();
    await manager.customerLeave();
    await manager.error();
    now = now.add(const Duration(milliseconds: 900));
    await manager.customerWarning();

    expect(backend.cues, <SfxCue>[
      SfxCue.customerWarning,
      SfxCue.customerLeave,
      SfxCue.error,
      SfxCue.customerWarning,
    ]);
  });

  test('ambient phase resumes after unmute and stop clears it', () async {
    final backend = _RecordingBackend();
    final manager = SfxManager.forTesting(backend);

    await manager.playAmbient(MusicPhase.open);
    expect(manager.ambientPhase, MusicPhase.open);
    await manager.setMuted(true);
    await manager.setMuted(false, playFeedback: false);
    await manager.stopAmbient();

    expect(
      backend.ambientPhases,
      <MusicPhase>[MusicPhase.open, MusicPhase.open],
    );
    expect(manager.ambientPhase, MusicPhase.silent);
    expect(backend.stopCalls, 1);
  });

  test('latest ambient phase selected while muted resumes on unmute', () async {
    final backend = _RecordingBackend();
    final manager = SfxManager.forTesting(backend);

    await manager.setMuted(true);
    await manager.playAmbient(MusicPhase.preparation);
    await manager.playAmbient(MusicPhase.rush);
    expect(manager.ambientPhase, MusicPhase.rush);
    await manager.setMuted(false, playFeedback: false);

    expect(backend.ambientPhases, <MusicPhase>[MusicPhase.rush]);
  });

  test('stop while muted clears the phase and prevents later resume', () async {
    final backend = _RecordingBackend();
    final manager = SfxManager.forTesting(backend);

    await manager.playAmbient(MusicPhase.open);
    await manager.setMuted(true);
    await manager.stopAmbient();
    await manager.setMuted(false, playFeedback: false);

    expect(manager.ambientPhase, MusicPhase.silent);
    expect(backend.ambientPhases, <MusicPhase>[MusicPhase.open]);
    expect(backend.stopCalls, 1);
  });

  test('dispose is idempotent and blocks state and backend operations', () async {
    final backend = _RecordingBackend();
    final manager = SfxManager.forTesting(backend);

    await manager.playAmbient(MusicPhase.open);
    await manager.dispose();
    await manager.dispose();
    await manager.click();
    await manager.playAmbient(MusicPhase.rush);
    await manager.stopAmbient();
    await manager.setMuted(true);

    expect(manager.isDisposed, isTrue);
    expect(manager.isMuted, isFalse);
    expect(manager.ambientPhase, MusicPhase.silent);
    expect(backend.disposeCalls, 1);
    expect(backend.cues, isEmpty);
    expect(backend.ambientPhases, <MusicPhase>[MusicPhase.open]);
    expect(backend.stopCalls, 0);
    expect(backend.muteValues, isEmpty);
  });

  test('playback failure is contained and disables later SFX calls', () async {
    final backend = _RecordingBackend()..failure = _Failure.play;
    final manager = SfxManager.forTesting(backend);

    await expectLater(manager.sale(), completes);
    await expectLater(manager.customerLeave(), completes);

    expect(backend.playAttempts, 1);
  });

  test('ambient, mute, stop, and dispose backend failures are contained', () async {
    for (final failure in <_Failure>[
      _Failure.ambient,
      _Failure.mute,
      _Failure.stop,
      _Failure.dispose,
    ]) {
      final backend = _RecordingBackend()..failure = failure;
      final manager = SfxManager.forTesting(backend);

      final operation = switch (failure) {
        _Failure.ambient => manager.playAmbient(MusicPhase.open),
        _Failure.mute => manager.setMuted(true),
        _Failure.stop => manager.stopAmbient(),
        _Failure.dispose => manager.dispose(),
        _Failure.play => throw StateError('covered separately'),
      };
      await expectLater(operation, completes, reason: failure.name);
    }
  });

  test('all semantic cues retain an original fallback family', () {
    expect(SfxCue.pickup.fallback, SfxCue.click);
    expect(SfxCue.restock.fallback, SfxCue.success);
    expect(SfxCue.checkoutScan.fallback, SfxCue.click);
    expect(SfxCue.sale.fallback, SfxCue.success);
    expect(SfxCue.customerWarning.fallback, SfxCue.error);
    expect(SfxCue.customerLeave.fallback, SfxCue.error);
    expect(SfxCue.deliveryArrived.fallback, SfxCue.milestone);
    expect(SfxCue.bakeryReady.fallback, SfxCue.success);
    expect(SfxCue.registerOpen.fallback, SfxCue.success);
    expect(SfxCue.registerClose.fallback, SfxCue.click);
  });
}

enum _Failure { play, ambient, mute, stop, dispose }

class _RecordingBackend implements SfxBackend {
  final List<SfxCue> cues = <SfxCue>[];
  final List<MusicPhase> ambientPhases = <MusicPhase>[];
  final List<bool> muteValues = <bool>[];
  _Failure? failure;
  int playAttempts = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  void _throwIf(_Failure operation) {
    if (failure == operation) {
      throw StateError('simulated ${operation.name} failure');
    }
  }

  @override
  Future<void> play(SfxCue cue) async {
    playAttempts++;
    _throwIf(_Failure.play);
    cues.add(cue);
  }

  @override
  Future<void> playAmbient(MusicPhase phase) async {
    _throwIf(_Failure.ambient);
    ambientPhases.add(phase);
  }

  @override
  Future<void> stopAmbient() async {
    _throwIf(_Failure.stop);
    stopCalls++;
  }

  @override
  Future<void> setMuted(bool muted) async {
    _throwIf(_Failure.mute);
    muteValues.add(muted);
  }

  @override
  Future<void> dispose() async {
    _throwIf(_Failure.dispose);
    disposeCalls++;
  }
}
