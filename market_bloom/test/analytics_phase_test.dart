import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/game/daily_event_game_controller.dart';
import 'package:pomarket/game/game_models.dart';
import 'package:pomarket/services/analytics/analytics_backend.dart';
import 'package:pomarket/services/analytics/analytics_event.dart';
import 'package:pomarket/services/analytics/analytics_monetization_service.dart';
import 'package:pomarket/services/analytics/analytics_service.dart';
import 'package:pomarket/services/analytics/game_analytics_tracker.dart';
import 'package:pomarket/services/game_storage.dart';
import 'package:pomarket/services/monetization_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('consent gate prevents analytics collection', () async {
    final backend = _MemoryAnalyticsBackend();
    final analytics = AnalyticsService(
      backend: backend,
      hasConsent: () => false,
    );

    analytics.track(AnalyticsEventName.appSessionStarted);
    await _flush();

    expect(backend.events, isEmpty);
  });

  test('events use deterministic names and remove sensitive parameters', () async {
    final backend = _MemoryAnalyticsBackend();
    final analytics = AnalyticsService(
      backend: backend,
      hasConsent: () => true,
    );

    analytics.track(
      AnalyticsEventName.purchaseCompleted,
      parameters: const <String, Object?>{
        'product': 'coinPack',
        'verified': true,
        'transactionId': 'must-not-leak',
        'serverVerificationData': 'must-not-leak',
        'savePayload': 'must-not-leak',
      },
    );
    await _flush();

    expect(backend.events.single.name.wireName, 'purchase_completed');
    expect(backend.events.single.parameters, <String, Object>{
      'product': 'coinPack',
      'verified': true,
    });
  });

  test('analytics backend failures are contained', () async {
    final analytics = AnalyticsService(
      backend: _ThrowingAnalyticsBackend(),
      hasConsent: () => true,
    );

    expect(
      () => analytics.track(AnalyticsEventName.errorRecorded),
      returnsNormally,
    );
    await _flush();
  });

  test('dedupe keys prevent duplicate event delivery', () async {
    final backend = _MemoryAnalyticsBackend();
    final analytics = AnalyticsService(
      backend: backend,
      hasConsent: () => true,
    );

    analytics.track(AnalyticsEventName.tutorialCompleted, dedupeKey: 'done');
    analytics.track(AnalyticsEventName.tutorialCompleted, dedupeKey: 'done');
    await _flush();

    expect(backend.events, hasLength(1));
  });

  test('game tracker maps core progression transitions once', () async {
    final backend = _MemoryAnalyticsBackend();
    final analytics = AnalyticsService(
      backend: backend,
      hasConsent: () => true,
    );
    final game = DailyEventGameController(
      storage: MemoryGameStorage(),
      monetization: PreviewMonetizationService(),
      now: () => DateTime(2026, 8, 14, 12),
    );
    await game.initialize();
    final tracker = GameAnalyticsTracker(game: game, analytics: analytics)
      ..start();

    game.completeOnboarding();
    game.debugSetProgress(sales: 16);
    game.coins = 1000;
    game.hireStaff(game.staffMembers.first.role);
    game.pendingShiftSummary = ShiftSummary(
      shiftNumber: game.shiftNumber,
      sales: 3,
      revenue: 24,
      missedSales: 1,
      satisfaction: .9,
      xp: 8,
      stockRemaining: 4,
      ledger: ShiftLedger(grossRevenue: 24),
    );
    game.notifyListeners();
    await _flush();

    final names = backend.events.map((event) => event.name).toList();
    expect(names, contains(AnalyticsEventName.appSessionStarted));
    expect(names, contains(AnalyticsEventName.shiftStarted));
    expect(names, contains(AnalyticsEventName.dailyEventActivated));
    expect(names, contains(AnalyticsEventName.tutorialCompleted));
    expect(names, contains(AnalyticsEventName.departmentUnlocked));
    expect(names, contains(AnalyticsEventName.staffHired));
    expect(names, contains(AnalyticsEventName.shiftEnded));
    expect(
      names.where((name) => name == AnalyticsEventName.tutorialCompleted),
      hasLength(1),
    );
    tracker.dispose();
  });

  test('purchase decorator maps purchase and restore outcomes', () async {
    final backend = _MemoryAnalyticsBackend();
    final analytics = AnalyticsService(
      backend: backend,
      hasConsent: () => true,
    );
    final service = AnalyticsMonetizationService(
      delegate: _FakeMonetizationService(),
      analytics: analytics,
    );

    await service.purchase(StoreProduct.coinPack);
    await service.restorePurchases();
    await _flush();

    expect(
      backend.events.map((event) => event.name),
      containsAll(<AnalyticsEventName>[
        AnalyticsEventName.purchaseCompleted,
        AnalyticsEventName.purchaseRestoreCompleted,
      ]),
    );
    expect(
      backend.events.expand((event) => event.parameters.keys),
      isNot(contains('transactionId')),
    );
  });
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 10));

class _MemoryAnalyticsBackend implements AnalyticsBackend {
  final List<AnalyticsEvent> events = <AnalyticsEvent>[];

  @override
  bool get isAvailable => true;

  @override
  Future<void> send(AnalyticsEvent event) async => events.add(event);
}

class _ThrowingAnalyticsBackend implements AnalyticsBackend {
  @override
  bool get isAvailable => true;

  @override
  Future<void> send(AnalyticsEvent event) async {
    throw StateError('offline');
  }
}

class _FakeMonetizationService implements MonetizationService {
  @override
  bool get interstitialAdsAvailable => false;
  @override
  bool get isPreview => false;
  @override
  bool get rewardedAdsAvailable => false;
  @override
  bool get storeAvailable => true;
  @override
  void dispose() {}
  @override
  Future<void> initialize() async {}
  @override
  String? priceFor(StoreProduct product) => r'$0.99';
  @override
  Future<StorePurchaseResult> purchase(StoreProduct product) async =>
      StorePurchaseResult(
        product: product,
        state: PurchaseState.purchased,
        transactionId: 'private-transaction',
        verified: true,
      );
  @override
  Future<List<StorePurchaseResult>> restorePurchases() async =>
      const <StorePurchaseResult>[
        StorePurchaseResult(
          product: StoreProduct.noAds,
          state: PurchaseState.restored,
          transactionId: 'private-restore',
          verified: true,
        ),
      ];
  @override
  Future<bool> showInterstitial(InterstitialPlacement placement) async => false;
  @override
  Future<bool> showRewardedAd(RewardPlacement placement) async => false;
}
