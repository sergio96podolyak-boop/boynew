import 'package:flutter/material.dart';

import '../theme/po_system.dart';
import 'premium_ui.dart';

/// Shared chrome for the nine management screens.
///
/// Every widget here is now a thin composition over the design system in
/// `theme/po_system.dart`. The class names and constructor signatures are
/// unchanged on purpose: the screens keep working while the visual language is
/// replaced underneath them.

/// Screen frame: page ground + floating header + centred content column.
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
  Widget build(BuildContext context) {
    final tier = PoBreak.of(context);
    return Scaffold(
      backgroundColor: PoColor.canvas,
      body: PoPageGround(
        aurora: 0.85,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _ScreenHeader(title: title, icon: icon, tier: tier),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: PoLayout.content,
                    ),
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
}

/// The header used to be a 50px slab with a decorative fake status pill. It is
/// now a proper title bar: eyebrow, screen title, and a live brand mark — the
/// same composition on every screen so navigation feels like one product.
class _ScreenHeader extends StatelessWidget {
  const _ScreenHeader({
    required this.title,
    required this.icon,
    required this.tier,
  });

  final String title;
  final IconData icon;
  final PoBreak tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFF6FAF7)],
        ),
        boxShadow: PoElevate.e1,
      ),
      child: Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: PoLayout.content),
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  tier.isCompact ? 12 : 16,
                  9,
                  tier.isCompact ? 12 : 16,
                  9,
                ),
                child: Row(
                  children: [
                    PoIconBadge(
                      icon: icon,
                      size: tier.isCompact ? 32 : 36,
                      radius: PoRadius.xs,
                    ),
                    const SizedBox(width: PoSpace.md),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tier.isCompact ? PoText.h2 : PoText.h1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // A single lit rule under the bar. Cheaper and calmer than a border,
          // and it ties the header to the brand accent on every screen.
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [
                  PoColor.primaryFace,
                  PoColor.primaryFace.withValues(alpha: 0.15),
                  PoColor.primaryFace.withValues(alpha: 0),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero panel: saturated identity band over a bright metric tray.
///
/// The old hero was a cream slab with a gradient square. Concentrating the
/// colour into one confident band and letting the metrics sit in recessed wells
/// below is the composition premium tycoon titles use, and it gives each screen
/// an immediately recognisable identity.
class ManagementHero extends StatelessWidget {
  const ManagementHero({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.metrics,
    this.colors = const [PoColor.primaryFace, PoColor.primaryDeep],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> metrics;

  /// Face/deep pair driving the band. Screens pass their own so each area of
  /// the game reads as a distinct place.
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 520;
      // Screens pass their pair in whichever order reads best in source, and
      // several pass dark-first. Sorting by luminance means the band is always
      // lit at the top and shaded at the bottom, so no screen can end up with a
      // murky, inverted gradient.
      final sorted = colors.length > 1
          ? (colors.toList()..sort(
              (a, b) => b.computeLuminance().compareTo(a.computeLuminance()),
            ))
          : colors;
      final face = sorted.first;
      final deep = sorted.length > 1 ? sorted.last : PoColor.deepen(face, 0.42);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PoRadius.lg),
          boxShadow: [
            ...PoElevate.e2,
            ...PoElevate.glow(PoColor.vivid(face), strength: 0.22),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PoRadius.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PoIdentityBand(
                icon: icon,
                title: title,
                subtitle: subtitle,
                face: face,
                deep: deep,
                compact: compact,
              ),
              if (metrics.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    compact ? 11 : 14,
                    compact ? 11 : 13,
                    compact ? 11 : 14,
                    compact ? 12 : 14,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [PoColor.surfaceLift, PoColor.surface],
                    ),
                  ),
                  child: Wrap(
                    spacing: PoSpace.sm,
                    runSpacing: PoSpace.sm,
                    children: metrics,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Hero metric: recessed well with a tiny label over a large tabular numeral.
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
  Widget build(BuildContext context) => PoStatWell(
    icon: icon,
    label: label,
    value: value,
    face: PoColor.primaryFace,
  );
}

/// Section opener: eyebrow rule, strong title, supporting line.
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
  Widget build(BuildContext context) =>
      PoSectionHead(title: title, subtitle: subtitle, trailing: trailing);
}

/// Content card.
///
/// Hierarchy is carried by elevation and an accent wash rather than by a border
/// colour: `highlighted` promotes the card to a featured surface with a rim
/// glow, `muted` demotes it to a flat locked panel. Cards therefore differ by
/// state, and the screens differ further by what they compose inside.
class ManagementCard extends StatelessWidget {
  const ManagementCard({
    super.key,
    required this.child,
    this.accent = PoColor.primaryFace,
    this.highlighted = false,
    this.muted = false,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final Color accent;
  final bool highlighted;
  final bool muted;
  final EdgeInsetsGeometry padding;

  /// Optional — gives the card press feedback when the whole card is tappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tier = PoBreak.of(context);
    final effectivePadding =
        padding == const EdgeInsets.all(16) && tier.isCompact
        ? const EdgeInsets.all(13)
        : padding;
    return PoPanel(
      kind: muted
          ? PoSurfaceKind.muted
          : highlighted
          ? PoSurfaceKind.featured
          : PoSurfaceKind.card,
      accent: accent,
      radius: tier.isCompact ? PoRadius.md : PoRadius.lg,
      padding: effectivePadding,
      onTap: onTap,
      child: child,
    );
  }
}

/// Status pill.
class ManagementStatusPill extends StatelessWidget {
  const ManagementStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.emphasise = false,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Fills the pill with the accent — use for the one state that must be read
  /// first (ready to collect, unlocked, on sale).
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final tier = PoBreak.of(context);
    return PoTag(
      label: label,
      icon: icon,
      showDot: icon == null,
      face: color,
      tone: emphasise ? PoTagTone.solid : PoTagTone.soft,
      dense: tier.isCompact,
      maxWidth: (MediaQuery.sizeOf(context).width * .44).clamp(92.0, 190.0),
    );
  }
}

/// Inline metric tile.
class ManagementInfoTile extends StatelessWidget {
  const ManagementInfoTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = PoColor.primaryFace,
    this.negative = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool negative;

  @override
  Widget build(BuildContext context) => PoStatWell(
    icon: icon,
    label: label,
    value: value,
    face: negative ? PoColor.danger : color,
    emphasis: true,
  );
}

/// Responsive column grid.
///
/// Previously one or two columns with a hard 860px switch, which produced a
/// single ~800px-wide card on a tablet and two very wide ones on a desktop —
/// the layout shrinking and stretching rather than adapting. Columns are now
/// derived from a minimum comfortable card width, so every tier gets a sensible
/// count and cards keep a readable measure.
class ManagementResponsiveWrap extends StatelessWidget {
  const ManagementResponsiveWrap({
    super.key,
    required this.children,
    this.spacing = 14,
    this.minItemWidth = 340,
    this.maxColumns = 3,
    this.twoColumnBreakpoint,
  });

  final List<Widget> children;
  final double spacing;

  /// Narrowest a card may become before dropping a column.
  final double minItemWidth;
  final int maxColumns;

  /// Legacy override kept for the call sites that tuned the old hard switch:
  /// below this width the grid stays single-column regardless of [minItemWidth].
  final double? twoColumnBreakpoint;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final gap = width < 430 ? 10.0 : spacing;
      final fits = ((width + gap) / (minItemWidth + gap)).floor();
      var columns = fits.clamp(1, maxColumns);
      if (twoColumnBreakpoint case final threshold? when width < threshold) {
        columns = 1;
      }
      final itemWidth = (width - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children)
            SizedBox(width: itemWidth, child: child),
        ],
      );
    },
  );
}

/// Row of paired label/value lines inside a card. Extracted because five
/// screens were hand-rolling the same two-column read-out.
class ManagementKeyValue extends StatelessWidget {
  const ManagementKeyValue({
    super.key,
    required this.label,
    required this.value,
    this.face,
    this.icon,
  });

  final String label;
  final String value;
  final Color? face;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        if (icon case final glyph?) ...[
          Icon(glyph, size: 13, color: PoColor.textTertiary),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PoText.label,
          ),
        ),
        const SizedBox(width: PoSpace.sm),
        Text(
          value,
          style: PoText.numeralSm.copyWith(
            color: face == null ? PoColor.ink : PoColor.deepen(face!, 0.26),
          ),
        ),
      ],
    ),
  );
}

/// Kept so screens importing this file still see the legacy palette without a
/// second import.
typedef ManagementPalette = PoMarketPalette;
