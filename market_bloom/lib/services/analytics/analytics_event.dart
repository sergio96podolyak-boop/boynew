enum AnalyticsEventName {
  appSessionStarted('app_session_started'),
  appSessionEnded('app_session_ended'),
  appBackgrounded('app_backgrounded'),
  appResumed('app_resumed'),
  tutorialCompleted('tutorial_completed'),
  departmentUnlocked('department_unlocked'),
  staffHired('staff_hired'),
  purchaseCompleted('purchase_completed'),
  purchaseFailed('purchase_failed'),
  purchasePending('purchase_pending'),
  purchaseCancelled('purchase_cancelled'),
  purchaseRestoreCompleted('purchase_restore_completed'),
  purchaseRestoreFailed('purchase_restore_failed'),
  shiftStarted('shift_started'),
  shiftEnded('shift_ended'),
  dailyEventActivated('daily_event_activated'),
  cloudSyncSucceeded('cloud_sync_succeeded'),
  cloudSyncFailed('cloud_sync_failed'),
  cloudSyncConflictResolved('cloud_sync_conflict_resolved'),
  cloudSaveDownloaded('cloud_save_downloaded'),
  cloudLocalOnly('cloud_local_only'),
  errorRecorded('error_recorded');

  const AnalyticsEventName(this.wireName);
  final String wireName;
}

class AnalyticsEvent {
  const AnalyticsEvent({
    required this.name,
    this.parameters = const <String, Object>{},
  });

  final AnalyticsEventName name;
  final Map<String, Object> parameters;
}
