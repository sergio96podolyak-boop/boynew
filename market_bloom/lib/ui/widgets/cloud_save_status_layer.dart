import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../game/game_controller.dart';
import '../../services/app_settings.dart';
import '../../services/cloud_save/cloud_save_status.dart';
import '../../services/cloud_save/cloud_synchronized_game_storage.dart';
import 'premium_ui.dart';

class CloudSaveStatusLayer extends StatelessWidget {
  const CloudSaveStatusLayer({
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
    final storage = game.storage;
    if (storage is! CloudSynchronizedGameStorage) return child;
    return AnimatedBuilder(
      animation: storage.status,
      child: child,
      builder: (context, child) {
        final presentation = _CloudStatusPresentation.of(
          storage.status,
          Localizations.localeOf(context).languageCode,
        );
        final reducedMotion =
            settings.reducedMotion ||
            MediaQuery.disableAnimationsOf(context) ||
            MediaQuery.accessibleNavigationOf(context);
        final statusButton = Tooltip(
          message: presentation.longLabel,
          child: Semantics(
            button: true,
            label: presentation.semanticLabel,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const ValueKey('cloud-save-status-chip'),
                borderRadius: BorderRadius.circular(99),
                onTap: () => unawaited(
                  _showCloudDialog(context, storage, presentation),
                ),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xD90A4937),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: presentation.color.withValues(alpha: .48),
                    ),
                  ),
                  child: Icon(
                    presentation.icon,
                    color: presentation.color,
                    size: 16,
                  ),
                ),
              ),
            ),
          ),
        );
        return Stack(
          children: [
            Positioned.fill(child: child!),
            PositionedDirectional(
              top: MediaQuery.paddingOf(context).top + 8,
              end: 8,
              child: reducedMotion
                  ? statusButton
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: KeyedSubtree(
                        key: ValueKey(storage.status.state),
                        child: statusButton,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCloudDialog(
    BuildContext context,
    CloudSynchronizedGameStorage storage,
    _CloudStatusPresentation presentation,
  ) async {
    final identity = await storage.identity;
    if (!context.mounted) return;
    final language = Localizations.localeOf(context).languageCode;
    final recoveryController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(presentation.icon, color: presentation.color),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _t(language, 'Cloud saves', 'שמירות ענן', 'الحفظ السحابي'),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(presentation.longLabel),
              const SizedBox(height: 8),
              SelectableText(
                '${_t(language, 'Account', 'חשבון', 'الحساب')}: ${identity.accountId}',
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 11),
              ),
              if (storage.status.remoteAppliedLocally) ...[
                const SizedBox(height: 10),
                Text(
                  _t(
                    language,
                    'Cloud progress was downloaded. Reopen PoMarket to apply it.',
                    'התקדמות מהענן הורדה. יש לפתוח מחדש את PoMarket כדי להחיל אותה.',
                    'تم تنزيل التقدم السحابي. أعد فتح PoMarket لتطبيقه.',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: recoveryController,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: _t(
                    language,
                    'Recovery code from another device',
                    'קוד שחזור ממכשיר אחר',
                    'رمز الاسترداد من جهاز آخر',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: await storage.recoveryCode),
              );
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      _t(
                        language,
                        'Recovery code copied',
                        'קוד השחזור הועתק',
                        'تم نسخ رمز الاسترداد',
                      ),
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: Text(_t(language, 'Copy code', 'העתקת קוד', 'نسخ الرمز')),
          ),
          TextButton(
            onPressed: storage.status.canRetry
                ? () => unawaited(storage.syncNow())
                : null,
            child: Text(_t(language, 'Retry', 'ניסיון חוזר', 'إعادة المحاولة')),
          ),
          FilledButton(
            onPressed: () async {
              final code = recoveryController.text.trim();
              if (code.isEmpty) return;
              try {
                await storage.recoverWithCode(code);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              } catch (_) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        _t(
                          language,
                          'Invalid recovery code',
                          'קוד השחזור אינו תקין',
                          'رمز الاسترداد غير صالح',
                        ),
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(_t(language, 'Recover', 'שחזור', 'استرداد')),
          ),
        ],
      ),
    );
    recoveryController.dispose();
  }
}

class _CloudStatusPresentation {
  const _CloudStatusPresentation({
    required this.shortLabel,
    required this.longLabel,
    required this.semanticLabel,
    required this.icon,
    required this.color,
  });

  factory _CloudStatusPresentation.of(
    CloudSaveStatus status,
    String language,
  ) {
    final label = switch (status.state) {
      CloudSaveState.localOnly =>
        _t(language, 'Saved on device', 'נשמר במכשיר', 'محفوظ على الجهاز'),
      CloudSaveState.pending =>
        _t(language, 'Waiting to sync', 'ממתין לסנכרון', 'بانتظار المزامنة'),
      CloudSaveState.syncing =>
        _t(language, 'Syncing', 'מסנכרן', 'جارٍ المزامنة'),
      CloudSaveState.synced =>
        _t(language, 'Progress synced', 'ההתקדמות סונכרנה', 'تمت مزامنة التقدم'),
      CloudSaveState.downloaded =>
        _t(language, 'Progress restored', 'ההתקדמות שוחזרה', 'تمت استعادة التقدم'),
      CloudSaveState.conflictResolved =>
        _t(language, 'Progress updated', 'ההתקדמות עודכנה', 'تم تحديث التقدم'),
      CloudSaveState.error =>
        _t(language, 'Sync needs attention', 'הסנכרון דורש בדיקה', 'تحتاج المزامنة إلى مراجعة'),
    };
    final color = switch (status.state) {
      CloudSaveState.error => PoMarketPalette.coral,
      CloudSaveState.localOnly => PoMarketPalette.gold,
      CloudSaveState.pending || CloudSaveState.syncing => PoMarketPalette.blue,
      _ => PoMarketPalette.mint,
    };
    final icon = switch (status.state) {
      CloudSaveState.error => Icons.cloud_off_rounded,
      CloudSaveState.localOnly => Icons.save_rounded,
      CloudSaveState.pending => Icons.cloud_queue_rounded,
      CloudSaveState.syncing => Icons.cloud_sync_rounded,
      CloudSaveState.downloaded => Icons.cloud_download_rounded,
      CloudSaveState.conflictResolved => Icons.rule_rounded,
      CloudSaveState.synced => Icons.cloud_done_rounded,
    };
    final detail = status.message ?? label;
    return _CloudStatusPresentation(
      shortLabel: label,
      longLabel: detail,
      semanticLabel: '$label. $detail',
      icon: icon,
      color: color,
    );
  }

  final String shortLabel;
  final String longLabel;
  final String semanticLabel;
  final IconData icon;
  final Color color;
}

String _t(String language, String en, String he, String ar) => switch (language) {
  'he' => he,
  'ar' => ar,
  _ => en,
};
