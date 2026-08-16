import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finish full bleed presentation cleanup', () {
    final shellFile = File('lib/ui/app_shell.dart');
    var shell = shellFile.readAsStringSync();
    shell = shell.replaceFirst(
      'minimum: const EdgeInsetsDirectional.fromSTEB(3, 5, 5, 6),',
      'minimum: const EdgeInsets.fromLTRB(3, 5, 5, 6),',
    );
    shellFile.writeAsStringSync(shell);

    final gameFile = File('lib/ui/game_screen.dart');
    var game = gameFile.readAsStringSync();
    game = game.replaceFirst(
      '  Future<void> _showRewardCenter() {',
      '  // Retained for compatibility with legacy deep links.\n  // ignore: unused_element\n  Future<void> _showRewardCenter() {',
    );
    game = game.replaceFirst(
      '  Future<void> _showUpgrades() {',
      '  // Retained for compatibility with legacy deep links.\n  // ignore: unused_element\n  Future<void> _showUpgrades() {',
    );
    game = game.replaceFirst(
      '  Future<void> _showMoneyShop() {',
      '  // Retained for compatibility with legacy deep links.\n  // ignore: unused_element\n  Future<void> _showMoneyShop() {',
    );
    game = game.replaceFirst(
      'class _ControlDeck extends StatelessWidget {',
      '// Legacy implementation retained temporarily; it is no longer mounted.\n// ignore: unused_element\nclass _ControlDeck extends StatelessWidget {',
    );
    gameFile.writeAsStringSync(game);
  });
}
