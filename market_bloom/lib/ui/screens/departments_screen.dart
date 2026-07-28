import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../../services/app_localizations.dart';

class DepartmentsScreen extends StatelessWidget {
  const DepartmentsScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(loc.departmentsTitle)),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final definition in DepartmentCatalog.all)
              _DepartmentCard(
                definition: definition,
                controller: controller,
                loc: loc,
              ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  const _DepartmentCard({
    required this.definition,
    required this.controller,
    required this.loc,
  });

  final DepartmentDefinition definition;
  final GameController controller;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final state = controller.departments.firstWhere(
      (d) => d.type == definition.type,
      orElse: () => DepartmentState(type: definition.type),
    );
    final unlocked = state.unlocked;
    final canUnlock =
        !unlocked &&
        controller.storeLevel >= definition.unlockLevel &&
        controller.coins >= definition.unlockCost;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: unlocked
                    ? definition.color
                    : Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                definition.icon,
                color: unlocked ? Colors.white : Colors.grey,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _nameFor(definition.type, loc),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: unlocked
                          ? null
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    definition.description,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    unlocked
                        ? '${loc.unlocked} · ${loc.level} ${state.level}'
                        : loc.unlockAtLevel.replaceFirst(
                            '{level}',
                            definition.unlockLevel.toString(),
                          ),
                    style: TextStyle(
                      color: unlocked
                          ? Colors.green
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (!unlocked && canUnlock)
              FilledButton(
                onPressed: () {
                  // Department unlock is a future feature; show locked state.
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${loc.unlockCost.replaceFirst("{cost}", definition.unlockCost.toString())} — ${loc.locked}',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text('${definition.unlockCost}'),
              ),
            if (!unlocked && !canUnlock)
              const Icon(Icons.lock_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  String _nameFor(DepartmentType type, AppLocalizations loc) {
    return switch (type) {
      DepartmentType.generalGoods => loc.departmentGeneralGoods,
      DepartmentType.bakery => loc.departmentBakery,
      DepartmentType.produce => loc.departmentProduce,
      DepartmentType.refrigerated => loc.departmentRefrigerated,
      DepartmentType.beauty => loc.departmentBeauty,
      DepartmentType.electronics => loc.departmentElectronics,
    };
  }
}
