import 'package:flutter/material.dart';

import '../../services/app_settings.dart';

class PrivacyConsentLayer extends StatelessWidget {
  const PrivacyConsentLayer({
    super.key,
    required this.settings,
    required this.child,
  });

  final AppSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      child: child,
      builder: (context, child) {
        if (!settings.isLoaded || !settings.requiresPrivacyConsent) {
          return child!;
        }
        final reduced =
            settings.reducedMotion || MediaQuery.disableAnimationsOf(context);
        return Stack(
          children: [
            Positioned.fill(child: child!),
            const Positioned.fill(
              child: ModalBarrier(
                dismissible: false,
                color: Color(0x99031E17),
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: AnimatedScale(
                      scale: 1,
                      duration: reduced
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: PrivacyConsentCard(
                          key: const ValueKey(
                            'privacy-consent-first-launch',
                          ),
                          settings: settings,
                          requiredDecision: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PrivacySettingsLauncher extends StatelessWidget {
  const PrivacySettingsLauncher({
    super.key,
    required this.settings,
    required this.child,
  });

  final AppSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        PositionedDirectional(
          end: 16,
          bottom: 16,
          child: SafeArea(
            child: Semantics(
              button: true,
              label: _t(
                context,
                'Privacy settings',
                'הגדרות פרטיות',
                'إعدادات الخصوصية',
              ),
              child: FilledButton.icon(
                key: const ValueKey('open-privacy-settings'),
                onPressed: () =>
                    showPrivacySettingsDialog(context, settings),
                icon: const Icon(Icons.privacy_tip_outlined),
                label: Text(
                  _t(context, 'Privacy', 'פרטיות', 'الخصوصية'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showPrivacySettingsDialog(
  BuildContext context,
  AppSettings settings,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: PrivacyConsentCard(settings: settings, requiredDecision: false),
    ),
  ),
);

class PrivacyConsentCard extends StatefulWidget {
  const PrivacyConsentCard({
    super.key,
    required this.settings,
    required this.requiredDecision,
  });

  final AppSettings settings;
  final bool requiredDecision;

  @override
  State<PrivacyConsentCard> createState() => _PrivacyConsentCardState();
}

class _PrivacyConsentCardState extends State<PrivacyConsentCard> {
  late bool _analytics;
  late bool _crashReporting;
  late bool _ads;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final consent = widget.settings.privacyConsent;
    _analytics = consent.analyticsEnabled;
    _crashReporting = consent.crashReportingEnabled;
    _ads = consent.adsEnabled;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.settings.setPrivacyChoices(
      analytics: _analytics,
      crashReporting: _crashReporting,
      ads: _ads,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!widget.requiredDecision) Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.settings.acceptAllPrivacy();
    if (mounted && !widget.requiredDecision) Navigator.of(context).pop();
  }

  Future<void> _reject() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.settings.rejectAllPrivacy();
    if (mounted && !widget.requiredDecision) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const privacyNotice = String.fromEnvironment(
      'POMARKET_PRIVACY_POLICY_URL',
    );
    final media = MediaQuery.of(context);
    final cardHeight = (media.size.height - media.padding.vertical - 32)
        .clamp(280.0, 680.0);
    return Material(
      color: const Color(0xFFFFFCF5),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: cardHeight,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: _t(
            context,
            'Privacy choices',
            'בחירות פרטיות',
            'خيارات الخصوصية',
          ),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.privacy_tip_rounded,
                        size: 44,
                        color: Color(0xFF087A58),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _t(
                          context,
                          'Privacy choices',
                          'בחירות פרטיות',
                          'خيارات الخصوصية',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'Choose whether optional diagnostics and ads may run. Core offline play works with every optional choice turned off.',
                          'בחרו אם לאפשר אבחון ופרסומות אופציונליים. המשחק הבסיסי במצב לא מקוון פועל גם כאשר כל האפשרויות כבויות.',
                          'اختر ما إذا كنت تريد السماح بالتشخيصات والإعلانات الاختيارية. تعمل اللعبة الأساسية دون اتصال حتى عند إيقاف جميع الخيارات.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      _ConsentSwitch(
                        key: const ValueKey('privacy-analytics-toggle'),
                        title: _t(
                          context,
                          'Usage analytics',
                          'ניתוח שימוש',
                          'تحليلات الاستخدام',
                        ),
                        description: _t(
                          context,
                          'Share limited, non-sensitive product events.',
                          'שיתוף אירועי מוצר מוגבלים וללא מידע רגיש.',
                          'مشاركة أحداث محدودة وغير حساسة عن استخدام المنتج.',
                        ),
                        value: _analytics,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _analytics = value),
                      ),
                      _ConsentSwitch(
                        key: const ValueKey('privacy-crash-toggle'),
                        title: _t(
                          context,
                          'Crash diagnostics',
                          'אבחון קריסות',
                          'تشخيص الأعطال',
                        ),
                        description: _t(
                          context,
                          'Send sanitized error types and stack traces.',
                          'שליחת סוגי שגיאות ונתיבי מחסנית לאחר סינון.',
                          'إرسال أنواع أخطاء ومسارات مكدس بعد تنقيتها.',
                        ),
                        value: _crashReporting,
                        onChanged: _saving
                            ? null
                            : (value) =>
                                  setState(() => _crashReporting = value),
                      ),
                      _ConsentSwitch(
                        key: const ValueKey('privacy-ads-toggle'),
                        title: _t(
                          context,
                          'Optional ads',
                          'פרסומות אופציונליות',
                          'الإعلانات الاختيارية',
                        ),
                        description: _t(
                          context,
                          'Allow optional rewarded and interstitial ad services.',
                          'מתן אפשרות לשירותי פרסום מתוגמל ובין-שלבי.',
                          'السماح بخدمات الإعلانات الاختيارية والمكافآت.',
                        ),
                        value: _ads,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _ads = value),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        privacyNotice.isEmpty
                            ? _t(
                                context,
                                'Publisher privacy-notice link is not configured in this build.',
                                'קישור להודעת הפרטיות של המפרסם אינו מוגדר בגרסה זו.',
                                'رابط إشعار الخصوصية الخاص بالناشر غير مهيأ في هذا الإصدار.',
                              )
                            : privacyNotice,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFCF5),
                  border: Border(
                    top: BorderSide(color: Color(0x1F087A58)),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('privacy-reject-all'),
                        onPressed: _saving ? null : _reject,
                        child: Text(
                          _t(
                            context,
                            'Reject optional',
                            'דחיית האפשרויות',
                            'رفض الاختياري',
                          ),
                        ),
                      ),
                      OutlinedButton(
                        key: const ValueKey('privacy-save-choices'),
                        onPressed: _saving ? null : _save,
                        child: Text(
                          _t(
                            context,
                            'Save choices',
                            'שמירת בחירות',
                            'حفظ الخيارات',
                          ),
                        ),
                      ),
                      FilledButton(
                        key: const ValueKey('privacy-accept-all'),
                        onPressed: _saving ? null : _accept,
                        child: Text(
                          _t(
                            context,
                            'Accept optional',
                            'אישור האפשרויות',
                            'قبول الاختياري',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsentSwitch extends StatelessWidget {
  const _ConsentSwitch({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: title,
      hint: description,
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(description),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

String _t(BuildContext context, String en, String he, String ar) =>
    switch (Localizations.localeOf(context).languageCode) {
      'he' => he,
      'ar' => ar,
      _ => en,
    };
