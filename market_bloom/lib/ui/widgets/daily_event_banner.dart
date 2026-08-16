import 'package:flutter/material.dart';

import '../../game/daily_event_game_controller.dart';
import '../../game/daily_event_models.dart';
import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_settings.dart';
import 'premium_ui.dart';

class DailyEventBannerLayer extends StatelessWidget {
  const DailyEventBannerLayer({
    super.key,
    required this.game,
    required this.settings,
    required this.child,
  });

  final GameController game;
  final AppSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (game is! DailyEventGameController) return child;
    return _DailyEventScope(
      game: game as DailyEventGameController,
      settings: settings,
      child: child,
    );
  }

  static ({DailyEventGameController game, AppSettings settings})? maybeOf(
    BuildContext context,
  ) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DailyEventScope>();
    return scope == null ? null : (game: scope.game, settings: scope.settings);
  }
}

class _DailyEventScope extends InheritedWidget {
  const _DailyEventScope({
    required this.game,
    required this.settings,
    required super.child,
  });

  final DailyEventGameController game;
  final AppSettings settings;

  @override
  bool updateShouldNotify(_DailyEventScope oldWidget) =>
      oldWidget.game != game || oldWidget.settings != settings;
}

class DailyEventBanner extends StatelessWidget {
  const DailyEventBanner({
    super.key,
    required this.game,
    required this.settings,
    required this.compact,
  });

  final DailyEventGameController game;
  final AppSettings settings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: game,
      builder: (context, _) => _DailyEventCard(
        event: game.dailyEvent,
        dateKey: game.dailyEventDateKey,
        compact: compact,
        reducedMotion:
            settings.reducedMotion ||
            MediaQuery.disableAnimationsOf(context) ||
            MediaQuery.accessibleNavigationOf(context),
      ),
    );
  }
}

class _DailyEventCard extends StatelessWidget {
  const _DailyEventCard({
    required this.event,
    required this.dateKey,
    required this.compact,
    required this.reducedMotion,
  });

  final DailyEventDefinition event;
  final String dateKey;
  final bool compact;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final presentation = _DailyEventPresentation.of(
      event,
      Localizations.localeOf(context).languageCode,
    );
    final color = _eventColor(event.type);
    final narrow = MediaQuery.sizeOf(context).width < 380;
    final card = Semantics(
      key: const ValueKey('daily-event-banner'),
      container: true,
      liveRegion: true,
      label:
          '${presentation.title}. ${presentation.description}. ${presentation.effect}',
      child: Container(
        height: compact ? 34 : (narrow ? 51 : 54),
        margin: EdgeInsets.fromLTRB(
          compact ? 8 : 10,
          compact ? 3 : 5,
          compact ? 8 : 10,
          compact ? 3 : 4,
        ),
        padding: EdgeInsetsDirectional.fromSTEB(
          compact ? 8 : 10,
          compact ? 4 : 7,
          compact ? 8 : 10,
          compact ? 4 : 7,
        ),
        decoration: BoxDecoration(
          gradient: compact
              ? null
              : LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: [
                    Color.lerp(const Color(0xFFFFFBF2), color, .08)!,
                    const Color(0xFFFFFCF6),
                  ],
                ),
          color: compact ? const Color(0xFFF8F4E9) : null,
          borderRadius: BorderRadius.circular(compact ? 12 : 17),
          border: Border.all(color: color.withValues(alpha: .25)),
          boxShadow: compact
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x17063D2C),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 24 : 36,
              height: compact ? 24 : 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(compact ? 8 : 12),
              ),
              child: Icon(
                _eventIcon(event.type),
                color: Colors.white,
                size: compact ? 14 : 20,
              ),
            ),
            SizedBox(width: compact ? 7 : 10),
            Expanded(
              // Stacked rather than side-by-side: sharing one line meant the
              // effect text ("Sale value +20% · customers arrive 8% faster")
              // was always clipped mid-sentence.
              child: compact
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          presentation.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PoMarketPalette.ink,
                            fontSize: 10,
                            height: 1.15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          presentation.effect,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 8,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .11),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                'LIVE',
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 7,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .7,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                presentation.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PoMarketPalette.ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (!narrow)
                              Text(
                                dateKey,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                  color: PoMarketPalette.muted,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          narrow
                              ? presentation.effect
                              : '${presentation.description} · ${presentation.effect}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PoMarketPalette.muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
    if (reducedMotion) return card;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .98, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(scale: value, child: child),
      ),
      child: card,
    );
  }
}

class _DailyEventPresentation {
  const _DailyEventPresentation({
    required this.title,
    required this.description,
    required this.effect,
  });

  factory _DailyEventPresentation.of(
    DailyEventDefinition event,
    String languageCode,
  ) {
    if (languageCode == 'he') {
      return switch (event.type) {
        MarketEventType.rainyDay => const _DailyEventPresentation(
          title: 'עומס ביום גשום',
          description: 'יותר שכנים נכנסים והמשלוחים מגיעים מהר יותר.',
          effect: 'לקוחות +12% · משלוחים +15%',
        ),
        MarketEventType.flashSale => const _DailyEventPresentation(
          title: 'מבצע בזק',
          description: 'המוצרים המקודמים נמכרים היום במחיר גבוה יותר.',
          effect: 'ערך מכירה +20% · לקוחות +8%',
        ),
        MarketEventType.inspectorVisit => const _DailyEventPresentation(
          title: 'ביקור מפקח',
          description: 'הספקים תומכים בחנות מסודרת ויעילה.',
          effect: 'הזמנות -15% · מאפייה +10%',
        ),
        MarketEventType.heatwave => const _DailyEventPresentation(
          title: 'גל חום',
          description: 'פחות תנועה ברחוב והאפייה נמשכת זמן רב יותר.',
          effect: 'לקוחות -10% · אפייה +20% זמן',
        ),
        _ => _DailyEventPresentation(
          title: event.title,
          description: event.description,
          effect: event.effectSummary,
        ),
      };
    }
    if (languageCode == 'ar') {
      return switch (event.type) {
        MarketEventType.rainyDay => const _DailyEventPresentation(
          title: 'ازدحام يوم ممطر',
          description: 'يزور المزيد من الجيران وتصل الشحنات أسرع.',
          effect: 'العملاء +12% · التوصيل +15%',
        ),
        MarketEventType.flashSale => const _DailyEventPresentation(
          title: 'تخفيض خاطف',
          description: 'تُباع المنتجات المروجة بقيمة أعلى اليوم.',
          effect: 'قيمة البيع +20% · العملاء +8%',
        ),
        MarketEventType.inspectorVisit => const _DailyEventPresentation(
          title: 'زيارة المفتش',
          description: 'يدعم الموردون المتجر المنظم والفعال.',
          effect: 'الطلبات -15% · المخبز +10%',
        ),
        MarketEventType.heatwave => const _DailyEventPresentation(
          title: 'موجة حر',
          description: 'تقل حركة الزوار ويستغرق الخَبز وقتًا أطول.',
          effect: 'العملاء -10% · الخَبز +20% وقت',
        ),
        _ => _DailyEventPresentation(
          title: event.title,
          description: event.description,
          effect: event.effectSummary,
        ),
      };
    }
    return _DailyEventPresentation(
      title: event.title,
      description: event.description,
      effect: event.effectSummary,
    );
  }

  final String title;
  final String description;
  final String effect;
}

Color _eventColor(MarketEventType type) => switch (type) {
  MarketEventType.rainyDay => PoMarketPalette.blue,
  MarketEventType.flashSale => PoMarketPalette.coral,
  MarketEventType.inspectorVisit => PoMarketPalette.mint,
  MarketEventType.heatwave => PoMarketPalette.gold,
  _ => PoMarketPalette.violet,
};

IconData _eventIcon(MarketEventType type) => switch (type) {
  MarketEventType.rainyDay => Icons.water_drop_rounded,
  MarketEventType.flashSale => Icons.bolt_rounded,
  MarketEventType.inspectorVisit => Icons.fact_check_rounded,
  MarketEventType.heatwave => Icons.wb_sunny_rounded,
  _ => Icons.event_rounded,
};
