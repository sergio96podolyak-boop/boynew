// ignore_for_file: use_null_aware_elements
import 'package:flutter/material.dart';

import '../theme/pomarket_design.dart';
import 'premium_ui.dart';

class ManagementScaffold extends StatelessWidget {
  const ManagementScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: PoDepthColors.deepSea,
    // Same deep field as the market and the shell, so cream cards float the
    // same way on every screen instead of each area having its own ground.
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PoDepthColors.forest, PoDepthColors.deepSea],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              height: 50,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: [Color(0xFF0A4937), Color(0xFF073326)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x2A052E23),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  PositionedDirectional(
                    end: -20,
                    top: -28,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .035),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [PoMarketPalette.mint, Color(0xFF27B77D)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x3345D39A),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            icon,
                            color: PoMarketPalette.forest,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .1,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: PoMarketPalette.mint.withValues(alpha: .22),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StatusDot(color: PoMarketPalette.mint, size: 6),
                              SizedBox(width: 5),
                              Text(
                                'POMARKET',
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  color: Color(0xFFC8E3D7),
                                  fontSize: 7,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .7,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ManagementHero extends StatelessWidget {
  const ManagementHero({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.metrics,
    this.colors = const [Color(0xFF0B4B38), Color(0xFF16805C)],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> metrics;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 520;
      return Container(
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF2),
          borderRadius: BorderRadius.circular(compact ? 20 : 24),
          border: Border.all(color: colors.last.withValues(alpha: .22)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A173D35),
              blurRadius: 16,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: compact ? 47 : 55,
                  height: compact ? 47 : 55,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: colors),
                    borderRadius: BorderRadius.circular(compact ? 15 : 18),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: compact ? 25 : 29,
                  ),
                ),
                SizedBox(width: compact ? 11 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: PoMarketPalette.ink,
                          fontSize: compact ? 18 : 22,
                          height: 1.06,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PoMarketPalette.muted,
                          fontSize: 10,
                          height: 1.28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Wrap(spacing: 8, runSpacing: 8, children: metrics),
          ],
        ),
      );
    },
  );
}

class ManagementHeroMetric extends StatelessWidget {
  const ManagementHeroMetric({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(
      minWidth: 96,
      maxWidth: 168,
      minHeight: 46,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F7F1),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: PoMarketPalette.line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: PoMarketPalette.forestLight, size: 15),
        const SizedBox(width: 5),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PoMarketPalette.muted,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PoMarketPalette.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ManagementSectionTitle extends StatelessWidget {
  const ManagementSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Row(
      children: [
        Container(
          width: 5,
          height: subtitle == null ? 25 : 38,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [PoAccent.mintFace, PoAccent.mintDeep],
            ),
            borderRadius: BorderRadius.circular(9),
            boxShadow: PoDepth.glow(PoAccent.mintFace, strength: 0.5),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Section titles sit directly on the page's deep backdrop rather
              // than inside a card, so they carry light type.
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 16 : 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontSize: 10,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

class ManagementCard extends StatelessWidget {
  const ManagementCard({
    super.key,
    required this.child,
    this.accent = PoMarketPalette.forest,
    this.highlighted = false,
    this.muted = false,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final Color accent;
  final bool highlighted;
  final bool muted;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    final effectivePadding = padding == const EdgeInsets.all(16) && compact
        ? const EdgeInsets.all(13)
        : padding;
    return Container(
      padding: effectivePadding,
      decoration: BoxDecoration(
        color: muted ? const Color(0xFFF1F0EA) : const Color(0xFFFFFCF5),
        borderRadius: BorderRadius.circular(compact ? 17 : 21),
        border: Border.all(
          color: highlighted
              ? accent.withValues(alpha: .38)
              : PoMarketPalette.line,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: highlighted
                ? accent.withValues(alpha: .09)
                : const Color(0x16063D2C),
            blurRadius: highlighted ? 13 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class ManagementStatusPill extends StatelessWidget {
  const ManagementStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Container(
      constraints: BoxConstraints(
        minHeight: compact ? 25 : 29,
        maxWidth: (MediaQuery.sizeOf(context).width * .42).clamp(88, 180),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.circle, color: color, size: compact ? 12 : 14),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: compact ? 8 : 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ManagementInfoTile extends StatelessWidget {
  const ManagementInfoTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = PoMarketPalette.forest,
    this.negative = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = negative ? PoMarketPalette.coral : color;
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Container(
      constraints: BoxConstraints(
        minWidth: compact ? 88 : 105,
        minHeight: compact ? 43 : 50,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 6 : 7,
      ),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: effectiveColor.withValues(alpha: .13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: effectiveColor, size: compact ? 14 : 16),
          const SizedBox(width: 5),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: PoMarketPalette.muted,
                    fontSize: compact ? 7 : 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: effectiveColor,
                    fontSize: compact ? 11 : 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ManagementResponsiveWrap extends StatelessWidget {
  const ManagementResponsiveWrap({
    super.key,
    required this.children,
    this.spacing = 14,
    this.twoColumnBreakpoint = 860,
  });
  final List<Widget> children;
  final double spacing;
  final double twoColumnBreakpoint;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= twoColumnBreakpoint ? 2 : 1;
      final gap = constraints.maxWidth < 430 ? 9.0 : spacing;
      final width = columns == 2
          ? (constraints.maxWidth - gap) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}
