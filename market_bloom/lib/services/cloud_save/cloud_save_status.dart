import 'package:flutter/foundation.dart';

enum CloudSaveState {
  localOnly,
  pending,
  syncing,
  synced,
  downloaded,
  conflictResolved,
  error,
}

class CloudSaveStatus extends ChangeNotifier {
  CloudSaveState _state = CloudSaveState.localOnly;
  DateTime? _lastSyncedAt;
  String? _message;
  bool _remoteAppliedLocally = false;

  CloudSaveState get state => _state;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get message => _message;
  bool get remoteAppliedLocally => _remoteAppliedLocally;
  bool get canRetry => _state == CloudSaveState.error;

  void update(
    CloudSaveState state, {
    DateTime? syncedAt,
    String? message,
    bool remoteAppliedLocally = false,
  }) {
    _state = state;
    _lastSyncedAt = syncedAt ?? _lastSyncedAt;
    _message = message;
    _remoteAppliedLocally = remoteAppliedLocally;
    notifyListeners();
  }
}
