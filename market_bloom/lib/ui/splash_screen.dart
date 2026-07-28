import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Premium opening sequence for PoMarket.
///
/// [minimumDuration] controls the loading phase before the closing fade. A
/// zero duration completes on the next frame, which keeps widget tests fast
/// and deterministic.
class PoMarketSplash extends StatefulWidget {
  const PoMarketSplash({
    super.key,
    required this.onComplete,
    this.minimumDuration = const Duration(milliseconds: 2400),
    this.readiness,
  });

  final VoidCallback onComplete;
  final Duration minimumDuration;
  final Future<void>? readiness;

  @override
  State<PoMarketSplash> createState() => _PoMarketSplashState();
}

class _PoMarketSplashState extends State<PoMarketSplash>
    with TickerProviderStateMixin {
  static const _mint = Color(0xFF70E2A9);
  static const _gold = Color(0xFFFFD779);
  static const _cream = Color(0xFFFFF8E8);

  late final AnimationController _entranceController;
  late final AnimationController _progressController;
  late final Animation<double> _entranceCurve;
  late final Animation<double> _logoScale;

  bool _sequenceStarted = false;
  bool _completionDispatched = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    final sequenceDuration = widget.minimumDuration.isNegative
        ? Duration.zero
        : widget.minimumDuration;

    _entranceController = AnimationController(
      vsync: this,
      duration: _fractionOf(
        sequenceDuration,
        0.42,
        const Duration(milliseconds: 880),
      ),
    );
    _progressController = AnimationController(
      vsync: this,
      duration: sequenceDuration,
    );

    _entranceCurve = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutBack,
    );
    _logoScale = Tween<double>(begin: 0.72, end: 1).animate(_entranceCurve);
  }

  static Duration _fractionOf(
    Duration duration,
    double fraction,
    Duration maximum,
  ) {
    final scaledMicroseconds = (duration.inMicroseconds * fraction)
        .round()
        .clamp(0, maximum.inMicroseconds);
    return Duration(microseconds: scaledMicroseconds);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sequenceStarted) {
      return;
    }

    final media = MediaQuery.maybeOf(context);
    _reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    _sequenceStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_playSequence());
      }
    });
  }

  Future<void> _playSequence() async {
    if (widget.minimumDuration <= Duration.zero) {
      _entranceController.value = 1;
      _progressController.value = 1;
      await _waitUntilReady();
      // Use a microtask rather than Future.delayed to avoid leaving a
      // pending fake timer that would trip flutter_test's invariants.
      await Future<void>.value();
      if (mounted) {
        _completeOnce();
      }
      return;
    }

    if (_reduceMotion) {
      _entranceController.value = 1;
    } else {
      unawaited(_entranceController.forward());
    }

    try {
      await Future.wait<void>([
        _progressController.forward().orCancel,
        _waitUntilReady(),
      ]);
      if (!mounted) {
        return;
      }
    } on TickerCanceled {
      return;
    }

    if (mounted) {
      _completeOnce();
    }
  }

  Future<void> _waitUntilReady() async {
    final readiness = widget.readiness;
    if (readiness == null) {
      return;
    }
    try {
      await readiness;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'PoMarket startup',
          context: ErrorDescription('while preparing the game'),
        ),
      );
    }
  }

  void _completeOnce() {
    if (_completionDispatched) {
      return;
    }
    _completionDispatched = true;
    widget.onComplete();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071D18),
      body: Semantics(
        container: true,
        label: 'PoMarket opening screen. Loading game.',
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF061B17),
                    Color(0xFF0A392B),
                    Color(0xFF12613F),
                  ],
                  stops: [0, 0.58, 1],
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: _SplashAtmospherePainter(
                  animation: _progressController,
                ),
              ),
            ),
            SafeArea(
              minimum: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxHeight < 650;
                      final logoSize = math.min(
                        compact ? 124.0 : 158.0,
                        constraints.maxWidth * 0.43,
                      );

                      return Column(
                        children: [
                          _TopPill(compact: compact),
                          const Spacer(flex: 3),
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              _entranceController,
                              _progressController,
                            ]),
                            builder: (context, child) {
                              final ambientScale = _reduceMotion
                                  ? 1.0
                                  : 1 +
                                        math.sin(
                                              _progressController.value *
                                                  math.pi *
                                                  3,
                                            ) *
                                            0.012;
                              return Opacity(
                                opacity: _entranceController.value,
                                child: Transform.scale(
                                  scale: _logoScale.value * ambientScale,
                                  child: child,
                                ),
                              );
                            },
                            child: _LogoMedallion(size: logoSize),
                          ),
                          SizedBox(height: compact ? 22 : 30),
                          FadeTransition(
                            opacity: _entranceCurve,
                            child: const Column(
                              children: [
                                Text(
                                  'PoMarket',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _cream,
                                    fontSize: 44,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1.8,
                                    shadows: [
                                      Shadow(
                                        color: Color(0x80000000),
                                        offset: Offset(0, 5),
                                        blurRadius: 18,
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 13),
                                Text(
                                  'BUILD. STOCK. GROW.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _gold,
                                    fontSize: 13,
                                    height: 1.2,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 3.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(flex: 4),
                          _LoadingPanel(
                            animation: _progressController,
                            compact: compact,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopPill extends StatelessWidget {
  const _TopPill({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: compact ? 0.8 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x38FFFFFF)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _PoMarketSplashState._mint,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x8070E2A9),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: SizedBox.square(dimension: 7),
              ),
              SizedBox(width: 9),
              Text(
                'YOUR MARKET AWAITS',
                style: TextStyle(
                  color: Color(0xD9FFFFFF),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoMedallion extends StatelessWidget {
  const _LogoMedallion({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.25),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE7A8), Color(0xFFD49A37)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x6670E2A9), blurRadius: 54, spreadRadius: 8),
          BoxShadow(
            color: Color(0x6B000000),
            offset: Offset(0, 18),
            blurRadius: 28,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(math.max(3, size * 0.026)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.23),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFF103E2E)),
            child: Image.asset(
              'assets/branding/pomarket_splash_512.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: 384,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'PoMarket logo',
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel({required this.animation, required this.compact});

  final Animation<double> animation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final progress = Curves.easeInOutCubic.transform(animation.value);
        final percent = (progress * 100).round();
        return Semantics(
          label: 'Loading PoMarket',
          value: '$percent percent',
          child: ExcludeSemantics(
            child: Padding(
              padding: EdgeInsets.only(bottom: compact ? 2 : 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'OPENING YOUR STORE',
                        style: TextStyle(
                          color: Color(0xBFFFFFFF),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.35,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$percent%',
                        style: const TextStyle(
                          color: _PoMarketSplashState._cream,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Container(
                    height: 9,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: const Color(0x40000000),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: const Color(0x29FFFFFF)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _PoMarketSplashState._mint,
                                Color(0xFFB7F48A),
                                _PoMarketSplashState._gold,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x9970E2A9),
                                blurRadius: 9,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 20),
                  const Text(
                    'A POCKET-SIZED BUSINESS EMPIRE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0x73FFFFFF),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SplashAtmospherePainter extends CustomPainter {
  _SplashAtmospherePainter({required this.animation})
    : super(repaint: animation);

  final Animation<double> animation;

  static const _particles = <Offset>[
    Offset(0.08, 0.16),
    Offset(0.18, 0.34),
    Offset(0.11, 0.72),
    Offset(0.26, 0.88),
    Offset(0.38, 0.10),
    Offset(0.46, 0.79),
    Offset(0.58, 0.21),
    Offset(0.67, 0.90),
    Offset(0.74, 0.39),
    Offset(0.84, 0.12),
    Offset(0.91, 0.60),
    Offset(0.82, 0.80),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;

    final topGlow = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0x4D70E2A9), Color(0x0070E2A9)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.12, size.height * 0.08),
              radius: size.shortestSide * 0.72,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.08),
      size.shortestSide * 0.72,
      topGlow,
    );

    final goldGlow = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0x24FFD779), Color(0x00FFD779)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.94, size.height * 0.72),
              radius: size.shortestSide * 0.65,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.94, size.height * 0.72),
      size.shortestSide * 0.65,
      goldGlow,
    );

    final linePaint = Paint()
      ..color = const Color(0x0FFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final wave = Path()..moveTo(0, size.height * 0.82);
    for (var x = 0.0; x <= size.width; x += 18) {
      final y =
          size.height * 0.82 +
          math.sin((x / size.width * math.pi * 2) + (t * math.pi)) * 9;
      wave.lineTo(x, y);
    }
    canvas.drawPath(wave, linePaint);

    for (var index = 0; index < _particles.length; index++) {
      final point = _particles[index];
      final phase = t * math.pi * 2 + index * 0.83;
      final driftX = math.sin(phase) * 5;
      final driftY = math.cos(phase * 0.74) * 8;
      final center = Offset(
        point.dx * size.width + driftX,
        point.dy * size.height + driftY,
      );
      final radius = 1.3 + (index % 3) * 0.7;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = index.isEven
              ? const Color(0x6670E2A9)
              : const Color(0x52FFD779),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashAtmospherePainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}
