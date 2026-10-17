import 'dart:typed_data';

import 'package:c411_remote/api/c411_socket.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/preferences.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/notifications.dart';
import 'package:c411_remote/state/releases.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:c411_remote/ui/home_shell.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:c411_remote/ui/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _S extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      const AppSettings(rpcUrl: 'http://x', apiKeys: {'c411': 'k'});
}

class _Sel extends SelectedTrackerNotifier {
  @override
  Tracker? build() => Tracker.c411;
}

class _P extends UiPrefsNotifier {
  @override
  UiPrefs build() => const UiPrefs();
}

class _N extends NotificationsNotifier {
  @override
  NotificationsState build() => const NotificationsState(
    configured: true,
    status: SocketStatus.connected,
  );
}

class _T extends TorrentsNotifier {
  @override
  TorrentsState build() => TorrentsState(
    byId: {
      for (var i = 0; i < 30; i++)
        i: Torrent({
          'id': i,
          'name': 'T$i',
          'hashString': 'h$i',
          'status': 6,
          'percentDone': 1.0,
          'rateUpload': i,
        }),
    },
    hashes: const {},
    loaded: true,
  );
  void tick() => state = TorrentsState(
    byId: {
      for (final e in state.byId.entries)
        e.key: e.value.merge({'rateUpload': e.value.rateUpload + 7}),
    },
    hashes: const {},
    loaded: true,
  );
}

class _Tr implements TrackerApi {
  @override
  Tracker get tracker => Tracker.c411;
  @override
  List<ReleaseSort> get sorts => ReleaseSort.values;
  @override
  Set<ReleaseSort> get serverSorts => ReleaseSort.values.toSet();
  @override
  Future<List<Category>> categories() async => const [];
  @override
  Future<ReleasePage> releases({
    int page = 1,
    int perPage = 50,
    int? categoryId,
    int? subcategoryId,
    String query = '',
    ReleaseSort sort = ReleaseSort.date,
    bool ascending = false,
  }) async => ReleasePage(
    [
      for (var i = 0; i < 20; i++)
        Release(
          tracker: Tracker.c411,
          id: '$i',
          infoHash: 'x$i',
          name: 'R$i',
          createdAt: DateTime(2026),
        ),
    ],
    1,
    1,
    20,
  );
  @override
  Future<Uint8List> downloadTorrent(Release r) async => Uint8List(0);
}

void main() {
  for (final width in [400.0, 1400.0]) {
    testWidgets(
      'app complète sans erreur : onglets, info-bulles, rafraîchissements ($width px)',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final errors = <String>[];
        final old = FlutterError.onError;
        FlutterError.onError = (d) =>
            errors.add(d.exceptionAsString().split('\n').first);
        addTearDown(() => FlutterError.onError = old);
        final c = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(_S.new),
            selectedTrackerProvider.overrideWith(_Sel.new),
            uiPrefsProvider.overrideWith(_P.new),
            notificationsProvider.overrideWith(_N.new),
            torrentsProvider.overrideWith(_T.new),
            currentTrackerApiProvider.overrideWithValue(_Tr()),
            trackersProvider.overrideWithValue({Tracker.c411: _Tr()}),
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
              scrollBehavior: const AppScrollBehavior(),
              home: const HomeShell(),
            ),
          ),
        );
        await tester.pump();
        // Le salon est un onglet comme les autres.
        expect(find.text('Salon'), findsWidgets);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        for (var round = 0; round < 3; round++) {
          for (var tab = 0; tab < 6; tab++) {
            final nav = find.byType(
              width < 720 ? NavigationBar : NavigationRail,
            );
            if (width < 720) {
              (tester.widget<NavigationBar>(nav)).onDestinationSelected!(tab);
            } else {
              (tester.widget<NavigationRail>(nav)).onDestinationSelected!(tab);
            }
            await tester.pump();
            // Survole chaque bouton à info-bulle visible, puis change d'onglet.
            for (final b
                in find.byType(IconButton).hitTestable().evaluate().take(6)) {
              await mouse.moveTo(tester.getCenter(find.byWidget(b.widget)));
              await tester.pump(const Duration(seconds: 1));
            }
            (c.read(torrentsProvider.notifier) as _T).tick();
            await tester.pump(const Duration(milliseconds: 500));
          }
        }
        await mouse.removePointer();
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(errors, isEmpty);
      },
    );
  }
}
