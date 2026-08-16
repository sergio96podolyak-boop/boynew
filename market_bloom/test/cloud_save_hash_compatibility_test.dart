import 'package:flutter_test/flutter_test.dart';
import 'package:pomarket/services/cloud_save/cloud_save_models.dart';

void main() {
  test('JS-safe hash preserves the legacy native hash value', () {
    final payload = <String, dynamic>{'b': 'x', 'a': 1};

    expect(stableSaveHash(payload), '4fcc937b86ef6c1d');
  });

  test('existing envelopes with the legacy hash remain readable', () {
    final restored = CloudSaveEnvelope.fromJson(<String, dynamic>{
      'schemaVersion': cloudEnvelopeSchemaVersion,
      'accountId': 'player-existing-account',
      'deviceId': 'device-existing',
      'revision': 4,
      'modifiedAt': '2026-08-14T10:00:00.000Z',
      'contentHash': '4fcc937b86ef6c1d',
      'payload': <String, dynamic>{'b': 'x', 'a': 1},
    });

    expect(restored.contentHash, '4fcc937b86ef6c1d');
    expect(restored.payload, <String, dynamic>{'b': 'x', 'a': 1});
  });
}
