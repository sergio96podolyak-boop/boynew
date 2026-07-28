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
                                  quest.title,
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
