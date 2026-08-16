import 'dart:math';

import 'package:flutter/material.dart';

class CelebrationController extends ChangeNotifier {
  int _sequence = 0;

  int get sequence => _sequence;

  void celebrate() {
    _sequence++;
    notifyListeners();
  }
}

class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({
    super.key,
    required this.controller,
    required this.child,
    this.reducedMotion = false,
  });

  final CelebrationController controller;
  final Widget child;
  final bool reducedMotion;

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late List<_ConfettiParticle> _particles;

  bool get _motionDisabled =>
      widget.reducedMotion || MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    _particles = _makeParticles(widget.controller.sequence);
    widget.controller.addListener(_onCelebrate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionDisabled && _animation.isAnimating) {
      _stopAnimation();
    }
  }

  @override
  void didUpdateWidget(CelebrationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onCelebrate);
      widget.controller.addListener(_onCelebrate);
    }
    if (widget.reducedMotion && !oldWidget.reducedMotion) {
      _stopAnimation();
    }
  }

  void _stopAnimation() {
    _animation.stop();
    _animation.value = 0;
  }

  void _onCelebrate() {
    if (_motionDisabled) {
      _stopAnimation();
      return;
    }
    setState(() {
      _particles = _makeParticles(widget.controller.sequence);
    });
    _animation.forward(from: 0);
  }

  List<_ConfettiParticle> _makeParticles(int seed) {
    final random = Random(731 + seed);
    const colors = [
      Color(0xFFF6A623),
      Color(0xFF38B879),
      Color(0xFF5B8DEF),
      Color(0xFFE85D75),
      Color(0xFF8B66D8),
      Color(0xFFFFD95A),
    ];
    return List.generate(56, (index) {
      return _ConfettiParticle(
        x: random.nextDouble(),
        delay: random.nextDouble() * 0.35,
        drift: (random.nextDouble() - 0.5) * 0.36,
        spin: random.nextDouble() * pi * 5,
        size: 5 + random.nextDouble() * 7,
        color: colors[random.nextInt(colors.length)],
      );
    }, growable: false);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCelebrate);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, _) => CustomPaint(
                  painter: _ConfettiPainter(
                    progress: _animation.value,
                    particles: _particles,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfettiParticle {
  const _ConfettiParticle({
    required this.x,
    required this.delay,
    required this.drift,
    required this.spin,
    required this.size,
    required this.color,
  });

  final double x;
  final double delay;
  final double drift;
  final double spin;
  final double size;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.progress, required this.particles});

  final double progress;
  final List<_ConfettiParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final particle in particles) {
      final local = ((progress - particle.delay) / (1 - particle.delay)).clamp(
        0.0,
        1.0,
      );
      if (local <= 0 || local >= 1) {
        continue;
      }
      final eased = Curves.easeIn.transform(local);
      final x =
          particle.x * size.width +
          sin(local * pi * 3 + particle.spin) * particle.drift * size.width;
      final y = -18 + eased * (size.height + 36);
      paint.color = particle.color.withValues(alpha: 1 - local * 0.35);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(particle.spin * local);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: particle.size,
            height: particle.size * 0.55,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.particles != particles;
  }
}
