@JS()
library;

import 'dart:async';
import 'dart:js_interop';

import 'sfx_backend.dart';

SfxBackend createSfxBackend() => _WebAudioSfxBackend();

final class _WebAudioSfxBackend implements SfxBackend {
  static const int _maxVoices = 12;

  _AudioContext? _context;
  final List<_ActiveVoice> _voices = <_ActiveVoice>[];
  bool _muted = false;
  bool _disposed = false;

  @override
  Future<void> play(SfxCue cue) async {
    if (_muted || _disposed) {
      return;
    }

    final context = _context ??= _AudioContext();

    // Browsers normally create a suspended context before the first gesture.
    // Every public cue can be called directly from a tap, so resume here rather
    // than during app startup and stay within autoplay policies.
    if (context.state == 'suspended') {
      await context.resume().toDart;
    }
    if (_muted || _disposed || context.state == 'closed') {
      return;
    }

    final now = context.currentTime;
    switch (cue) {
      case SfxCue.click:
        _scheduleTone(
          context,
          startsAt: now,
          frequency: 620,
          endingFrequency: 760,
          duration: 0.055,
          gain: 0.026,
          wave: 'sine',
        );
      case SfxCue.success:
        _scheduleTone(
          context,
          startsAt: now,
          frequency: 523.25,
          endingFrequency: 587.33,
          duration: 0.105,
          gain: 0.032,
          wave: 'sine',
        );
        _scheduleTone(
          context,
          startsAt: now + 0.075,
          frequency: 659.25,
          endingFrequency: 783.99,
          duration: 0.15,
          gain: 0.034,
          wave: 'triangle',
        );
      case SfxCue.milestone:
        for (final (index, note) in <double>[
          523.25,
          659.25,
          783.99,
          1046.50,
        ].indexed) {
          _scheduleTone(
            context,
            startsAt: now + (index * 0.065),
            frequency: note,
            endingFrequency: note * 1.035,
            duration: 0.19,
            gain: index == 3 ? 0.043 : 0.034,
            wave: index.isEven ? 'sine' : 'triangle',
          );
        }
      case SfxCue.error:
        _scheduleTone(
          context,
          startsAt: now,
          frequency: 230,
          endingFrequency: 145,
          duration: 0.16,
          gain: 0.028,
          wave: 'triangle',
        );
    }
  }

  void _scheduleTone(
    _AudioContext context, {
    required double startsAt,
    required double frequency,
    required double endingFrequency,
    required double duration,
    required double gain,
    required String wave,
  }) {
    if (_voices.length >= _maxVoices) {
      _voices.removeAt(0).release();
    }

    final oscillator = context.createOscillator();
    final gainNode = context.createGain();
    final frequencyParam = oscillator.frequency;
    final gainParam = gainNode.gain;
    final endsAt = startsAt + duration;

    oscillator.type = wave;
    frequencyParam
      ..setValueAtTime(frequency, startsAt)
      ..exponentialRampToValueAtTime(endingFrequency, endsAt);
    gainParam
      ..setValueAtTime(0.0001, startsAt)
      ..linearRampToValueAtTime(gain, startsAt + 0.008)
      ..exponentialRampToValueAtTime(0.0001, endsAt);

    oscillator.connect(gainNode);
    gainNode.connect(context.destination);
    oscillator
      ..start(startsAt)
      ..stop(endsAt + 0.012);

    late final _ActiveVoice voice;
    voice = _ActiveVoice(
      oscillator: oscillator,
      gainNode: gainNode,
      releaseTimer: Timer(
        Duration(
          milliseconds: ((endsAt - context.currentTime + 0.08) * 1000)
              .ceil()
              .clamp(1, 1000),
        ),
        () {
          voice.release();
          _voices.remove(voice);
        },
      ),
    );
    _voices.add(voice);
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    if (!muted) {
      return;
    }

    _releaseVoices();
    final context = _context;
    if (context != null && context.state == 'running') {
      await context.suspend().toDart;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _releaseVoices();

    final context = _context;
    _context = null;
    if (context != null && context.state != 'closed') {
      await context.close().toDart;
    }
  }

  void _releaseVoices() {
    for (final voice in List<_ActiveVoice>.of(_voices)) {
      voice.release();
    }
    _voices.clear();
  }
}

final class _ActiveVoice {
  _ActiveVoice({
    required this.oscillator,
    required this.gainNode,
    required this.releaseTimer,
  });

  final _OscillatorNode oscillator;
  final _GainNode gainNode;
  final Timer releaseTimer;
  bool _released = false;

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    releaseTimer.cancel();
    try {
      oscillator.stop();
    } on Object {
      // A scheduled source may already be stopped; disconnection is enough.
    }
    try {
      oscillator.disconnect();
      gainNode.disconnect();
    } on Object {
      // Closing an AudioContext can disconnect nodes before this callback.
    }
  }
}

@JS('AudioContext')
extension type _AudioContext._(JSObject _) implements JSObject {
  external factory _AudioContext();

  external double get currentTime;
  external String get state;
  external _AudioDestinationNode get destination;
  external _OscillatorNode createOscillator();
  external _GainNode createGain();
  external JSPromise<JSAny?> resume();
  external JSPromise<JSAny?> suspend();
  external JSPromise<JSAny?> close();
}

extension type _AudioDestinationNode._(JSObject _) implements JSObject {}

extension type _AudioNode._(JSObject _) implements JSObject {
  external JSAny? connect(JSObject destination);
  external void disconnect();
}

extension type _OscillatorNode._(JSObject _) implements _AudioNode, JSObject {
  external _AudioParam get frequency;
  external set type(String value);
  external void start([double when]);
  external void stop([double when]);
}

extension type _GainNode._(JSObject _) implements _AudioNode, JSObject {
  external _AudioParam get gain;
}

extension type _AudioParam._(JSObject _) implements JSObject {
  external _AudioParam setValueAtTime(num value, num startTime);
  external _AudioParam linearRampToValueAtTime(num value, num endTime);
  external _AudioParam exponentialRampToValueAtTime(num value, num endTime);
}
