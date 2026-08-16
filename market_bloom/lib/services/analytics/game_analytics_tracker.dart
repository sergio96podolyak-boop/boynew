import 'package:flutter/widgets.dart';

import '../../game/daily_event_game_controller.dart';
import '../../game/game_controller.dart';
import '../../game/game_models.dart';
import '../cloud_save/cloud_save_status.dart';
import '../cloud_save/cloud_synchronized_game_storage.dart';
import 'analytics_event.dart';
import 'analytics_service.dart';

class GameAnalyticsTracker with WidgetsBindingObserver {
  GameAnalyticsTracker({
    required this.game,
    required this.analytics,
  });

  final GameController game;
  final AnalyticsService analytics;

  final Set<DepartmentType> _departments = <DepartmentType>{};
  final Set<StaffRole> _hiredStaff = <StaffRole>{};
  bool _onboardingComplete = false;
  int _shiftNumber = 0;
  bool _shiftEnded = false;
  String? _dailyEventKey;
  CloudSynchronizedGameStorage? _cloudStorage;
  CloudSaveState? _cloudState;

  void start() {
    _captureInitialState();
    WidgetsBinding.instance.addObserver(this);
    game.addListener(_onGameChanged);
    final storage = game.storage;
    if (storage is CloudSynchronizedGameStorage) {
      _cloudStorage = storage;
      _cloudState = storage.status.state;
      storage.status.addListener(_onCloudStatusChanged);
    }
    analytics.track(
      AnalyticsEventName.appSessionStarted,
      dedupeKey: 'session',
    );
    analytics.track(
      AnalyticsEventName.shiftStarted,
      parameters: <String, Object?>{'shift_number': game.shiftNumber},
      dedupeKey: '${game.shiftNumber}',
    );
    _trackDailyEvent();
  }

  void _captureInitialState() {
    _onboardingComplete = game.onboardingComplete;
    _shiftNumber = game.shiftNumber;
    _shiftEnded = game.pendingShiftSummary != null;
    _departments.addAll(game.unlockedDepartments);
    _hiredStaff.addAll(
      game.staffMembers.where((member) => member.hired).map((member) => member.role),
    );
  }

  void _onGameChanged() {
    if (!_onboardingComplete && game.onboardingComplete) {
      analytics.track(
        AnalyticsEventName.tutorialCompleted,
        dedupeKey: 'completed',
      );
    }
    _onboardingComplete = game.onboardingComplete;

    for (final department in game.unlockedDepartments) {
      if (_departments.add(department)) {
        analytics.track(
          AnalyticsEventName.departmentUnlocked,
          parameters: <String, Object?>{
            'department': department.name,
            'store_level': game.storeLevel,
          },
          dedupeKey: department.name,
        );
      }
    }
    for (final member in game.staffMembers.where((item) => item.hired)) {
      if (_hiredStaff.add(member.role)) {
        analytics.track(
          AnalyticsEventName.staffHired,
          parameters: <String, Object?>{
            'role': member.role.name,
            'store_level': game.storeLevel,
          },
          dedupeKey: member.role.name,
        );
      }
    }

    if (game.shiftNumber != _shiftNumber) {
      _shiftNumber = game.shiftNumber;
      _shiftEnded = false;
      analytics.track(
        AnalyticsEventName.shiftStarted,
        parameters: <String, Object?>{'shift_number': _shiftNumber},
        dedupeKey: '$_shiftNumber',
      );
    }
    final summary = game.pendingShiftSummary;
    if (!_shiftEnded && summary != null) {
      _shiftEnded = true;
      analytics.track(
        AnalyticsEventName.shiftEnded,
        parameters: <String, Object?>{
          'shift_number': summary.shiftNumber,
          'sales': summary.sales,
          'missed_sales': summary.missedSales,
          'net_profit': summary.ledger.netProfit,
        },
        dedupeKey: '${summary.shiftNumber}',
      );
    }
    _trackDailyEvent();
  }

  void _trackDailyEvent() {
    final controller = game;
    if (controller is! DailyEventGameController) return;
    final key = '${controller.dailyEventDateKey}:${controller.dailyEvent.id}';
    if (_dailyEventKey == key) return;
    _dailyEventKey = key;
    analytics.track(
      AnalyticsEventName.dailyEventActivated,
      parameters: <String, Object?>{'event_id': controller.dailyEvent.id},
      dedupeKey: key,
    );
  }

  void _onCloudStatusChanged() {
    final storage = _cloudStorage;
    if (storage == null || storage.status.state == _cloudState) return;
    _cloudState = storage.status.state;
    final event = switch (storage.status.state) {
      CloudSaveState.synced => AnalyticsEventName.cloudSyncSucceeded,
      CloudSaveState.error => AnalyticsEventName.cloudSyncFailed,
      CloudSaveState.conflictResolved =>
        AnalyticsEventName.cloudSyncConflictResolved,
      CloudSaveState.downloaded => AnalyticsEventName.cloudSaveDownloaded,
      CloudSaveState.localOnly => AnalyticsEventName.cloudLocalOnly,
      CloudSaveState.pending || CloudSaveState.syncing => null,
    };
    if (event != null) {
      analytics.track(event);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        analytics.track(AnalyticsEventName.appResumed);
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        analytics.track(AnalyticsEventName.appBackgrounded);
      case AppLifecycleState.detached:
        analytics.track(
          AnalyticsEventName.appSessionEnded,
          dedupeKey: 'session',
        );
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    game.removeListener(_onGameChanged);
    _cloudStorage?.status.removeListener(_onCloudStatusChanged);
  }
}
