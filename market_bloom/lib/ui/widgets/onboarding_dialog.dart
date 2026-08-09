import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/app_localizations.dart';
import '../../services/sfx/sfx_manager.dart';

class PoMarketOnboardingDialog extends StatefulWidget {
  const PoMarketOnboardingDialog({super.key});

  @override
  State<PoMarketOnboardingDialog> createState() =>
      _PoMarketOnboardingDialogState();
}

class _PoMarketOnboardingDialogState extends State<PoMarketOnboardingDialog> {
  static const _stepCount = 3;

  final PageController _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    unawaited(SfxManager.instance.click());
    if (_index == _stepCount - 1) {
      Navigator.of(context).pop(true);
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  void _skip() {
    unawaited(SfxManager.instance.click());
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final steps = <_TutorialStep>[
      _TutorialStep(
        icon: Icons.touch_app_rounded,
        eyebrow: loc.tutorialStep
            .replaceFirst('{current}', '1')
            .replaceFirst('{total}', '$_stepCount'),
        title: loc.moveAndCollect,
        description: loc.moveAndCollectDesc,
        color: const Color(0xFF5B8DEF),
      ),
      _TutorialStep(
        icon: Icons.shelves,
        eyebrow: loc.tutorialStep
            .replaceFirst('{current}', '2')
            .replaceFirst('{total}', '$_stepCount'),
        title: loc.keepShelvesFull,
        description: loc.keepShelvesFullDesc,
        color: const Color(0xFFF6A623),
      ),
      _TutorialStep(
        icon: Icons.trending_up_rounded,
        eyebrow: loc.tutorialStep
            .replaceFirst('{current}', '3')
            .replaceFirst('{total}', '$_stepCount'),
        title: loc.sellEarnGrow,
        description: loc.sellEarnGrowDesc,
        color: const Color(0xFF38B879),
      ),
    ];
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc.welcomeToPoMarket,
                            style: const TextStyle(
                              color: Color(0xFF315F4A),
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                          Text(
                            loc.tutorialSubtitle,
                            style: const TextStyle(
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
                    itemCount: steps.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder: (context, index) =>
                        _TutorialPage(step: steps[index], compact: compact),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    steps.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: index == _index ? 24 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: index == _index
                            ? steps[_index].color
                            : const Color(0xFFD7D5CE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    TextButton(
                      onPressed: _skip,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 54),
                      ),
                      child: Text(loc.skip),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: steps[_index].color,
                        ),
                        icon: Icon(
                          _index == steps.length - 1
                              ? Icons.play_arrow_rounded
                              : Icons.arrow_forward_rounded,
                        ),
                        label: Text(
                          _index == steps.length - 1
                              ? loc.startPlaying
                              : loc.gotItNext,
                        ),
                      ),
                    ),
                  ],
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
