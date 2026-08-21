import 'package:flutter/material.dart';

import '../../game/game_models.dart';
import '../../services/app_localizations.dart';
import 'management_ui.dart';
import 'premium_ui.dart';
import 'pressable_scale.dart';

/// Business-focused presentation for the completed shift accounting snapshot.
///
/// This widget is presentation-only: it never mutates the ledger or coin
/// balance. Payroll and department operating costs display the policy-backed
/// values already settled and recorded in [ShiftLedger].
class ShiftPnlSummary extends StatelessWidget {
  const ShiftPnlSummary({
    super.key,
    required this.summary,
    required this.cashBalance,
    required this.onContinue,
  });

  final ShiftSummary summary;
  final int cashBalance;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final ledger = summary.ledger;
    final netProfit = ledger.netProfit;
    final netPositive = netProfit >= 0;
    final netColor = netPositive ? PoMarketPalette.mint : PoMarketPalette.coral;
    final totalCosts =
        ledger.stockOrderCosts +
        ledger.payroll +
        ledger.departmentOperatingCosts;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Semantics(
        container: true,
        label: _t(
          context,
          'Shift ${summary.shiftNumber} business report. Net profit $netProfit. Cash balance $cashBalance.',
          'דוח עסקי למשמרת ${summary.shiftNumber}. רווח נקי $netProfit. יתרת מזומן $cashBalance.',
          'تقرير أعمال الوردية ${summary.shiftNumber}. صافي الربح $netProfit. الرصيد النقدي $cashBalance.',
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 780,
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: PremiumSurface(
              radius: 28,
              elevation: 20,
              color: PoMarketPalette.canvas,
              borderColor: netColor.withValues(alpha: 0.35),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('shift-pnl-scroll-view'),
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        16,
                        16,
                        12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ManagementHero(
                            key: const ValueKey('shift-pnl-hero'),
                            icon: netPositive
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            title: _t(
                              context,
                              'Net profit ${_signed(netProfit)}',
                              'רווח נקי ${_signed(netProfit)}',
                              'صافي الربح ${_signed(netProfit)}',
                            ),
                            subtitle: _t(
                              context,
                              'Accounting performance only — cash balance remains $cashBalance coins',
                              'מדד חשבונאי בלבד — יתרת המזומן נשארת $cashBalance מטבעות',
                              'أداء محاسبي فقط — يبقى الرصيد النقدي $cashBalance عملة',
                            ),
                            colors: netPositive
                                ? const [Color(0xFF0A8B59), Color(0xFF2FD98F)]
                                : const [Color(0xFF7E1128), Color(0xFFD32A47)],
                            metrics: [
                              ManagementHeroMetric(
                                icon: Icons.account_balance_wallet_rounded,
                                label: _t(
                                  context,
                                  'Cash balance',
                                  'יתרת מזומן',
                                  'الرصيد النقدي',
                                ),
                                value: '$cashBalance',
                              ),
                              ManagementHeroMetric(
                                icon: Icons.point_of_sale_rounded,
                                label: _t(
                                  context,
                                  'Gross sales',
                                  'מכירות ברוטו',
                                  'إجمالي المبيعات',
                                ),
                                value: '${ledger.grossRevenue}',
                              ),
                              ManagementHeroMetric(
                                icon: Icons.receipt_long_rounded,
                                label: _t(
                                  context,
                                  'Recorded costs',
                                  'עלויות שנרשמו',
                                  'التكاليف المسجلة',
                                ),
                                value: '$totalCosts',
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ManagementSectionTitle(
                            title: _t(
                              context,
                              'Revenue vs costs',
                              'הכנסות מול עלויות',
                              'الإيرادات مقابل التكاليف',
                            ),
                            subtitle: _t(
                              context,
                              'Recorded accounting events from this shift',
                              'אירועים חשבונאיים שנרשמו במשמרת הזו',
                              'الأحداث المحاسبية المسجلة لهذه الوردية',
                            ),
                          ),
                          const SizedBox(height: 10),
                          ManagementResponsiveWrap(
                            twoColumnBreakpoint: 620,
                            children: [
                              _ReportCard(
                                key: const ValueKey('shift-pnl-revenue'),
                                title: _t(
                                  context,
                                  'Revenue',
                                  'הכנסות',
                                  'الإيرادات',
                                ),
                                icon: Icons.payments_rounded,
                                color: PoMarketPalette.mint,
                                children: [
                                  ManagementInfoTile(
                                    icon: Icons.point_of_sale_rounded,
                                    label: _t(
                                      context,
                                      'Gross sales',
                                      'מכירות ברוטו',
                                      'إجمالي المبيعات',
                                    ),
                                    value: '${ledger.grossRevenue}',
                                    color: PoMarketPalette.mint,
                                  ),
                                  ManagementInfoTile(
                                    icon: Icons.card_giftcard_rounded,
                                    label: _t(
                                      context,
                                      'Bonuses',
                                      'בונוסים',
                                      'المكافآت',
                                    ),
                                    value: '${ledger.bonuses}',
                                    color: PoMarketPalette.gold,
                                  ),
                                ],
                              ),
                              _ReportCard(
                                key: const ValueKey('shift-pnl-costs'),
                                title: _t(
                                  context,
                                  'Costs',
                                  'עלויות',
                                  'التكاليف',
                                ),
                                icon: Icons.receipt_long_rounded,
                                color: PoMarketPalette.coral,
                                children: [
                                  ManagementInfoTile(
                                    icon: Icons.inventory_2_rounded,
                                    label: _t(
                                      context,
                                      'Stock orders',
                                      'הזמנות מלאי',
                                      'طلبات المخزون',
                                    ),
                                    value: '${ledger.stockOrderCosts}',
                                    color: PoMarketPalette.coral,
                                  ),
                                  _InactiveAwareCostTile(
                                    key: const ValueKey('shift-pnl-payroll'),
                                    icon: Icons.groups_2_rounded,
                                    label: _t(
                                      context,
                                      'Payroll cost',
                                      'עלות שכר',
                                      'تكلفة الرواتب',
                                    ),
                                    value: ledger.payroll,
                                  ),
                                  _InactiveAwareCostTile(
                                    key: const ValueKey(
                                      'shift-pnl-operating-costs',
                                    ),
                                    icon: Icons.store_mall_directory_rounded,
                                    label: _t(
                                      context,
                                      'Department operations',
                                      'תפעול מחלקות',
                                      'تشغيل الأقسام',
                                    ),
                                    value: ledger.departmentOperatingCosts,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ManagementSectionTitle(
                            title: _t(
                              context,
                              'Operational performance',
                              'ביצועים תפעוליים',
                              'الأداء التشغيلي',
                            ),
                          ),
                          const SizedBox(height: 10),
                          ManagementCard(
                            key: const ValueKey('shift-pnl-performance'),
                            accent: PoMarketPalette.blue,
                            child: Wrap(
                              spacing: 9,
                              runSpacing: 9,
                              children: [
                                ManagementInfoTile(
                                  icon: Icons.people_alt_rounded,
                                  label: _t(
                                    context,
                                    'Customers served',
                                    'לקוחות ששורתו',
                                    'العملاء المخدومون',
                                  ),
                                  value: '${summary.sales}',
                                  color: PoMarketPalette.blue,
                                ),
                                ManagementInfoTile(
                                  icon: Icons.person_off_rounded,
                                  label: _t(
                                    context,
                                    'Customers lost',
                                    'לקוחות שאבדו',
                                    'العملاء المفقودون',
                                  ),
                                  value: '${summary.missedSales}',
                                  color: PoMarketPalette.coral,
                                  negative: summary.missedSales > 0,
                                ),
                                ManagementInfoTile(
                                  icon: Icons.money_off_csred_rounded,
                                  label: _t(
                                    context,
                                    'Missed sales estimate',
                                    'אומדן מכירות שהוחמצו',
                                    'تقدير المبيعات الضائعة',
                                  ),
                                  value: '${ledger.missedSalesEstimate}',
                                  color: PoMarketPalette.coral,
                                  negative: ledger.missedSalesEstimate > 0,
                                ),
                                ManagementInfoTile(
                                  icon: Icons.sentiment_satisfied_alt_rounded,
                                  label: _t(
                                    context,
                                    'Satisfaction',
                                    'שביעות רצון',
                                    'الرضا',
                                  ),
                                  value:
                                      '${(summary.satisfaction * 100).round()}%',
                                  color: PoMarketPalette.mint,
                                ),
                                ManagementInfoTile(
                                  icon: Icons.inventory_rounded,
                                  label: _t(
                                    context,
                                    'Stock remaining',
                                    'מלאי שנותר',
                                    'المخزون المتبقي',
                                  ),
                                  value: '${summary.stockRemaining}',
                                  color: PoMarketPalette.gold,
                                ),
                                ManagementInfoTile(
                                  icon: Icons.stars_rounded,
                                  label: loc.shiftXp,
                                  value: '${summary.xp}',
                                  color: PoMarketPalette.violet,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          ManagementSectionTitle(
                            title: _t(
                              context,
                              'Department breakdown',
                              'פירוט לפי מחלקה',
                              'تفصيل الأقسام',
                            ),
                          ),
                          const SizedBox(height: 10),
                          ManagementCard(
                            key: const ValueKey(
                              'shift-pnl-department-breakdown',
                            ),
                            accent: PoMarketPalette.violet,
                            muted: true,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.data_usage_rounded,
                                  color: PoMarketPalette.violet,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _t(
                                          context,
                                          'Per-department shift sales are not tracked yet',
                                          'מכירות לפי מחלקה במשמרת עדיין אינן נמדדות',
                                          'مبيعات الأقسام لكل وردية غير متتبعة بعد',
                                        ),
                                        style: const TextStyle(
                                          color: PoMarketPalette.ink,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _t(
                                          context,
                                          'No values are estimated or invented in this report.',
                                          'הדוח אינו מעריך או ממציא נתונים חסרים.',
                                          'لا يقدّر هذا التقرير بيانات غير موجودة ولا ينشئها.',
                                        ),
                                        style: const TextStyle(
                                          color: PoMarketPalette.muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ManagementStatusPill(
                                  label: _t(
                                    context,
                                    'Not tracked',
                                    'לא נמדד',
                                    'غير متتبع',
                                  ),
                                  color: PoMarketPalette.muted,
                                  icon: Icons.schedule_rounded,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _ShiftInsight(
                            netProfit: netProfit,
                            missedSales: summary.missedSales,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      10,
                      16,
                      16,
                    ),
                    decoration: const BoxDecoration(
                      color: PoMarketPalette.canvas,
                      border: Border(
                        top: BorderSide(color: PoMarketPalette.line),
                      ),
                    ),
                    child: PressableScale(
                      child: FilledButton.icon(
                        key: const ValueKey('shift-pnl-continue'),
                        onPressed: onContinue,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: netColor,
                          foregroundColor: netPositive
                              ? PoMarketPalette.forest
                              : Colors.white,
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(loc.continueShift),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ManagementCard(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: PoMarketPalette.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}

class _InactiveAwareCostTile extends StatelessWidget {
  const _InactiveAwareCostTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: value > 0
          ? '$label $value'
          : '$label 0. ${_t(context, 'Policy not active', 'המדיניות לא פעילה', 'السياسة غير مفعلة')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManagementInfoTile(
            icon: icon,
            label: label,
            value: '$value',
            color: value > 0 ? PoMarketPalette.coral : PoMarketPalette.muted,
            negative: value > 0,
          ),
          if (value == 0) ...[
            const SizedBox(height: 5),
            ManagementStatusPill(
              label: _t(context, 'Not active', 'לא פעיל', 'غير مفعل'),
              color: PoMarketPalette.muted,
              icon: Icons.pause_circle_outline_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

class _ShiftInsight extends StatelessWidget {
  const _ShiftInsight({required this.netProfit, required this.missedSales});

  final int netProfit;
  final int missedSales;

  @override
  Widget build(BuildContext context) {
    final positive = netProfit >= 0;
    final color = positive ? PoMarketPalette.mint : PoMarketPalette.coral;
    final message = !positive
        ? _t(
            context,
            'This shift recorded a loss. Review stock ordering before adding new costs.',
            'המשמרת הסתיימה בהפסד. כדאי לבדוק הזמנות מלאי לפני הוספת עלויות חדשות.',
            'سجلت هذه الوردية خسارة. راجع طلبات المخزون قبل إضافة تكاليف جديدة.',
          )
        : missedSales > 0
        ? _t(
            context,
            'The shift was profitable, but missed customers indicate an operational opportunity.',
            'המשמרת הייתה רווחית, אך לקוחות שאבדו מצביעים על הזדמנות תפעולית.',
            'كانت الوردية مربحة، لكن فقدان العملاء يشير إلى فرصة تشغيلية.',
          )
        : _t(
            context,
            'Profitable shift with no recorded customer losses.',
            'משמרת רווחית ללא אובדן לקוחות שנרשם.',
            'وردية مربحة دون خسائر عملاء مسجلة.',
          );

    return ManagementCard(
      key: const ValueKey('shift-pnl-insight'),
      accent: color,
      highlighted: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            positive ? Icons.lightbulb_rounded : Icons.warning_amber_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: PoMarketPalette.ink,
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _signed(int value) => value > 0 ? '+$value' : '$value';

String _t(BuildContext context, String en, String he, String ar) =>
    switch (Localizations.localeOf(context).languageCode) {
      'he' => he,
      'ar' => ar,
      _ => en,
    };
