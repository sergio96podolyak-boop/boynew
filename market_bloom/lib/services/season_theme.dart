import 'package:flutter/material.dart';

/// The four seasonal cosmetic themes for PoMarket.
enum SeasonTheme { spring, summer, autumn, winter }

/// Detects and exposes the current [SeasonTheme] based on the real-world date.
abstract final class SeasonManager {
  /// Returns the season for [date] (or today when omitted).
  static SeasonTheme current({DateTime? date}) {
    final month = (date ?? DateTime.now()).month;
    return switch (month) {
      3 || 4 || 5 => SeasonTheme.spring,
      6 || 7 || 8 => SeasonTheme.summer,
      9 || 10 || 11 => SeasonTheme.autumn,
      _ => SeasonTheme.winter,
    };
  }
}

/// Visual palette and decorative data for a given [SeasonTheme].
extension SeasonThemeData on SeasonTheme {
  // ── Primary shelf / accent colours ────────────────────────────────────────

  /// Main shelf-plank tint.
  Color get shelfColor => switch (this) {
    SeasonTheme.spring => const Color(0xFFB5E8B0),   // soft green
    SeasonTheme.summer => const Color(0xFFFFE082),   // warm yellow
    SeasonTheme.autumn => const Color(0xFFE8A87C),   // burnt orange
    SeasonTheme.winter => const Color(0xFFB3D9F2),   // icy blue
  };

  /// Shelf edge / border tint.
  Color get shelfEdgeColor => switch (this) {
    SeasonTheme.spring => const Color(0xFF7DC87A),
    SeasonTheme.summer => const Color(0xFFFFC107),
    SeasonTheme.autumn => const Color(0xFFD4721A),
    SeasonTheme.winter => const Color(0xFF64B5F6),
  };

  /// Floor tile base colour.
  Color get floorColor => switch (this) {
    SeasonTheme.spring => const Color(0xFFF1FFF0),
    SeasonTheme.summer => const Color(0xFFFFFDE7),
    SeasonTheme.autumn => const Color(0xFFFFF3E0),
    SeasonTheme.winter => const Color(0xFFE3F2FD),
  };

  /// Checkout counter accent.
  Color get counterColor => switch (this) {
    SeasonTheme.spring => const Color(0xFF66BB6A),
    SeasonTheme.summer => const Color(0xFFFFB300),
    SeasonTheme.autumn => const Color(0xFFBF360C),
    SeasonTheme.winter => const Color(0xFF1E88E5),
  };

  /// Wall / sky gradient top.
  Color get wallTopColor => switch (this) {
    SeasonTheme.spring => const Color(0xFFE8F5E9),
    SeasonTheme.summer => const Color(0xFFFFF8E1),
    SeasonTheme.autumn => const Color(0xFFFBE9E7),
    SeasonTheme.winter => const Color(0xFFE3F2FD),
  };

  // ── Ambient particle data ──────────────────────────────────────────────────

  /// Floating decoration particle emoji (rendered on the canvas).
  String get particleEmoji => switch (this) {
    SeasonTheme.spring => '🌸',
    SeasonTheme.summer => '☀️',
    SeasonTheme.autumn => '🍂',
    SeasonTheme.winter => '❄️',
  };

  /// Human-readable season name.
  String get displayName => switch (this) {
    SeasonTheme.spring => 'Spring',
    SeasonTheme.summer => 'Summer',
    SeasonTheme.autumn => 'Autumn',
    SeasonTheme.winter => 'Winter',
  };

  /// Max number of ambient particles visible at once.
  int get maxParticles => switch (this) {
    SeasonTheme.winter => 18,  // lots of snowflakes
    SeasonTheme.autumn => 14,  // falling leaves
    SeasonTheme.spring => 10,  // petals
    SeasonTheme.summer => 6,   // sparse sun-rays
  };

  /// Particle fall speed multiplier (1.0 = normal).
  double get particleSpeed => switch (this) {
    SeasonTheme.winter => 0.6,   // slow drift
    SeasonTheme.autumn => 0.85,  // gentle tumble
    SeasonTheme.spring => 0.70,  // flutter
    SeasonTheme.summer => 0.40,  // slow shimmer
  };
}
