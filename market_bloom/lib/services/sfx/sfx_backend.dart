enum SfxCue {
  click,
  success,
  milestone,
  error,
  pickup,
  restock,
  checkoutScan,
  sale,
  customerWarning,
  customerLeave,
  deliveryArrived,
  bakeryReady,
  registerOpen,
  registerClose,
}

/// Maps semantic gameplay cues to the original four fail-safe sound families.
extension SfxCueFallback on SfxCue {
  SfxCue get fallback => switch (this) {
    SfxCue.pickup ||
    SfxCue.checkoutScan ||
    SfxCue.registerClose => SfxCue.click,
    SfxCue.restock ||
    SfxCue.sale ||
    SfxCue.bakeryReady ||
    SfxCue.registerOpen => SfxCue.success,
    SfxCue.deliveryArrived => SfxCue.milestone,
    SfxCue.customerWarning ||
    SfxCue.customerLeave => SfxCue.error,
    _ => this,
  };
}

/// Describes the ambient music phase tied to the current shift state.
enum MusicPhase {
  silent,
  preparation,
  open,
  rush,
  closing,
}

abstract interface class SfxBackend {
  Future<void> play(SfxCue cue);

  Future<void> playAmbient(MusicPhase phase);

  Future<void> stopAmbient();

  Future<void> setMuted(bool muted);

  Future<void> dispose();
}
