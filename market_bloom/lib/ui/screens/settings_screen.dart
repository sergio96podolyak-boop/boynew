import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../game/game_controller.dart';
import '../../services/app_localizations.dart';
import '../../services/app_settings.dart';
import '../../services/sfx/sfx_manager.dart';
import '../theme/po_system.dart';
import '../widgets/management_ui.dart';
import '../widgets/premium_ui.dart';
import '../widgets/pressable_scale.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.settings,
  });

  final GameController controller;
  final AppSettings settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  bool _restoringPurchases = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      if (mounted) setState(() => _version = '1.0.0');
    }
  }

  void _feedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _setSound(bool value) async {
    await widget.settings.setSoundEnabled(value);
    widget.controller.setMuted(!value);
    await SfxManager.instance.setMuted(!value);
    if (!mounted) return;
    _feedback(
      value
          ? _t(
              context,
              'Audio feedback enabled',
              'משוב השמע הופעל',
              'تم تفعيل الصوت',
            )
          : _t(
              context,
              'Audio feedback muted',
              'משוב השמע הושתק',
              'تم كتم الصوت',
            ),
    );
  }

  Future<void> _setControlMode(ControlMode value) async {
    await widget.settings.setControlMode(value);
    if (mounted) {
      _feedback(
        _t(
          context,
          'Control mode updated',
          'מצב השליטה עודכן',
          'تم تحديث وضع التحكم',
        ),
      );
    }
  }

  Future<void> _setLanguage(String value) async {
    await widget.settings.setLanguage(value == 'system' ? null : Locale(value));
    if (mounted) {
      _feedback(
        _t(
          context,
          'Language preference updated',
          'העדפת השפה עודכנה',
          'تم تحديث تفضيل اللغة',
        ),
      );
    }
  }

  Future<void> _setReducedMotion(bool value) async {
    await widget.settings.setReducedMotion(value);
    if (!mounted) return;
    _feedback(
      value
          ? _t(
              context,
              'Reduced motion enabled',
              'תנועה מצומצמת הופעלה',
              'تم تفعيل تقليل الحركة',
            )
          : _t(
              context,
              'Standard motion restored',
              'התנועה הרגילה הוחזרה',
              'تمت استعادة الحركة العادية',
            ),
    );
  }

  Future<void> _restorePurchases() async {
    if (_restoringPurchases || !widget.controller.storePurchasesAvailable) {
      return;
    }
    setState(() => _restoringPurchases = true);
    final restored = await widget.controller.restoreStorePurchases();
    if (!mounted) return;
    setState(() => _restoringPurchases = false);
    final loc = AppLocalizations.of(context);
    _feedback(
      restored ? loc.restorePurchasesSuccess : loc.restorePurchasesNone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ManagementScaffold(
      title: loc.settingsTitle,
      icon: Icons.tune_rounded,
      child: AnimatedBuilder(
        animation: widget.settings,
        builder: (context, _) {
          final settings = widget.settings;
          final controlLabel = _controlLabel(loc, settings.controlMode);
          final languageLabel = _languageLabel(settings, loc);
          final sections = <Widget>[
            _SettingsSection(
              key: const ValueKey('settings-section-audio'),
              icon: Icons.graphic_eq_rounded,
              color: PoMarketPalette.blue,
              title: _t(context, 'Audio', 'שמע', 'الصوت'),
              subtitle: _t(
                context,
                'Control the existing game and interface sounds',
                'שליטה בצלילי המשחק והממשק הקיימים',
                'تحكم في أصوات اللعبة والواجهة الحالية',
              ),
              children: [
                _SwitchSettingTile(
                  key: const ValueKey('settings-sound-toggle'),
                  icon: settings.soundEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: PoMarketPalette.blue,
                  title: loc.soundEffects,
                  description: loc.soundEffectsDesc,
                  value: settings.soundEnabled,
                  onLabel: _t(context, 'Audio on', 'שמע פועל', 'الصوت مفعل'),
                  offLabel: _t(context, 'Muted', 'מושתק', 'مكتوم'),
                  onChanged: _setSound,
                ),
              ],
            ),
            _SettingsSection(
              key: const ValueKey('settings-section-gameplay'),
              icon: Icons.sports_esports_rounded,
              color: PoMarketPalette.mint,
              title: _t(context, 'Gameplay', 'משחקיות', 'أسلوب اللعب'),
              subtitle: _t(
                context,
                'Choose the existing movement mode or replay guidance',
                'בחירת מצב התנועה הקיים או הפעלה חוזרת של ההדרכה',
                'اختر وضع الحركة الحالي أو أعد تشغيل الإرشادات',
              ),
              children: [
                _ChoiceSettingTile<ControlMode>(
                  key: const ValueKey('settings-control-mode'),
                  icon: Icons.touch_app_rounded,
                  color: PoMarketPalette.mint,
                  title: loc.controlMode,
                  description: _t(
                    context,
                    'Select how your character moves around the market.',
                    'בחרו כיצד הדמות נעה ברחבי המרקט.',
                    'اختر كيفية تحرك شخصيتك داخل المتجر.',
                  ),
                  currentLabel: controlLabel,
                  value: settings.controlMode,
                  options: [
                    _ChoiceOption(
                      ControlMode.directTouch,
                      loc.directTouch,
                      Icons.touch_app_rounded,
                    ),
                    _ChoiceOption(
                      ControlMode.joystick,
                      loc.floatingJoystick,
                      Icons.gamepad_rounded,
                    ),
                    _ChoiceOption(
                      ControlMode.leftJoystick,
                      loc.leftHandedJoystick,
                      Icons.swipe_left_alt_rounded,
                    ),
                  ],
                  onChanged: _setControlMode,
                ),
                _ActionSettingTile(
                  key: const ValueKey('settings-replay-tutorial'),
                  icon: Icons.school_rounded,
                  color: PoMarketPalette.gold,
                  title: loc.quickTutorial,
                  description: loc.replayTutorial,
                  status: _t(context, 'Ready', 'מוכן', 'جاهز'),
                  actionLabel: loc.replay,
                  onPressed: () {
                    widget.controller.replayOnboarding();
                    _feedback(
                      _t(
                        context,
                        'Tutorial queued for the market screen',
                        'ההדרכה תוצג במסך המרקט',
                        'سيتم عرض الدليل في شاشة المتجر',
                      ),
                    );
                  },
                ),
              ],
            ),
            _SettingsSection(
              key: const ValueKey('settings-section-preferences'),
              icon: Icons.tune_rounded,
              color: PoMarketPalette.violet,
              title: _t(context, 'Preferences', 'העדפות', 'التفضيلات'),
              subtitle: _t(
                context,
                'Existing language and motion preferences',
                'העדפות השפה והתנועה הקיימות',
                'تفضيلات اللغة والحركة الحالية',
              ),
              children: [
                _ChoiceSettingTile<String>(
                  key: const ValueKey('settings-language'),
                  icon: Icons.language_rounded,
                  color: PoMarketPalette.violet,
                  title: loc.language,
                  description: _t(
                    context,
                    'Choose the language used throughout PoMarket.',
                    'בחרו את השפה שתוצג ברחבי PoMarket.',
                    'اختر اللغة المستخدمة في PoMarket.',
                  ),
                  currentLabel: languageLabel,
                  value: settings.followsSystemLanguage
                      ? 'system'
                      : settings.language?.languageCode ?? 'en',
                  options: [
                    _ChoiceOption(
                      'system',
                      loc.systemDefault,
                      Icons.settings_suggest_rounded,
                    ),
                    _ChoiceOption('en', loc.english, Icons.translate_rounded),
                    _ChoiceOption(
                      'he',
                      loc.hebrew,
                      Icons.format_textdirection_r_to_l_rounded,
                    ),
                    _ChoiceOption(
                      'ar',
                      loc.arabic,
                      Icons.format_textdirection_r_to_l_rounded,
                    ),
                  ],
                  onChanged: _setLanguage,
                ),
                _SwitchSettingTile(
                  key: const ValueKey('settings-reduced-motion-toggle'),
                  icon: Icons.motion_photos_off_rounded,
                  color: PoMarketPalette.violet,
                  title: loc.reducedMotion,
                  description: loc.reducedMotionDesc,
                  value: settings.reducedMotion,
                  onLabel: _t(context, 'Reduced', 'מצומצמת', 'مقلصة'),
                  offLabel: _t(context, 'Standard', 'רגילה', 'عادية'),
                  onChanged: _setReducedMotion,
                ),
              ],
            ),
            _SettingsSection(
              key: const ValueKey('settings-section-data'),
              icon: Icons.storage_rounded,
              color: PoMarketPalette.gold,
              title: _t(
                context,
                'Saves and data',
                'שמירות ונתונים',
                'الحفظ والبيانات',
              ),
              subtitle: _t(
                context,
                'Status and actions already available in the game',
                'סטטוס ופעולות שכבר זמינים במשחק',
                'الحالة والإجراءات المتاحة حالياً في اللعبة',
              ),
              children: [
                _InformationSettingTile(
                  key: const ValueKey('settings-local-save'),
                  icon: Icons.save_rounded,
                  color: PoMarketPalette.gold,
                  title: _t(
                    context,
                    'Game progress',
                    'התקדמות במשחק',
                    'تقدم اللعبة',
                  ),
                  description: _t(
                    context,
                    'Progress is stored by the existing local save system.',
                    'ההתקדמות נשמרת באמצעות מערכת השמירה המקומית הקיימת.',
                    'يتم حفظ التقدم عبر نظام الحفظ المحلي الحالي.',
                  ),
                  status: _t(context, 'Local save', 'שמירה מקומית', 'حفظ محلي'),
                ),
                _ActionSettingTile(
                  key: const ValueKey('settings-restore-purchases'),
                  icon: Icons.restore_rounded,
                  color: PoMarketPalette.gold,
                  title: loc.restorePurchases,
                  description: widget.controller.storePurchasesAvailable
                      ? loc.restorePurchasesDesc
                      : loc.restorePurchasesUnavailable,
                  status: widget.controller.storePurchasesAvailable
                      ? _t(context, 'Available', 'זמין', 'متاح')
                      : _t(context, 'Unavailable', 'לא זמין', 'غير متاح'),
                  actionLabel: _restoringPurchases
                      ? _t(context, 'Restoring…', 'משחזר…', 'جارٍ الاستعادة…')
                      : loc.restorePurchases,
                  onPressed:
                      widget.controller.storePurchasesAvailable &&
                          !_restoringPurchases
                      ? _restorePurchases
                      : null,
                ),
              ],
            ),
            _SettingsSection(
              key: const ValueKey('settings-section-about'),
              icon: Icons.info_outline_rounded,
              color: PoMarketPalette.blue,
              title: loc.about,
              subtitle: _t(
                context,
                'Application information',
                'מידע על האפליקציה',
                'معلومات التطبيق',
              ),
              children: [
                _InformationSettingTile(
                  key: const ValueKey('settings-app-version'),
                  icon: Icons.storefront_rounded,
                  color: PoMarketPalette.blue,
                  title: 'PoMarket',
                  description: _t(
                    context,
                    'Build, stock and grow your mini market.',
                    'בנו, מלאו ופתחו את המרקט הקטן שלכם.',
                    'ابنِ وجهّز وطوّر متجرك الصغير.',
                  ),
                  status: _version.isEmpty
                      ? loc.version
                      : '${loc.version} $_version',
                ),
              ],
            ),
          ];

          return FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Scrollbar(
              child: ListView(
                key: const ValueKey('settings-scroll-view'),
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 28),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: ManagementHero(
                        icon: Icons.tune_rounded,
                        title: loc.settingsTitle,
                        subtitle: _t(
                          context,
                          'Your current PoMarket preferences at a glance',
                          'העדפות PoMarket הנוכחיות שלכם במבט מהיר',
                          'تفضيلات PoMarket الحالية بنظرة سريعة',
                        ),
                        colors: const [Color(0xFF1C3A32), Color(0xFF0C837E)],
                        metrics: [
                          ManagementHeroMetric(
                            icon: settings.soundEnabled
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            label: _t(context, 'Audio', 'שמע', 'الصوت'),
                            value: settings.soundEnabled
                                ? _t(context, 'On', 'פועל', 'مفعل')
                                : _t(context, 'Muted', 'מושתק', 'مكتوم'),
                          ),
                          ManagementHeroMetric(
                            icon: Icons.sports_esports_rounded,
                            label: loc.controlMode,
                            value: controlLabel,
                          ),
                          ManagementHeroMetric(
                            icon: Icons.language_rounded,
                            label: loc.language,
                            value: languageLabel,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < sections.length;
                            index++
                          ) ...[
                            sections[index],
                            if (index != sections.length - 1)
                              const SizedBox(height: 22),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ManagementSectionTitle(
          title: title,
          subtitle: subtitle,
          trailing: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
        ),
        const SizedBox(height: 10),
        ManagementCard(
          accent: color,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1)
                  const Divider(height: 1, color: PoMarketPalette.line),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingIdentity extends StatelessWidget {
  const _SettingIdentity({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, color: color, size: 23),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: PoMarketPalette.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(
                  color: PoMarketPalette.muted,
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingTileLayout extends StatelessWidget {
  const _SettingTileLayout({required this.identity, this.status, this.control});

  final Widget identity;
  final Widget? status;
  final Widget? control;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 600 || textScale > 1.15;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                if (status != null || control != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [?status, ?control],
                  ),
                ],
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              if (status != null) ...[const SizedBox(width: 12), status!],
              if (control != null) ...[const SizedBox(width: 10), control!],
            ],
          );
        },
      ),
    );
  }
}

class _SwitchSettingTile extends StatelessWidget {
  const _SwitchSettingTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.value,
    required this.onLabel,
    required this.offLabel,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final bool value;
  final String onLabel;
  final String offLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = value ? onLabel : offLabel;
    return Semantics(
      container: true,
      label: title,
      hint: '$description. $label',
      child: _SettingTileLayout(
        identity: _SettingIdentity(
          icon: icon,
          color: color,
          title: title,
          description: description,
        ),
        status: ManagementStatusPill(
          label: label,
          color: value ? color : PoMarketPalette.muted,
          icon: value ? Icons.check_circle_rounded : Icons.circle_outlined,
        ),
        control: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
    );
  }
}

class _InformationSettingTile extends StatelessWidget {
  const _InformationSettingTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.status,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title. $description. $status',
      child: _SettingTileLayout(
        identity: _SettingIdentity(
          icon: icon,
          color: color,
          title: title,
          description: description,
        ),
        status: ManagementStatusPill(
          label: status,
          color: color,
          icon: Icons.info_outline_rounded,
        ),
      ),
    );
  }
}

class _ActionSettingTile extends StatelessWidget {
  const _ActionSettingTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.status,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String status;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final statusColor = onPressed == null ? PoMarketPalette.muted : color;
    return Semantics(
      container: true,
      label: title,
      hint: '$description. $status',
      child: _SettingTileLayout(
        identity: _SettingIdentity(
          icon: icon,
          color: color,
          title: title,
          description: description,
        ),
        status: ManagementStatusPill(
          label: status,
          color: statusColor,
          icon: onPressed == null
              ? Icons.block_rounded
              : Icons.check_circle_rounded,
        ),
        control: PressableScale(
          enabled: onPressed != null,
          child: PoBtn(onPressed: onPressed, face: color, label: actionLabel),
        ),
      ),
    );
  }
}

class _ChoiceSettingTile<T> extends StatelessWidget {
  const _ChoiceSettingTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.currentLabel,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String currentLabel;
  final T value;
  final List<_ChoiceOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: title,
      hint: '$description. $currentLabel',
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SettingIdentity(
              icon: icon,
              color: color,
              title: title,
              description: description,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ManagementStatusPill(
                label: currentLabel,
                color: color,
                icon: Icons.check_circle_rounded,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  PressableScale(
                    child: ChoiceChip(
                      avatar: Icon(option.icon, size: 17),
                      label: Text(option.label),
                      selected: value == option.value,
                      onSelected: (_) => onChanged(option.value),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      selectedColor: color.withValues(alpha: 0.18),
                      backgroundColor: PoMarketPalette.canvas,
                      side: BorderSide(
                        color: value == option.value
                            ? color.withValues(alpha: 0.5)
                            : PoMarketPalette.line,
                      ),
                      labelStyle: TextStyle(
                        color: value == option.value
                            ? color
                            : PoMarketPalette.ink,
                        fontWeight: value == option.value
                            ? FontWeight.w900
                            : FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceOption<T> {
  const _ChoiceOption(this.value, this.label, this.icon);

  final T value;
  final String label;
  final IconData icon;
}

String _languageLabel(AppSettings settings, AppLocalizations loc) {
  if (settings.followsSystemLanguage) return loc.systemDefault;
  return switch (settings.language?.languageCode) {
    'he' => loc.hebrew,
    'ar' => loc.arabic,
    _ => loc.english,
  };
}

String _controlLabel(AppLocalizations loc, ControlMode value) =>
    switch (value) {
      ControlMode.directTouch => loc.directTouch,
      ControlMode.joystick => loc.floatingJoystick,
      ControlMode.leftJoystick => loc.leftHandedJoystick,
    };

String _t(BuildContext context, String en, String he, String ar) =>
    switch (Localizations.localeOf(context).languageCode) {
      'he' => he,
      'ar' => ar,
      _ => en,
    };
