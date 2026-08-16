import 'package:flutter/material.dart';

/// Shared visual language for the premium PoMarket shell.
abstract final class PoMarketPalette {
  static const ink = Color(0xFF0C241E);
  static const forest = Color(0xFF063D2C);
  static const forestLight = Color(0xFF0E5B42);
  static const mint = Color(0xFF2FD08C);
  static const mintSoft = Color(0xFFD6F7E8);
  static const cream = Color(0xFFFFFDF6);
  static const canvas = Color(0xFFEDF3EE);
  static const gold = Color(0xFFFFBE2E);
  static const coral = Color(0xFFFF5C77);
  static const violet = Color(0xFF9B7CFF);
  static const blue = Color(0xFF4FA3FF);
  static const muted = Color(0xFF6A7A73);
  static const line = Color(0x1A123A30);
}

abstract final class PoMarketRadii {
  static const small = 12.0;
  static const control = 15.0;
  static const card = 22.0;
  static const hero = 28.0;
}

abstract final class PoMarketSpacing {
  static const compact = 8.0;
  static const content = 12.0;
  static const card = 16.0;
  static const section = 22.0;
}

abstract final class PoMarketTextStyles {
  static const cardTitle = TextStyle(
    color: PoMarketPalette.ink,
    fontSize: 16,
    height: 1.15,
    fontWeight: FontWeight.w900,
  );

  static const supporting = TextStyle(
    color: PoMarketPalette.muted,
    fontSize: 11,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  static const overline = TextStyle(
    fontSize: 10,
    height: 1.1,
    letterSpacing: 0.35,
    fontWeight: FontWeight.w900,
  );
}

class PremiumSurface extends StatelessWidget {
  const PremiumSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = PoMarketRadii.card,
    this.color = PoMarketPalette.cream,
    this.borderColor = PoMarketPalette.line,
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
    return DecoratedBox(
      decoration: BoxDecoration(
        // A faint top-to-bottom lift keeps flat cream from looking like paper.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, Colors.white, 0.5)!, color],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: elevation <= 0
            ? null
            : [
                // Tight contact shadow first, then a wide ambient one: the
                // pairing is what makes a surface read as raised.
                BoxShadow(
                  color: PoMarketPalette.forest.withValues(alpha: 0.10),
                  blurRadius: elevation * 0.5,
                  offset: Offset(0, elevation * 0.18),
                ),
                BoxShadow(
                  color: PoMarketPalette.forest.withValues(alpha: 0.085),
                  blurRadius: elevation * 2.2,
                  offset: Offset(0, elevation * 0.75),
                ),
                const BoxShadow(
                  color: Color(0x99FFFFFF),
                  blurRadius: 1,
                  offset: Offset(0, -1),
                ),
              ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

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
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.24),
            color.withValues(alpha: 0.07),
          ],
        ),
        borderRadius: BorderRadius.circular(PoMarketRadii.control),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

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
      child: PremiumSurface(
        elevation: 0,
        radius: PoMarketRadii.control,
        color: color.withValues(alpha: 0.055),
        borderColor: color.withValues(alpha: 0.18),
        padding: const EdgeInsetsDirectional.fromSTEB(11, 9, 11, 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: PoMarketPalette.ink,
                  fontSize: 10,
                  height: 1.3,
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

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.38),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}
