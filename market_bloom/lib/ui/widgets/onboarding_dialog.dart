import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/sfx/sfx_manager.dart';

class PoMarketOnboardingDialog extends StatefulWidget {
  const PoMarketOnboardingDialog({super.key});

  @override
  State<PoMarketOnboardingDialog> createState() =>
      _PoMarketOnboardingDialogState();
}

class _PoMarketOnboardingDialogState extends State<PoMarketOnboardingDialog> {
  static const _steps = <_TutorialStep>[
    _TutorialStep(
      icon: Icons.sports_esports_rounded,
      eyebrow: 'STEP 1 OF 3',
      title: 'Move & Collect',
      description:
          'Drag the joystick with your thumb. Walk to STORAGE and products will load into your bag automatically.',
      color: Color(0xFF5B8DEF),
    ),
    _TutorialStep(
      icon: Icons.shelves,
      eyebrow: 'STEP 2 OF 3',
      title: 'Keep Shelves Full',
      description:
          'Carry products to the SHELF. Customers can only shop while products are available.',
      color: Color(0xFFF6A623),
    ),
    _TutorialStep(
      icon: Icons.trending_up_rounded,
      eyebrow: 'STEP 3 OF 3',
      title: 'Sell, Earn & Grow',
      description:
          'Customers pay at CHECKOUT. Use your coins for upgrades, climb the leaderboard, and build your store empire.',
      color: Color(0xFF38B879),
    ),
  ];

  final PageController _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    unawaited(SfxManager.instance.click());
    if (_index == _steps.length - 1) {
      Navigator.of(context).pop(true);
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 700 || size.width < 430;
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Container(
            padding: EdgeInsets.fromLTRB(20, compact ? 18 : 24, 20, 18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF6),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44315F4A),
                  blurRadius: 30,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF315F4A),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WELCOME TO POMARKET',
                            style: TextStyle(
                              color: Color(0xFF315F4A),
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                          Text(
                            'Your store opens in three quick steps',
                            style: TextStyle(
                              color: Color(0xFF747A75),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 13 : 20),
                SizedBox(
                  height: compact ? 245 : 265,
                  child: PageView.builder(
                    controller: _pages,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _steps.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder: (context, index) =>
                        _TutorialPage(step: _steps[index], compact: compact),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _steps.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: index == _index ? 24 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: index == _index
                            ? _steps[_index].color
                            : const Color(0xFFD7D5CE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                FilledButton.icon(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: _steps[_index].color,
                  ),
                  icon: Icon(
                    _index == _steps.length - 1
                        ? Icons.play_arrow_rounded
                        : Icons.arrow_forward_rounded,
                  ),
                  label: Text(
                    _index == _steps.length - 1
                        ? 'START PLAYING'
                        : 'GOT IT — NEXT',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TutorialPage extends StatelessWidget {
  const _TutorialPage({required this.step, required this.compact});

  final _TutorialStep step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: compact ? 78 : 98,
          height: compact ? 78 : 98,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [step.color.withValues(alpha: 0.72), step.color],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: step.color.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Icon(step.icon, size: compact ? 39 : 49, color: Colors.white),
        ),
        SizedBox(height: compact ? 10 : 15),
        Text(
          step.eyebrow,
          style: TextStyle(
            color: step.color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          step.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: step.color,
            fontSize: compact ? 22 : 25,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Text(
                step.description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF606862),
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TutorialStep {
  const _TutorialStep({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final Color color;
}
