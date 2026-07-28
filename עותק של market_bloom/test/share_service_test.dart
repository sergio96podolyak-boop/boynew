import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/services/share_service.dart';

void main() {
  group('ShareService.formatChallengeMessage', () {
    test('creates the PoMarket challenge copy with a grouped score', () {
      expect(
        ShareService.formatChallengeMessage(
          score: 12345,
          url: 'https://pomarket.example/play',
        ),
        'I just reached 12,345 points in PoMarket! Can you beat me? '
        'https://pomarket.example/play',
      );
    });

    test('trims the URL and clamps invalid negative scores', () {
      expect(
        ShareService.formatChallengeMessage(
          score: -20,
          url: '  https://pomarket.example  ',
        ),
        'I just reached 0 points in PoMarket! Can you beat me? '
        'https://pomarket.example',
      );
    });

    test('does not leave trailing whitespace when no URL is available', () {
      expect(
        ShareService.formatChallengeMessage(score: 900, url: ' '),
        'I just reached 900 points in PoMarket! Can you beat me?',
      );
    });
  });
}
