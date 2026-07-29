import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../services/app_localizations.dart';

class QuestsScreen extends StatelessWidget {
  const QuestsScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(loc.questsTitle)),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final quest = controller.quest;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _MissionCard(
                title: loc.shiftMission,
                objective: loc.serveFiveCustomers,
                progress: controller.shiftMissionProgress,
                target: controller.shiftMissionTarget,
                reward: 20,
                completed: controller.shiftMissionCompleted,
                claimed: controller.shiftMissionClaimed,
                onClaim: controller.claimShiftMission,
                loc: loc,
              ),
              _MissionCard(
                title: loc.dailyMission,
                objective: loc.keepCustomersHappy,
                progress: controller.dailyMissionCompleted ? 1 : 0,
                target: 1,
                reward: 15,
                completed: controller.dailyMissionCompleted,
                claimed: controller.dailyMissionClaimed,
                onClaim: controller.claimDailyMission,
                loc: loc,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  loc.progressionMission,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: quest.completed
                                  ? Colors.green
                                  : const Color(0xFFFFE5AF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              quest.completed
                                  ? Icons.check_rounded
                                  : Icons.flag_rounded,
                              color: quest.completed
                                  ? Colors.white
                                  : const Color(0xFFA66B00),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loc.activeQuest,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  loc.questTitle(
                                    controller.questStage,
                                    quest.target,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: quest.fraction,
                          minHeight: 10,
                          color: const Color(0xFFF6A623),
                          backgroundColor: const Color(0xFFE8E4DA),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${quest.progress.clamp(0, quest.target)}/${quest.target}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (quest.completed)
                        FilledButton.icon(
                          onPressed: () {
                            controller.claimQuest();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${loc.questCompleted} +${quest.reward}',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: const Icon(Icons.card_giftcard_rounded),
                          label: Text('${loc.claimReward} ${quest.reward}'),
                        )
                      else
                        Text(
                          loc.questInProgress,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({
    required this.title,
    required this.objective,
    required this.progress,
    required this.target,
    required this.reward,
    required this.completed,
    required this.claimed,
    required this.onClaim,
    required this.loc,
  });

  final String title;
  final String objective;
  final int progress;
  final int target;
  final int reward;
  final bool completed;
  final bool claimed;
  final bool Function() onClaim;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final state = claimed ? loc.claimed : loc.active;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  state,
                  style: TextStyle(
                    fontSize: 11,
                    color: completed ? Colors.green : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(objective),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (progress / target).clamp(0, 1)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$progress/$target · ${loc.missionReward} $reward',
                  ),
                ),
                if (completed && !claimed)
                  TextButton(onPressed: onClaim, child: Text(loc.claimMission)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
