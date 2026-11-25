import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Runs the on-device tests, saves what they measured to
/// build/lenzo_device_report.json and any screenshots to
/// build/device_screens/.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final out = File('build/lenzo_device_report.json');
    await out.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
  onScreenshot: (name, bytes, [args]) async {
    final f = File('build/device_screens/$name.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    return true;
  },
);
