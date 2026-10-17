import 'dart:math' as math;

import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/preferences.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:c411_remote/ui/downloads_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _T extends TorrentsNotifier {
  final rnd = math.Random(1);
  @override
  TorrentsState build() => TorrentsState(
    byId: {
      for (var i = 0; i < 60; i++)
        i: Torrent({
          'id': i,
          'name': 'T$i',
          'hashString': 'h$i',
          'status': 6,
          'percentDone': 1.0,
          'rateUpload': rnd.nextInt(1000),
        }),
    },
    hashes: const {},
    loaded: true,
  );
  void tick() {
    final map = Map.of(state.byId);
    for (var k = 0; k < 20; k++) {
      final i = rnd.nextInt(60);
      map[i] = map[i]!.merge({'rateUpload': rnd.nextInt(1000)});
    }
    state = TorrentsState(byId: map, hashes: state.hashes, loaded: true);
  }
}

class _P extends UiPrefsNotifier {
  @override
  UiPrefs build() =>
      const UiPrefs(transferSort: 'upload', transferAscending: false);
}

void main() {
  testWidgets(
    'liste des transferts réordonnée à chaque rafraîchissement, sans erreur',
    (tester) async {
      final errors = <String>[];
      final old = FlutterError.onError;
      FlutterError.onError = (d) =>
          errors.add(d.exceptionAsString().split('\n').first);
      addTearDown(() => FlutterError.onError = old);
      final c = ProviderContainer(
        overrides: [
          torrentsProvider.overrideWith(_T.new),
          uiPrefsProvider.overrideWith(_P.new),
          transmissionProvider.overrideWithValue(
            TransmissionClient(url: 'http://x'),
          ),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: const DownloadsPage(),
          ),
        ),
      );
      for (var i = 0; i < 15; i++) {
        (c.read(torrentsProvider.notifier) as _T).tick();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.drag(find.byType(ListView).last, const Offset(0, -200));
        await tester.pump();
      }
      expect(errors, isEmpty);
    },
  );
}
