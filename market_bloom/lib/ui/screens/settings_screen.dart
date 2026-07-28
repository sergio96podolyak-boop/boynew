import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../game/game_controller.dart';
import '../../services/app_localizations.dart';
import '../../services/app_settings.dart';
import '../../services/sfx/sfx_manager.dart';
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

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _version = info.version);
    } catch (_) {
      setState(() => _version = '1.0.0');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final game = widget.controller;
    final settings = widget.settings;

    return Scaffold(
      appBar: AppBar(title: Text(loc.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Language
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.language,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _LanguageChip(
                        label: loc.systemDefault,
                        selected: settings.language == null,
                        onTap: () => settings.setLanguage(null),
                      ),
                      _LanguageChip(
                        label: loc.english,
                        selected: settings.language?.languageCode == 'en',
                        onTap: () => settings.setLanguage(const Locale('en')),
                      ),
                      _LanguageChip(
                        label: loc.hebrew,
                        selected: settings.language?.languageCode == 'he',
                        onTap: () => settings.setLanguage(const Locale('he')),
                      ),
                      _LanguageChip(
                        label: loc.arabic,
                        selected: settings.language?.languageCode == 'ar',
                        onTap: () => settings.setLanguage(const Locale('ar')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Sound
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  settings.soundEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(
                loc.soundEffects,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                loc.soundEffectsDesc,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              trailing: Switch(
                value: settings.soundEnabled,
                onChanged: (value) async {
                  await settings.setSoundEnabled(value);
                  game.setMuted(!value);
                  await SfxManager.instance.setMuted(!value);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Reduced motion
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.visibility_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(
                loc.reducedMotion,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                loc.reducedMotionDesc,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              trailing: Switch(
                value: settings.reducedMotion,
                onChanged: (value) => settings.setReducedMotion(value),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Control mode
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.controlMode,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _ControlModeChip(
                        label: loc.directTouch,
                        mode: ControlMode.directTouch,
                        selected:
                            settings.controlMode == ControlMode.directTouch,
                        onTap: () =>
                            settings.setControlMode(ControlMode.directTouch),
                      ),
                      _ControlModeChip(
                        label: loc.floatingJoystick,
                        mode: ControlMode.joystick,
                        selected: settings.controlMode == ControlMode.joystick,
                        onTap: () =>
                            settings.setControlMode(ControlMode.joystick),
                      ),
                      _ControlModeChip(
                        label: loc.leftHandedJoystick,
                        mode: ControlMode.leftJoystick,
                        selected:
                            settings.controlMode == ControlMode.leftJoystick,
                        onTap: () =>
                            settings.setControlMode(ControlMode.leftJoystick),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Restore purchases
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.restore_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(
                loc.restorePurchases,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                game.storePurchasesAvailable
                    ? 'Restore previous purchases'
                    : loc.restorePurchasesUnavailable,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              trailing: SizedBox(
                width: 120,
                child: PressableScale(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    onPressed: game.storePurchasesAvailable
                        ? () async {
                            final restored = await game.monetization
                                .restorePurchases();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  restored
                                      ? loc.restorePurchasesSuccess
                                      : loc.restorePurchasesNone,
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        : null,
                    child: Text(loc.restorePurchases),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // About
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.about,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'PoMarket',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${loc.version} $_version',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlModeChip extends StatelessWidget {
  const _ControlModeChip({
    required this.label,
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final ControlMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        selectedColor: Theme.of(context).colorScheme.primaryContainer,
        labelStyle: TextStyle(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        selectedColor: Theme.of(context).colorScheme.primaryContainer,
        labelStyle: TextStyle(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );
  }
}
