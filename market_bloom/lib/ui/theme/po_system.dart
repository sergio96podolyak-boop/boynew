import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PoMarket design system.
///
/// This file is the single source of truth for colour, type, spacing, radius,
/// elevation and the primitive widgets every screen is assembled from. It
/// replaces the two overlapping vocabularies the project grew organically —
/// `PoMarketPalette` (cream/forest) and `PoDepthColors` (depth ramp) — both of
/// which are now thin aliases onto the roles defined here.
///
/// Design intent: a bright, layered "premium tycoon" interface. Surfaces are
/// near-white and carry the hierarchy through *elevation and grouping*, not
/// borders; saturated colour is reserved for identity bands, currency, and
/// primary actions so that the eye is always pulled to the thing that matters.
/// Nothing is a 1px-bordered rectangle.

// ---------------------------------------------------------------------------
// Colour
// ---------------------------------------------------------------------------

/// Semantic colour roles.
///
/// Every colour in the app resolves to one of these. Accents come in
/// face/deep pairs so any element can be extruded (lit top, shaded bottom)
/// from a single token.
abstract final class PoColor {
  // -- Ink ramp. Cool deep green so text feels part of the brand, not black.
  /// Primary text, icons on light surfaces.
  static const ink = Color(0xFF0B1F1A);

  /// Headings that sit on tinted surfaces.
  static const inkSoft = Color(0xFF1C3A32);

  /// Secondary text: descriptions, supporting copy.
  static const textSecondary = Color(0xFF4A6E63);

  /// Tertiary text: captions, meta, timestamps.
  static const textTertiary = Color(0xFF7D998F);

  /// Disabled text and icons.
  static const textDisabled = Color(0xFF9DB2AA);

  // -- Ground and surfaces. Four steps is enough to build real depth.
  /// Deepest page ground; the bottom of every page gradient.
  static const canvasDeep = Color(0xFFDCE7E1);

  /// Page ground.
  static const canvas = Color(0xFFE9F0EB);

  /// Default card / panel.
  static const surface = Color(0xFFFFFFFF);

  /// Card top stop, for the faint vertical lift on every panel.
  static const surfaceLift = Color(0xFFFCFEFC);

  /// Recessed wells: stat tiles, tracks, list rows inside a card.
  static const surfaceSunken = Color(0xFFE8EFEA);

  /// Unavailable / locked content.
  static const surfaceMuted = Color(0xFFEFF2EF);

  /// Chrome behind the HUD and dock.
  static const chrome = Color(0xFFFFFFFF);

  /// Hairline used only where a true edge is needed (dividers, insets).
  static const hairline = Color(0x140B1F1A);
  static const hairlineStrong = Color(0x240B1F1A);

  // -- Accent pairs. `face` is the lit body, `deep` the shaded edge.
  static const primaryFace = Color(0xFF2FD98F);
  static const primaryDeep = Color(0xFF0A8B59);
  static const primaryInk = Color(0xFF043222);

  static const secondaryFace = Color(0xFF3FCCC4);
  static const secondaryDeep = Color(0xFF0C837E);

  static const accentFace = Color(0xFFAB8DFF);
  static const accentDeep = Color(0xFF6234E0);

  static const goldFace = Color(0xFFFFCB45);
  static const goldDeep = Color(0xFFD98505);

  static const infoFace = Color(0xFF62B4FF);
  static const infoDeep = Color(0xFF1D6FD4);

  // -- Status. Single hue each; pair with [deepen]/[lighten] when extruding.
  static const success = Color(0xFF1FC178);
  static const warning = Color(0xFFF59A0B);
  static const danger = Color(0xFFEE4664);
  static const neutral = Color(0xFF6D8A80);

  /// Darker companion used for bevels, button edges and pressed states.
  static Color deepen(Color face, [double amount = 0.32]) =>
      Color.lerp(face, const Color(0xFF04120E), amount)!;

  /// Lighter companion used for top highlights and gradient tops.
  static Color lighten(Color face, [double amount = 0.40]) =>
      Color.lerp(face, Colors.white, amount)!;

  /// A legible foreground for content sitting directly on [face].
  ///
  /// Candy-bright accents (mint, gold) need dark ink; saturated deeps need
  /// white. Measuring luminance means new accents work without a lookup table.
  static Color onFace(Color face) =>
      face.computeLuminance() > 0.48 ? ink : Colors.white;

  /// A very light tint of [face], for wash backgrounds inside panels.
  static Color wash(Color face, [double alpha = 0.10]) =>
      face.withValues(alpha: alpha);

  /// Forces [seed] to a vivid, well-lit version of its own hue.
  ///
  /// Several screens hand the hero their palette as a pair of very dark greens
  /// and teals — fine when the colour only filled a 50px icon, murky when it
  /// fills a full-width identity band. Normalising saturation and lightness
  /// keeps each area's hue identity while guaranteeing the band is actually
  /// colourful.
  static Color vivid(
    Color seed, {
    double lightness = 0.52,
    double minSaturation = 0.58,
  }) {
    final hsl = HSLColor.fromColor(seed);
    return hsl
        .withSaturation(math.max(hsl.saturation, minSaturation).clamp(0.0, 1.0))
        .withLightness(lightness.clamp(0.0, 1.0))
        .toColor();
  }
}

// ---------------------------------------------------------------------------
// Type
// ---------------------------------------------------------------------------

/// Typographic scale.
///
/// Named roles only — no screen should invent a font size. Numerals use
/// tabular figures so ticking counters do not jitter, and negative tracking on
/// the large sizes is what gives headings their "designed" feel.
abstract final class PoText {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Screen-defining number (shift takings, prestige total).
  static const displayXl = TextStyle(
    fontSize: 32,
    height: 1.0,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.1,
    color: PoColor.ink,
    fontFeatures: _tabular,
  );

  /// Hero titles.
  static const display = TextStyle(
    fontSize: 25,
    height: 1.05,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.7,
    color: PoColor.ink,
  );

  /// Screen title.
  static const h1 = TextStyle(
    fontSize: 20,
    height: 1.1,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.4,
    color: PoColor.ink,
  );

  /// Section title.
  static const h2 = TextStyle(
    fontSize: 17,
    height: 1.15,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.25,
    color: PoColor.ink,
  );

  /// Card title.
  static const h3 = TextStyle(
    fontSize: 14.5,
    height: 1.2,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.1,
    color: PoColor.ink,
  );

  /// Emphasised row label.
  static const title = TextStyle(
    fontSize: 13,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: PoColor.ink,
  );

  /// Reading copy.
  static const body = TextStyle(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: PoColor.textSecondary,
  );

  /// Dense reading copy inside cards.
  static const bodySm = TextStyle(
    fontSize: 11,
    height: 1.38,
    fontWeight: FontWeight.w600,
    color: PoColor.textSecondary,
  );

  /// Field / metric label.
  static const label = TextStyle(
    fontSize: 10.5,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.1,
    color: PoColor.textSecondary,
  );

  /// Meta text: counts, hints, timestamps.
  static const caption = TextStyle(
    fontSize: 9.5,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    color: PoColor.textTertiary,
  );

  /// All-caps eyebrow above a title. Wide tracking is doing the work here.
  static const overline = TextStyle(
    fontSize: 9,
    height: 1.1,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.0,
    color: PoColor.textTertiary,
  );

  /// Large readout (hero metric).
  static const numeralLg = TextStyle(
    fontSize: 22,
    height: 1.0,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.6,
    color: PoColor.ink,
    fontFeatures: _tabular,
  );

  /// Standard readout (HUD, stat tile).
  static const numeral = TextStyle(
    fontSize: 16,
    height: 1.0,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.35,
    color: PoColor.ink,
    fontFeatures: _tabular,
  );

  /// Compact readout (chips, inline costs).
  static const numeralSm = TextStyle(
    fontSize: 12.5,
    height: 1.0,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.2,
    color: PoColor.ink,
    fontFeatures: _tabular,
  );

  /// Button label.
  static const button = TextStyle(
    fontSize: 13.5,
    height: 1.1,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.2,
  );

  /// Compact button label.
  static const buttonSm = TextStyle(
    fontSize: 11.5,
    height: 1.1,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.2,
  );
}

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------

/// 4pt spacing scale.
abstract final class PoSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 22.0;
  static const xxl = 30.0;
}

/// Shared layout measures.
abstract final class PoLayout {
  /// Maximum width of a page's content column. Chrome stays full-bleed but its
  /// contents align to this, so nothing drifts to the window edges on desktop.
  static const content = 1180.0;
}

/// Corner radii. Larger than a productivity app on purpose — soft, generous
/// corners are a big part of why game UI reads as friendly rather than clinical.
abstract final class PoRadius {
  static const pill = 999.0;
  static const xs = 10.0;
  static const sm = 13.0;
  static const md = 17.0;
  static const lg = 22.0;
  static const xl = 28.0;
}

/// Layered shadow sets.
///
/// Every level is a tight contact shadow plus a wide ambient one. That pairing
/// is what makes an element read as resting on the page instead of pasted on.
abstract final class PoElevate {
  static const _tint = Color(0xFF0B3B2C);

  /// Hairline only — for elements inside an already-raised panel.
  static List<BoxShadow> get e0 => const [
    BoxShadow(color: Color(0x0F0B3B2C), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// Resting card.
  static List<BoxShadow> get e1 => [
    BoxShadow(
      color: _tint.withValues(alpha: 0.07),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: _tint.withValues(alpha: 0.07),
      blurRadius: 14,
      offset: const Offset(0, 6),
    ),
  ];

  /// Raised / interactive card, hovered row.
  static List<BoxShadow> get e2 => [
    BoxShadow(
      color: _tint.withValues(alpha: 0.09),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: _tint.withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, 11),
    ),
  ];

  /// Floating chrome: dock, HUD, sticky panels.
  static List<BoxShadow> get e3 => [
    BoxShadow(
      color: _tint.withValues(alpha: 0.10),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: _tint.withValues(alpha: 0.13),
      blurRadius: 38,
      offset: const Offset(0, 16),
    ),
  ];

  /// Modals and dialogs.
  static List<BoxShadow> get e4 => [
    BoxShadow(
      color: _tint.withValues(alpha: 0.16),
      blurRadius: 10,
      offset: const Offset(0, 6),
    ),
    BoxShadow(
      color: _tint.withValues(alpha: 0.22),
      blurRadius: 60,
      offset: const Offset(0, 26),
    ),
  ];

  /// Coloured bloom under a primary action or currency medallion.
  static List<BoxShadow> glow(Color face, {double strength = 1}) => [
    BoxShadow(
      color: face.withValues(alpha: 0.34 * strength),
      blurRadius: 18 * strength,
      offset: Offset(0, 6 * strength),
    ),
  ];

  /// Recessed look for wells and tracks.
  static List<BoxShadow> get inset => const [
    BoxShadow(
      color: Color(0x140B3B2C),
      blurRadius: 3,
      offset: Offset(0, 1),
      blurStyle: BlurStyle.inner,
    ),
  ];
}

/// Responsive tiers. Named so screens branch on intent, not magic numbers.
enum PoBreak {
  /// Phone portrait.
  compact,

  /// Large phone / small tablet portrait.
  medium,

  /// Tablet landscape.
  expanded,

  /// Desktop.
  wide;

  static PoBreak of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static PoBreak fromWidth(double width) => switch (width) {
    < 420 => PoBreak.compact,
    < 700 => PoBreak.medium,
    < 1080 => PoBreak.expanded,
    _ => PoBreak.wide,
  };

  bool get isCompact => this == PoBreak.compact;
  bool get isPhone => index <= PoBreak.medium.index;
  bool get isDesktop => this == PoBreak.wide;

  /// Picks per-tier values without a chain of ternaries at every call site.
  T pick<T>({required T compact, T? medium, T? expanded, T? wide}) =>
      switch (this) {
        PoBreak.compact => compact,
        PoBreak.medium => medium ?? compact,
        PoBreak.expanded => expanded ?? medium ?? compact,
        PoBreak.wide => wide ?? expanded ?? medium ?? compact,
      };
}

// ---------------------------------------------------------------------------
// Motion
// ---------------------------------------------------------------------------

abstract final class PoMotion {
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 380);

  /// Snappy in, settled out — the standard for UI state changes.
  static const curve = Curves.easeOutCubic;

  /// Slight overshoot, for rewards and things appearing.
  static const pop = Curves.easeOutBack;

  static Duration respect(BuildContext context, Duration base) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : base;
}

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

/// Universal press/hover feedback.
///
/// Wraps any content so it dips and dims under the finger and lifts on hover.
/// Game UI lives or dies on this: a card that does not react to touch reads as
/// a picture of a card.
class PoPressable extends StatefulWidget {
  const PoPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.radius = PoRadius.md,
    this.pressScale = 0.975,
    this.enableHoverLift = true,
    this.semanticLabel,
    this.selected,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final double pressScale;
  final bool enableHoverLift;
  final String? semanticLabel;
  final bool? selected;

  @override
  State<PoPressable> createState() => _PoPressableState();
}

class _PoPressableState extends State<PoPressable> {
  bool _down = false;
  bool _hover = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    final duration = PoMotion.respect(context, PoMotion.fast);
    final lift = widget.enableHoverLift && _hover && !_down ? -1.5 : 0.0;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                },
          onLongPress: widget.onLongPress,
          child: AnimatedScale(
            duration: duration,
            curve: PoMotion.curve,
            scale: _down ? widget.pressScale : 1,
            child: AnimatedSlide(
              duration: duration,
              curve: PoMotion.curve,
              offset: Offset(0, lift / 100),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Surface roles. Each has a distinct fill/elevation treatment, so a panel's
/// job is legible before a single word is read.
enum PoSurfaceKind {
  /// Standard content card floating on the page.
  card,

  /// Emphasised card — carries an accent wash and a coloured rim glow.
  featured,

  /// Recessed area inside another panel.
  well,

  /// Locked / unavailable content.
  muted,

  /// Floating chrome (dock, sticky bars, popovers).
  chrome,

  /// Modal / dialog body.
  modal,
}

/// The one panel widget everything is built from.
///
/// Hierarchy comes from `kind` + `accent`, never from a border colour. A single
/// inner top highlight is included on raised kinds, which is what sells the
/// "moulded plastic" feel that flat cards lack.
class PoPanel extends StatelessWidget {
  const PoPanel({
    super.key,
    required this.child,
    this.kind = PoSurfaceKind.card,
    this.accent,
    this.padding = const EdgeInsets.all(PoSpace.lg),
    this.radius = PoRadius.lg,
    this.onTap,
    this.clip = false,
  });

  final Widget child;
  final PoSurfaceKind kind;

  /// Tints the wash, rim and glow. Ignored by [PoSurfaceKind.muted].
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent ?? PoColor.primaryFace;
    final border = BorderRadius.circular(radius);

    final (
      List<Color> fill,
      List<BoxShadow> shadow,
      Color rim,
    ) = switch (kind) {
      PoSurfaceKind.card => (
        const [PoColor.surfaceLift, PoColor.surface],
        PoElevate.e1,
        PoColor.hairline,
      ),
      PoSurfaceKind.featured => (
        [PoColor.lighten(accent, 0.93), PoColor.surface],
        [...PoElevate.e2, ...PoElevate.glow(accent, strength: 0.42)],
        accent.withValues(alpha: 0.42),
      ),
      PoSurfaceKind.well => (
        const [PoColor.surfaceSunken, Color(0xFFEDF3EE)],
        const <BoxShadow>[],
        PoColor.hairline,
      ),
      // Locked content still needs to look like a designed surface: a flat
      // grey slab reads as broken rather than unavailable, and on the staff and
      // department screens most cards start locked.
      PoSurfaceKind.muted => (
        [
          Color.lerp(const Color(0xFFF5F8F6), accent, 0.05)!,
          Color.lerp(PoColor.surfaceMuted, accent, 0.04)!,
        ],
        PoElevate.e0,
        accent.withValues(alpha: 0.14),
      ),
      PoSurfaceKind.chrome => (
        const [PoColor.chrome, Color(0xFFF6FAF7)],
        PoElevate.e3,
        PoColor.hairline,
      ),
      PoSurfaceKind.modal => (
        const [PoColor.surfaceLift, PoColor.surface],
        PoElevate.e4,
        PoColor.hairlineStrong,
      ),
    };

    final raised = kind != PoSurfaceKind.well && kind != PoSurfaceKind.muted;

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: fill,
        ),
        borderRadius: border,
        border: Border.all(
          color: rim,
          width: kind == PoSurfaceKind.featured ? 1.4 : 1,
        ),
        boxShadow: shadow,
      ),
      child: Stack(
        children: [
          // Inner top highlight. One hairline of light along the top edge is
          // the cheapest possible "this object has a surface" cue.
          if (raised)
            Positioned(
              left: 1,
              right: 1,
              top: 0,
              height: radius,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(radius),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.9),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );

    if (clip) {
      body = ClipRRect(borderRadius: border, child: body);
    }
    if (onTap != null) {
      body = PoPressable(onTap: onTap, radius: radius, child: body);
    }
    return body;
  }
}

/// Saturated identity band used at the top of hero panels.
///
/// Colour concentrated in one confident block, with the page's content staying
/// bright, is how commercial tycoon UI gets richness without visual noise.
class PoIdentityBand extends StatelessWidget {
  const PoIdentityBand({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.face = PoColor.primaryFace,
    this.deep,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color face;
  final Color? deep;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Normalise whatever the screen passed into a lit/shaded pair of the same
    // hue, so no caller can produce a near-black band.
    final lit = PoColor.vivid(face, lightness: 0.56);
    final deep = PoColor.vivid(this.deep ?? face, lightness: 0.26);
    final onBand = PoColor.onFace(deep);
    final medallion = compact ? 42.0 : 50.0;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(PoRadius.lg),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [lit, deep],
                ),
              ),
            ),
          ),
          // Two soft light pools give the band depth without a texture asset.
          Positioned(
            right: -30,
            top: -46,
            child: _Blob(
              size: 132,
              color: Colors.white.withValues(alpha: 0.16),
            ),
          ),
          Positioned(
            left: -22,
            bottom: -54,
            child: _Blob(
              size: 108,
              color: Colors.black.withValues(alpha: 0.09),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              compact ? 12 : 14,
              compact ? 12 : 16,
              compact ? 13 : 15,
            ),
            child: Row(
              children: [
                Container(
                  width: medallion,
                  height: medallion,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(
                      compact ? PoRadius.sm : PoRadius.md,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.42),
                      width: 1.4,
                    ),
                  ),
                  child: Icon(icon, color: onBand, size: compact ? 22 : 26),
                ),
                SizedBox(width: compact ? 11 : 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: (compact ? PoText.h1 : PoText.display).copyWith(
                          color: onBand,
                        ),
                      ),
                      if (subtitle case final text?) ...[
                        const SizedBox(height: PoSpace.xs),
                        Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: PoText.bodySm.copyWith(
                            color: onBand.withValues(alpha: 0.82),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing case final widget?) ...[
                  const SizedBox(width: PoSpace.sm),
                  widget,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

/// Gradient icon medallion with a gloss highlight.
class PoIconBadge extends StatelessWidget {
  const PoIconBadge({
    super.key,
    required this.icon,
    this.face = PoColor.primaryFace,
    this.size = 46,
    this.iconSize,
    this.radius,
    this.tinted = false,
  });

  final IconData icon;
  final Color face;
  final double size;
  final double? iconSize;
  final double? radius;

  /// Soft tinted treatment instead of a saturated medallion — for dense lists
  /// where a wall of full-colour badges would fight the content.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final radius = this.radius ?? size * 0.32;
    if (tinted) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              face.withValues(alpha: 0.22),
              face.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Icon(
          icon,
          size: iconSize ?? size * 0.48,
          color: PoColor.deepen(face, 0.24),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PoColor.lighten(face, 0.22), PoColor.deepen(face, 0.16)],
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: PoElevate.glow(face, strength: 0.55),
      ),
      child: Stack(
        children: [
          // Gloss: a bright cap over the top 45%, exactly like moulded plastic.
          Positioned(
            left: 2,
            right: 2,
            top: 1,
            height: size * 0.45,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.42),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Icon(
              icon,
              size: iconSize ?? size * 0.48,
              color: PoColor.onFace(face),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill tag tones.
enum PoTagTone {
  /// Filled with the accent — for the single most important state on a card.
  solid,

  /// Tinted wash with accent ink — the default.
  soft,

  /// Nearly invisible; for neutral metadata.
  ghost,
}

/// Status / metadata pill.
class PoTag extends StatelessWidget {
  const PoTag({
    super.key,
    required this.label,
    this.icon,
    this.face = PoColor.primaryFace,
    this.tone = PoTagTone.soft,
    this.dense = false,
    this.showDot = false,
    this.maxWidth,
  });

  final String label;
  final IconData? icon;
  final Color face;
  final PoTagTone tone;
  final bool dense;
  final bool showDot;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final deep = PoColor.deepen(face, 0.30);
    final (
      Gradient? gradient,
      Color? fill,
      Color ink,
      Color rim,
    ) = switch (tone) {
      PoTagTone.solid => (
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PoColor.lighten(face, 0.16), PoColor.deepen(face, 0.12)],
        ),
        null,
        PoColor.onFace(face),
        Colors.white.withValues(alpha: 0.38),
      ),
      PoTagTone.soft => (
        null,
        face.withValues(alpha: 0.15),
        deep,
        face.withValues(alpha: 0.28),
      ),
      PoTagTone.ghost => (
        null,
        PoColor.surfaceSunken,
        PoColor.textSecondary,
        Colors.transparent,
      ),
    };

    return Container(
      constraints: BoxConstraints(
        minHeight: dense ? 22 : 27,
        maxWidth: maxWidth ?? double.infinity,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 3 : 4,
      ),
      decoration: BoxDecoration(
        gradient: gradient,
        color: fill,
        borderRadius: BorderRadius.circular(PoRadius.pill),
        border: Border.all(color: rim),
        boxShadow: tone == PoTagTone.solid
            ? PoElevate.glow(face, strength: 0.35)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            PoDot(color: ink, size: dense ? 5 : 6),
            SizedBox(width: dense ? 4 : 5),
          ] else if (icon case final glyph?) ...[
            Icon(glyph, size: dense ? 11 : 13, color: ink),
            SizedBox(width: dense ? 4 : 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (dense ? PoText.caption : PoText.label).copyWith(
                color: ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small glowing status dot.
class PoDot extends StatelessWidget {
  const PoDot({super.key, required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 5),
      ],
    ),
  );
}

/// Recessed stat well: tiny label over a large tabular numeral.
///
/// Replaces the bordered `label: value` rectangles that used to carry every
/// metric. Sinking the tile and enlarging the number is what makes numbers
/// scannable at arm's length.
class PoStatWell extends StatelessWidget {
  const PoStatWell({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.face = PoColor.primaryFace,
    this.emphasis = false,
    this.minWidth,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color face;

  /// Colours the numeral with the accent instead of ink. Use sparingly — one
  /// emphasised stat per group, otherwise nothing stands out.
  final bool emphasis;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final tier = PoBreak.of(context);
    final dense = tier.isCompact;
    return Container(
      constraints: BoxConstraints(
        minWidth: minWidth ?? (dense ? 88 : 104),
        minHeight: dense ? 48 : 54,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 9 : 11,
        vertical: dense ? 7 : 9,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(const Color(0xFFE4EBE6), face, 0.10)!,
            Color.lerp(const Color(0xFFF1F6F2), face, 0.05)!,
          ],
        ),
        borderRadius: BorderRadius.circular(PoRadius.sm),
        border: Border.all(color: face.withValues(alpha: 0.16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon case final glyph?) ...[
                Icon(
                  glyph,
                  size: dense ? 11 : 12,
                  color: PoColor.deepen(face, 0.22),
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PoText.overline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (dense ? PoText.numeralSm : PoText.numeral).copyWith(
              color: emphasis ? PoColor.deepen(face, 0.26) : PoColor.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress meter with a sunken track, gradient fill and a moving shine.
class PoMeter extends StatelessWidget {
  const PoMeter({
    super.key,
    required this.value,
    this.face = PoColor.primaryFace,
    this.height = 9,
    this.width,
    this.showShine = true,
  });

  final double value;
  final Color face;
  final double height;
  final double? width;
  final bool showShine;

  @override
  Widget build(BuildContext context) {
    final ratio = value.clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PoRadius.pill),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFD3DED8), Color(0xFFE2EAE5)],
                  ),
                ),
              ),
            ),
            AnimatedFractionallySizedBox(
              duration: PoMotion.respect(context, PoMotion.normal),
              curve: PoMotion.curve,
              widthFactor: ratio,
              alignment: AlignmentDirectional.centerStart,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      PoColor.lighten(face, 0.34),
                      face,
                      PoColor.deepen(face, 0.14),
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                  boxShadow: ratio <= 0
                      ? null
                      : PoElevate.glow(face, strength: 0.32),
                ),
                child: showShine && height >= 7
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: FractionallySizedBox(
                          heightFactor: 0.42,
                          widthFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.30),
                              borderRadius: BorderRadius.circular(
                                PoRadius.pill,
                              ),
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eyebrow + title + fading rule. The standard way to open a section.
class PoSectionHead extends StatelessWidget {
  const PoSectionHead({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.face = PoColor.primaryFace,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;
  final Color face;

  @override
  Widget build(BuildContext context) {
    final tier = PoBreak.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow case final text?) ...[
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 3,
                      decoration: BoxDecoration(
                        color: PoColor.deepen(face, 0.18),
                        borderRadius: BorderRadius.circular(PoRadius.pill),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        text.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PoText.overline.copyWith(
                          color: PoColor.deepen(face, 0.24),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
              ],
              Text(title, style: tier.isCompact ? PoText.h2 : PoText.h1),
              if (subtitle case final text?) ...[
                const SizedBox(height: 3),
                Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: PoText.bodySm,
                ),
              ],
            ],
          ),
        ),
        if (trailing case final widget?) ...[
          const SizedBox(width: PoSpace.sm),
          widget,
        ],
      ],
    );
  }
}

/// Button intents. Each is visually distinct enough to be read without labels.
enum PoBtnKind {
  /// The one thing to do on this screen.
  primary,

  /// Supporting actions.
  secondary,

  /// Confirmations that grant something.
  success,

  /// Irreversible / costly.
  destructive,

  /// Low-emphasis inline action.
  ghost,
}

/// Extruded button with real thickness.
///
/// The face sits on a solid darker edge; pressing collapses the edge so the
/// control physically sinks. This is the single strongest game-feel signal a
/// flat UI can gain, and it is why every action in the game uses this instead
/// of a Material button.
class PoBtn extends StatefulWidget {
  const PoBtn({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.kind = PoBtnKind.primary,
    this.dense = false,
    this.expand = false,
    this.loading = false,
    this.trailing,
    this.semanticLabel,
  });

  /// Icon-only variant: square, no label text rendered.
  const PoBtn.icon({
    super.key,
    required this.onPressed,
    required IconData this.icon,
    required String this.semanticLabel,
    this.kind = PoBtnKind.secondary,
    this.dense = false,
  }) : label = null,
       expand = false,
       loading = false,
       trailing = null;

  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;
  final PoBtnKind kind;
  final bool dense;
  final bool expand;
  final bool loading;
  final Widget? trailing;
  final String? semanticLabel;

  @override
  State<PoBtn> createState() => _PoBtnState();
}

class _PoBtnState extends State<PoBtn> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final iconOnly = widget.label == null;
    final thickness = widget.dense ? 3.0 : 4.0;
    final radius = widget.dense ? PoRadius.sm : PoRadius.md;

    final (
      Color face,
      Color? edgeOverride,
      Color? inkOverride,
    ) = switch (widget.kind) {
      PoBtnKind.primary => (PoColor.primaryFace, null, null),
      PoBtnKind.success => (PoColor.success, null, Colors.white),
      PoBtnKind.destructive => (PoColor.danger, null, Colors.white),
      PoBtnKind.secondary => (
        const Color(0xFFF2F6F2),
        const Color(0xFFCFDBD4),
        PoColor.inkSoft,
      ),
      PoBtnKind.ghost => (
        Colors.transparent,
        Colors.transparent,
        PoColor.deepen(PoColor.primaryFace, 0.3),
      ),
    };

    final enabled = _enabled;
    final effFace = enabled
        ? face
        : Color.lerp(face, PoColor.surfaceMuted, 0.72)!;
    final edge = enabled
        ? (edgeOverride ?? PoColor.deepen(face, 0.34))
        : const Color(0xFFD8DEDA);
    final ink = enabled
        ? (inkOverride ?? PoColor.onFace(PoColor.lighten(face, 0.2)))
        : PoColor.textDisabled;

    final sink = _down ? thickness : 0.0;
    final duration = PoMotion.respect(
      context,
      const Duration(milliseconds: 70),
    );

    final content = widget.loading
        ? SizedBox(
            height: widget.dense ? 14 : 16,
            width: widget.dense ? 14 : 16,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(ink),
            ),
          )
        : Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon case final glyph?) ...[
                Icon(glyph, size: widget.dense ? 15 : 17, color: ink),
                if (!iconOnly) SizedBox(width: widget.dense ? 5 : 7),
              ],
              if (widget.label case final text?)
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: (widget.dense ? PoText.buttonSm : PoText.button)
                        .copyWith(color: ink),
                  ),
                ),
              if (widget.trailing case final widget2?) ...[
                const SizedBox(width: 6),
                widget2,
              ],
            ],
          );

    final padding = iconOnly
        ? EdgeInsets.all(widget.dense ? 8 : 11)
        : EdgeInsets.symmetric(
            horizontal: widget.dense ? 12 : 18,
            vertical: widget.dense ? 8 : 12,
          );

    final isGhost = widget.kind == PoBtnKind.ghost;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: AnimatedPadding(
            duration: duration,
            curve: Curves.easeOut,
            padding: EdgeInsets.only(top: sink, bottom: thickness - sink),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isGhost ? Colors.transparent : edge,
                borderRadius: BorderRadius.circular(radius),
                boxShadow: enabled && !_down && !isGhost
                    ? [
                        ...PoElevate.e1,
                        if (widget.kind == PoBtnKind.primary ||
                            widget.kind == PoBtnKind.success)
                          ...PoElevate.glow(face, strength: 0.34),
                      ]
                    : null,
              ),
              child: Container(
                width: widget.expand ? double.infinity : null,
                margin: EdgeInsets.only(bottom: thickness),
                padding: padding,
                decoration: BoxDecoration(
                  gradient: isGhost
                      ? null
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [PoColor.lighten(effFace, 0.34), effFace],
                        ),
                  color: isGhost
                      ? (_down
                            ? PoColor.wash(PoColor.primaryFace, 0.14)
                            : Colors.transparent)
                      : null,
                  borderRadius: BorderRadius.circular(radius),
                  border: isGhost
                      ? null
                      : Border.all(color: Colors.white.withValues(alpha: 0.36)),
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft coloured light pools for page grounds.
///
/// A flat pale ground is the fastest way to look like a dashboard template.
/// Two or three very low-opacity blooms give the page atmosphere at effectively
/// no cost, and because they sit behind everything they never fight content.
class PoAurora extends StatelessWidget {
  const PoAurora({super.key, this.intensity = 1});

  final double intensity;

  @override
  Widget build(BuildContext context) {
    if (intensity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _AuroraPainter(intensity: intensity),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter({required this.intensity});

  final double intensity;

  static const _pools = <(Alignment, double, Color)>[
    (Alignment(-0.85, -0.95), 0.85, PoColor.primaryFace),
    (Alignment(0.95, -0.55), 0.70, PoColor.infoFace),
    (Alignment(0.10, 1.05), 0.95, PoColor.accentFace),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    for (final (align, radius, color) in _pools) {
      final paint = Paint()
        ..shader = RadialGradient(
          center: align,
          radius: radius,
          colors: [
            color.withValues(alpha: 0.16 * intensity),
            color.withValues(alpha: 0),
          ],
        ).createShader(rect);
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) =>
      old.intensity != intensity;
}

/// Page ground: gradient ramp + aurora, behind every screen.
class PoPageGround extends StatelessWidget {
  const PoPageGround({super.key, required this.child, this.aurora = 1});

  final Widget child;
  final double aurora;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF4F8F5), PoColor.canvas, PoColor.canvasDeep],
        stops: [0, 0.42, 1],
      ),
    ),
    child: Stack(
      children: [
        Positioned.fill(child: PoAurora(intensity: aurora)),
        Positioned.fill(child: child),
      ],
    ),
  );
}

/// Compact number formatting for readouts.
///
/// Tycoon economies reach seven figures quickly; the raw integer both overflows
/// the HUD and is harder to read at a glance than `2.4M`.
String poShort(num value) {
  final negative = value < 0;
  final magnitude = value.abs();
  final (scaled, suffix) = switch (magnitude) {
    >= 1000000000 => (magnitude / 1000000000, 'B'),
    >= 1000000 => (magnitude / 1000000, 'M'),
    >= 10000 => (magnitude / 1000, 'K'),
    _ => (magnitude.toDouble(), ''),
  };
  final body = suffix.isEmpty
      ? magnitude.round().toString()
      // One decimal below 100 keeps precision where the player still notices it.
      : (scaled < 100
            ? scaled.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')
            : scaled.round().toString());
  return '${negative ? '-' : ''}$body$suffix';
}
