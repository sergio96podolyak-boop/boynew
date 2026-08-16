import '../game_storage.dart';
import 'cloud_save_backend.dart';
import 'cloud_save_status.dart';
import 'cloud_synchronized_game_storage.dart';
import 'player_identity.dart';

CloudSynchronizedGameStorage createCloudGameStorage({
  GameStorage? local,
  CloudSaveStatus? status,
}) {
  const endpoint = String.fromEnvironment('POMARKET_CLOUD_SAVE_ENDPOINT');
  final backend = endpoint.trim().isEmpty
      ? const DisabledCloudSaveBackend()
      : RestCloudSaveBackend(baseUrl: endpoint);
  return CloudSynchronizedGameStorage(
    local: local ?? SharedPreferencesGameStorage(),
    backend: backend,
    identityStore: SharedPreferencesPlayerIdentityStore(),
    metadataStore: SharedPreferencesCloudSyncMetadataStore(),
    status: status,
  );
}
