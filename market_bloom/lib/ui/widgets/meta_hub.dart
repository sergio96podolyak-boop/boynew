import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/meta_models.dart';
import '../../services/app_localizations.dart';
import '../../services/share_service.dart';
import '../../services/sfx/sfx_manager.dart';
import 'pressable_scale.dart';

class MetaHub extends StatelessWidget {
  const MetaHub({
    super.key,
    required this.game,
    required this.onCelebrate,
    required this.onReplayTutorial,
  });

  static const publicGameUrl =
      'https://pomarket-review.ordersp495.chatgpt.site/';

  final GameController game;
  final VoidCallback onCelebrate;
  final VoidCallback onReplayTutorial;

  @override
  Widget build(BuildContext context) {
    final height = min(650.0, MediaQuery.sizeOf(context).height * 0.74);
    return SizedBox(
      height: height,
      child: DefaultTabController(
        length: 4,
        child: AnimatedBuilder(
          animation: game,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Business Hub',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Your progress, records, and rewards',
                          style: TextStyle(
                            color: Color(0xFF707872),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ScorePill(score: game.businessScore),
                ],
              ),
              const SizedBox(height: 10),
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Color(0xFFE8E4DA),
                tabs: [
                  Tab(text: 'ACHIEVEMENTS'),
                  Tab(text: 'STATS'),
                  Tab(text: 'LEADERBOARD'),
                  Tab(text: 'SETTINGS'),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: [
                    _AchievementsTab(game: game),
                    _StatsTab(game: game),
                    _LeaderboardTab(game: game, onCelebrate: onCelebrate),
                    _SettingsTab(
                      game: game,
                      onReplayTutorial: onReplayTutorial,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF315F4A), Color(0xFF38B879)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Text(
            'SCORE',
            style: TextStyle(
              color: Color(0xFFCFF5E2),
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            _formatNumber(score),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementsTab extends StatelessWidget {
  const _AchievementsTab({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 5, 0, 16),
      itemCount: AchievementCatalog.all.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ProgressBanner(
            icon: Icons.emoji_events_rounded,
            title:
                '${game.unlockedAchievementCount}/${AchievementCatalog.all.length} badges unlocked',
            value:
                game.unlockedAchievementCount / AchievementCatalog.all.length,
          );
        }
        final definition = AchievementCatalog.all[index - 1];
        final progress = game.progressFor(definition);
        return _AchievementCard(definition: definition, progress: progress);
      },
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.definition, required this.progress});

  final AchievementDefinition definition;
  final AchievementProgress progress;

  @override
  Widget build(BuildContext context) {
    final unlocked = progress.isUnlocked;
    final color = _tierColor(definition.tier);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unlocked
            ? color.withValues(alpha: 0.12)
            : const Color(0xFFF2F0EA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: unlocked
              ? color.withValues(alpha: 0.45)
              : const Color(0xFFDCD9D1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: unlocked ? color : const Color(0xFFD7D4CD),
              borderRadius: BorderRadius.circular(16),
              boxShadow: unlocked
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.22),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: unlocked
                ? Text(definition.badge, style: const TextStyle(fontSize: 25))
                : const Icon(Icons.lock_rounded, color: Color(0xFF7E827E)),
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
                          ? 'UNLOCKED'
                          : '${min(progress.currentValue, definition.target)}/${definition.target}',
                      style: TextStyle(
                        color: unlocked ? color : const Color(0xFF777C77),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  definition.description,
                  style: const TextStyle(
                    color: Color(0xFF707570),
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
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  const _ProgressBanner({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF315F4A),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFFD95A), size: 30),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: LinearProgressIndicator(
                    value: value,
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
    );
  }
}

class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final cards = <({IconData icon, String label, String value, Color color})>[
      (
        icon: Icons.timer_rounded,
        label: loc.playTime,
        value: _formatDuration(game.totalPlayTime),
        color: const Color(0xFF5B8DEF),
      ),
      (
        icon: Icons.touch_app_rounded,
        label: loc.actions,
        value: _formatNumber(game.totalActions),
        color: const Color(0xFF8B66D8),
      ),
      (
        icon: Icons.monetization_on_rounded,
        label: loc.bestBalance,
        value: _formatNumber(game.highestBalance),
        color: const Color(0xFFF6A623),
      ),
      (
        icon: Icons.workspace_premium_rounded,
        label: loc.highScore,
        value: _formatNumber(game.highestScore),
        color: const Color(0xFFE85D75),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 5, 0, 18),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            childAspectRatio: 1.65,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) => _StatCard(data: cards[index]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E1D8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.performanceHistory,
                style: TextStyle(
                  color: Color(0xFF315F4A),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${game.performanceHistory.length} ${loc.savedSnapshots} · ${loc.scoreOverTime}',
                style: const TextStyle(color: Color(0xFF7A7F7B), fontSize: 11),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 155,
                child: CustomPaint(
                  painter: _HistoryChartPainter(game.performanceHistory),
                  child: game.performanceHistory.length < 2
                      ? Center(
                          child: Text(
                            loc.keepPlayingChart,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF7A7F7B),
                              fontSize: 12,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MiniMetric(
                label: loc.customers,
                value: '${game.totalSales}',
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _MiniMetric(
                label: loc.itemsStocked,
                value: '${game.stockedTotal}',
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _MiniMetric(
                label: loc.upgradesCount,
                value: '${game.upgradesBought}',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});

  final ({IconData icon, String label, String value, Color color}) data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: data.color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(data.icon, color: data.color, size: 27),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: data.color,
                    fontSize: 9,
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

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EEE7),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF767B77),
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardTab extends StatelessWidget {
  const _LeaderboardTab({required this.game, required this.onCelebrate});

  final GameController game;
  final VoidCallback onCelebrate;

  Future<void> _submit(BuildContext context) async {
    unawaited(SfxManager.instance.click());
    final controller = TextEditingController(text: 'Player');
    final loc = AppLocalizations.of(context);
    final nickname = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(loc.postYourScore),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: loc.nickname,
            hintText: loc.enterYourPlayerName,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(loc.post),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!context.mounted || nickname == null) {
      return;
    }
    final entry = game.submitLeaderboardScore(nickname);
    unawaited(SfxManager.instance.milestone());
    onCelebrate();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          loc.joinedLeaderboard
              .replaceFirst('{nickname}', entry.nickname)
              .replaceFirst('{score}', _formatNumber(entry.score)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    unawaited(SfxManager.instance.click());
    final nickname = game.leaderboard.isEmpty
        ? 'Player'
        : game.leaderboard.first.nickname;
    final result = await const ShareService().shareChallenge(
      score: game.businessScore,
      nickname: nickname,
      url: MetaHub.publicGameUrl,
    );
    if (!context.mounted) {
      return;
    }
    if (result.succeeded) {
      unawaited(SfxManager.instance.success());
    } else {
      unawaited(SfxManager.instance.error());
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.feedback),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 5, 0, 18),
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF244D3A), Color(0xFF3A8663)],
            ),
            borderRadius: BorderRadius.circular(21),
          ),
          child: Column(
            children: [
              Text(
                AppLocalizations.of(context).yourCurrentBusinessScore,
                style: TextStyle(
                  color: Color(0xFFCDEDDD),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _formatNumber(game.businessScore),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 33,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: PressableScale(
                      child: FilledButton.icon(
                        onPressed: () => unawaited(_submit(context)),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: const Color(0xFFFFD95A),
                          foregroundColor: const Color(0xFF294B3A),
                        ),
                        icon: const Icon(Icons.leaderboard_rounded),
                        label: Text(AppLocalizations.of(context).postScore),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: PressableScale(
                      child: OutlinedButton.icon(
                        onPressed: () => unawaited(_share(context)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFAEE0C5)),
                        ),
                        icon: const Icon(Icons.ios_share_rounded),
                        label: Text(AppLocalizations.of(context).challenge),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: Text(
                AppLocalizations.of(context).localTop10,
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              AppLocalizations.of(context).savedOnThisDevice,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: const Color(0xFF7A7E7A)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (game.leaderboard.isEmpty)
          const _EmptyLeaderboard()
        else
          ...game.leaderboard.indexed.map(
            (ranked) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LeaderboardRow(rank: ranked.$1 + 1, entry: ranked.$2),
            ),
          ),
      ],
    );
  }
}

class _EmptyLeaderboard extends StatelessWidget {
  const _EmptyLeaderboard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EEE7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(Icons.emoji_events_outlined, size: 42, color: Color(0xFF839087)),
          SizedBox(height: 8),
          Text(
            'The podium is waiting for you.',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          Text(
            'Post your current score to claim the first spot.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF777D79), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.rank, required this.entry});

  final int rank;
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final medal = switch (rank) {
      1 => ('🥇', const Color(0xFFFFE372)),
      2 => ('🥈', const Color(0xFFE1E5E8)),
      3 => ('🥉', const Color(0xFFE6B887)),
      _ => ('$rank', const Color(0xFFE9E7E0)),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE6E2D9)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: medal.$2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              medal.$1,
              style: TextStyle(
                fontSize: rank <= 3 ? 21 : 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  'Level ${entry.storeLevel} · ${entry.totalSales} sales',
                  style: const TextStyle(
                    color: Color(0xFF737974),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatNumber(entry.score),
            style: const TextStyle(
              color: Color(0xFF315F4A),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.game, required this.onReplayTutorial});

  final GameController game;
  final VoidCallback onReplayTutorial;

  Future<void> _setMuted(bool value) async {
    game.setMuted(value);
    await SfxManager.instance.setMuted(value);
  }

  Future<void> _reset(BuildContext context) async {
    unawaited(SfxManager.instance.click());
    final loc = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(loc.resetProgress),
        content: Text(loc.resetConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC94355),
            ),
            child: Text(loc.reset),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await game.reset();
    await SfxManager.instance.setMuted(game.muted, playFeedback: false);
    if (context.mounted) {
      Navigator.of(context).pop();
      onReplayTutorial();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 5, 0, 18),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5EE),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_done_rounded, color: Color(0xFF2C8D60)),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.autoSaveOn,
                      style: TextStyle(
                        color: Color(0xFF256A4B),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      loc.autoSaveDesc,
                      style: TextStyle(color: Color(0xFF5B7466), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingsTile(
          icon: game.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          title: loc.soundEffects,
          subtitle: loc.soundEffectsDesc,
          trailing: Switch(
            value: !game.muted,
            onChanged: (enabled) => unawaited(_setMuted(!enabled)),
          ),
        ),
        const SizedBox(height: 9),
        _SettingsTile(
          icon: Icons.school_rounded,
          title: loc.quickTutorial,
          subtitle: loc.replayTutorial,
          trailing: FilledButton(
            onPressed: () {
              unawaited(SfxManager.instance.click());
              Navigator.of(context).pop();
              onReplayTutorial();
            },
            child: Text(loc.replay),
          ),
        ),
        const SizedBox(height: 9),
        _SettingsTile(
          icon: Icons.local_fire_department_rounded,
          title: loc.dailyStreak,
          subtitle:
              '${game.dailyBonus.currentStreak} days · best ${game.dailyBonus.longestStreak}',
          trailing: Text(
            '🔥 ${game.dailyBonus.currentStreak}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => unawaited(_reset(context)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: const Color(0xFFC94355),
            side: const BorderSide(color: Color(0xFFE5A9B1)),
          ),
          icon: const Icon(Icons.restart_alt_rounded),
          label: Text(loc.reset),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E2D9)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE7F2EC),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: const Color(0xFF315F4A)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF747A75),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          trailing,
        ],
      ),
    );
  }
}

class _HistoryChartPainter extends CustomPainter {
  const _HistoryChartPainter(this.samples);

  final List<PerformanceSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) {
      return;
    }
    final values = samples.map((sample) => sample.businessScore).toList();
    final minimum = values.reduce(min).toDouble();
    final maximum = values.reduce(max).toDouble();
    final range = max(1.0, maximum - minimum);
    const inset = 7.0;
    final usableWidth = size.width - inset * 2;
    final usableHeight = size.height - inset * 2;
    final path = Path();
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = inset + usableWidth * index / (values.length - 1);
      final normalized = (values[index] - minimum) / range;
      final y = inset + usableHeight * (1 - normalized);
      final point = Offset(x, y);
      points.add(point);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height - inset)
      ..lineTo(points.first.dx, size.height - inset)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x5538B879), Color(0x0038B879)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF38B879)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final dotPaint = Paint()..color = const Color(0xFF315F4A);
    for (final point in points) {
      canvas.drawCircle(point, 3.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_HistoryChartPainter oldDelegate) =>
      oldDelegate.samples != samples;
}

Color _tierColor(AchievementTier tier) {
  return switch (tier) {
    AchievementTier.bronze => const Color(0xFFC27A46),
    AchievementTier.silver => const Color(0xFF7D91A5),
    AchievementTier.gold => const Color(0xFFE2A91F),
    AchievementTier.platinum => const Color(0xFF8B66D8),
  };
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  final seconds = duration.inSeconds.remainder(60);
  return minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
}

String _formatNumber(int value) {
  final digits = max(0, value).toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
