import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const assets = <String>[
    'assets/audio/sfx/ui/sfx_ui_click_v01.wav',
    'assets/audio/sfx/ui/sfx_ui_success_v01.wav',
    'assets/audio/sfx/progression/sfx_progress_milestone_v01.wav',
    'assets/audio/sfx/ui/sfx_ui_error_v01.wav',
    'assets/audio/sfx/inventory/sfx_inventory_pickup_v01.wav',
    'assets/audio/sfx/inventory/sfx_inventory_shelf_place_v01.wav',
    'assets/audio/sfx/checkout/sfx_checkout_scan_v01.wav',
    'assets/audio/sfx/checkout/sfx_checkout_payment_complete_v01.wav',
    'assets/audio/sfx/customers/sfx_customer_warning_v01.wav',
    'assets/audio/sfx/customers/sfx_customer_leave_v01.wav',
    'assets/audio/sfx/delivery/sfx_delivery_arrived_v01.wav',
    'assets/audio/sfx/bakery/sfx_bakery_ready_v01.wav',
    'assets/audio/sfx/checkout/sfx_checkout_register_open_v01.wav',
    'assets/audio/sfx/checkout/sfx_checkout_register_close_v01.wav',
    'assets/audio/ambience/ambience_shop_day_loop_v01.mp3',
    'assets/audio/music/music_market_open_loop_v01.mp3',
    'assets/audio/music/music_market_rush_loop_v01.mp3',
  ];

  test('all 17 MVP audio files are bundled and have valid signatures', () async {
    expect(assets, hasLength(17));
    for (final path in assets) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(44), reason: path);
      final bytes = data.buffer.asUint8List();
      if (path.endsWith('.wav')) {
        expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF', reason: path);
        expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE', reason: path);
      } else {
        final hasId3 = ascii.decode(bytes.sublist(0, 3), allowInvalid: true) == 'ID3';
        final hasFrameSync = bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;
        expect(hasId3 || hasFrameSync, isTrue, reason: path);
      }
    }
  });

  test('audio provenance documents are bundled', () async {
    final licenses = await rootBundle.loadString('assets/audio/LICENSES.md');
    final sources = await rootBundle.loadString('assets/audio/SOURCES.csv');
    expect(licenses, contains('All 17 audio assets'));
    expect(sources.split('\n').where((line) => line.isNotEmpty), hasLength(18));
  });
}
