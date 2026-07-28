import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/meta_models.dart';
import '../../services/app_localizations.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(loc.achievementsTitle)),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final total = AchievementCatalog.all.length;
          final unlocked = controller.unlockedAchievementCount;
          if (total == 0) {
            return Center(child: Text(loc.noAchievementsYet));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: const Color(0xFF315F4A),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.emoji_events_rounded,
                        color: Color(0xFFFFD95A),
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$unlocked/$total ${loc.badgesUnlocked}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: unlocked / total,
                                minHeight: 7,
                                color: const Color(0xFFFFD95A),
                                backgroundColor: const Color(0xFF527965),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final definition in AchievementCatalog.all)
                _AchievementCard(
                  definition: definition,
                  progress: controller.progressFor(definition),
                  loc: loc,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({
    required this.definition,
    required this.progress,
    required this.loc,
  });

  final AchievementDefinition definition;
  final AchievementProgress progress;
  final AppLocalizations loc;

  static Color _tierColor(AchievementTier tier) {
    return switch (tier) {
      AchievementTier.bronze => const Color(0xFFCD7F32),
      AchievementTier.silver => const Color(0xFFC0C0C0),
      AchievementTier.gold => const Color(0xFFFFD700),
      AchievementTier.platinum => const Color(0xFFE5E4E2),
    };
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = progress.isUnlocked;
    final color = _tierColor(definition.tier);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: unlocked ? color : Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: unlocked
                  ? Text(definition.badge, style: const TextStyle(fontSize: 25))
                  : const Icon(Icons.lock_rounded, color: Colors.grey),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          definition.title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        unlocked
                            ? loc.unlockedLabel
                            : '${progress.currentValue.clamp(0, definition.target)}/${definition.target}',
                        style: TextStyle(
                          color: unlocked ? color : Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    definition.description,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress.fractionFor(definition),
                      minHeight: 6,
                      color: color,
                      backgroundColor: const Color(0xFFDCDAD3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
