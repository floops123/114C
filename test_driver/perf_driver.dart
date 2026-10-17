import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Écrit les mesures de fluidité dans `build/perf/<scénario>.json`.
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) return;
        final dir = Directory('build/perf')..createSync(recursive: true);
        for (final MapEntry(:key, :value) in data.entries) {
          File('${dir.path}/$key.json')
              .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(value));
        }
      },
    );
