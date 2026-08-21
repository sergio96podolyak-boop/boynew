import 'package:flutter/material.dart';

import '../theme/po_system.dart';

/// Legacy vocabulary, now a thin alias over [PoColor].
///
/// Hundreds of call sites across the nine screens reference these names. Rather
/// than churn every file, the names stay and the *values* resolve to the design
/// system's semantic roles — so retuning the system retunes the whole app.
/// New code should reference [PoColor] directly.
abstract final class PoMarketPalette {
  static const ink = PoColor.ink;
  static const forest = PoColor.primaryDeep;
  static const forestLight = PoColor.secondaryDeep;
  static const mint = PoColor.primaryFace;
  static const mintSoft = Color(0xFFD8F6E7);
  static const cream = PoColor.surface;
  static const canvas = PoColor.canvas;
  static const gold = PoColor.goldFace;
  static const coral = PoColor.danger;
  static const violet = PoColor.accentFace;
  static const blue = PoColor.infoFace;
  static const muted = PoColor.textSecondary;
  static const line = PoColor.hairline;
}

abstract final class PoMarketRadii {
  static const small = PoRadius.xs;
  static const control = PoRadius.sm;
  static const card = PoRadius.lg;
  static const hero = PoRadius.xl;
}

abstract final class PoMarketSpacing {
  static const compact = PoSpace.sm;
  static const content = PoSpace.md;
  static const card = PoSpace.lg;
  static const section = PoSpace.xl;
}

abstract final class PoMarketTextStyles {
  static const cardTitle = PoText.h3;
  static const supporting = PoText.bodySm;
  static const overline = PoText.overline;
}

/// Layered surface. Delegates to [PoPanel] so there is exactly one place in the
/// codebase that decides what a raised surface looks like.
class PremiumSurface extends StatelessWidget {
  const PremiumSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = PoMarketRadii.card,
    this.color = PoColor.surface,
    this.borderColor = PoColor.hairline,
    this.elevation = 8,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final Color borderColor;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    // Callers signalled "tinted informational block" by passing a translucent
    // colour; that maps onto a well, not a floating card.
    final tinted = color.a < 0.99;
    return PoPanel(
      kind: elevation <= 0
          ? (tinted ? PoSurfaceKind.well : PoSurfaceKind.muted)
          : PoSurfaceKind.card,
      radius: radius,
      padding: padding,
      child: child,
    );
  }
}

/// Soft tinted icon tile for dense lists.
class PremiumIconTile extends StatelessWidget {
  const PremiumIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 52,
    this.iconSize = 25,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => PoIconBadge(
    icon: icon,
    face: color,
    size: size,
    iconSize: iconSize,
    tinted: true,
    radius: PoRadius.sm,
  );
}

/// Inline advisory / empty-state note.
class PremiumStateMessage extends StatelessWidget {
  const PremiumStateMessage({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: message,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 9, 12, 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [
              color.withValues(alpha: 0.14),
              color.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(PoRadius.sm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A saturated leading rule reads as "note" far faster than a box.
            Container(
              width: 3,
              height: 26,
              margin: const EdgeInsetsDirectional.only(end: 9),
              decoration: BoxDecoration(
                color: PoColor.deepen(color, 0.18),
                borderRadius: BorderRadius.circular(PoRadius.pill),
              ),
            ),
            Icon(icon, color: PoColor.deepen(color, 0.24), size: 17),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                message,
                style: PoText.bodySm.copyWith(
                  color: PoColor.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glowing status dot. Alias of [PoDot] for existing call sites.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => PoDot(color: color, size: size);
}
