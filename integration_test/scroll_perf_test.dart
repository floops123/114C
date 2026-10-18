// Banc d'essai de fluidité : défilement des transferts (424 torrents
// rafraîchis toutes les 2 s) et des sorties (affiches TMDB).
// flutter drive --profile -d linux --driver=test_driver/perf_driver.dart \
//   --target=integration_test/scroll_perf_test.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/preferences.dart';
import 'package:c411_remote/state/releases.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:c411_remote/ui/downloads_page.dart';
import 'package:c411_remote/ui/releases_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _posters = [
  'https://image.tmdb.org/t/p/w500/tO67V8FhUlGghwttkPkEdUYpCWI.jpg',
  'https://image.tmdb.org/t/p/w500/6teVZPk7JW0aePF7yzCBRKFNPSD.jpg',
  'https://image.tmdb.org/t/p/w500/33NysOnLpLZY0ewHTcfpalzAsRG.jpg',
  'https://image.tmdb.org/t/p/w500/xk3XBVkHgn2QYKYpabJImEWNbim.jpg',
  'https://image.tmdb.org/t/p/w500/kRgsJq9dMz7bIciUEqwbmzFBwSL.jpg',
  'https://image.tmdb.org/t/p/w500/rpACJX9KC5V65NW5AcIy0zPhi5D.jpg',
  'https://image.tmdb.org/t/p/w500/8h0ACHWTjv2cdwiMZ5t3zEvs0f8.jpg',
  'https://image.tmdb.org/t/p/w500/gGpOBlVqrelKKKYTwpFxhAaBVdq.jpg',
  'https://image.tmdb.org/t/p/w500/iszDGgBwKd47GMmnWekGSVj9wwM.jpg',
  'https://image.tmdb.org/t/p/w500/vzbhprlVk5Mn837CObJ93oG66ll.jpg',
  'https://image.tmdb.org/t/p/w500/8fQFQRgkF3wDw2L2uVakSOlvvwj.jpg',
  'https://image.tmdb.org/t/p/w500/qTSDZvY9TSh41cWYm1Ktv9Oqk5N.jpg',
];

/// 424 torrents ; toutes les 2 s, ~20 d'entre eux changent (comme le
/// rafraîchissement « recently-active »).
class _Torrents extends TorrentsNotifier {
  final _rnd = math.Random(1);

  Map<String, dynamic> _json(int i) => {
        'id': i,
        'name': 'Torrent.$i.${['Film', 'Serie', 'Doc'][i % 3]}.2025.MULTi.1080p.WEB.H265-GRP',
        'hashString': 'h$i',
        'status': i % 7 == 0 ? 4 : (i % 11 == 0 ? 0 : 6),
        'percentDone': i % 7 == 0 ? _rnd.nextDouble() : 1.0,
        'sizeWhenDone': 1500000000 + i * 1000000,
        'leftUntilDone': i % 7 == 0 ? 500000000 : 0,
        'rateDownload': i % 7 == 0 ? _rnd.nextInt(4000000) : 0,
        'rateUpload': _rnd.nextInt(800000),
        'uploadRatio': _rnd.nextDouble() * 3,
        'eta': i % 7 == 0 ? 600 : -1,
        'addedDate': 1790000000 - i * 3600,
        'labels': i % 13 == 0 ? ['films'] : <String>[],
      };

  @override
  TorrentsState build() {
    final timer = Timer.periodic(const Duration(seconds: 2), (_) {
      final map = Map.of(state.byId);
      for (var k = 0; k < 20; k++) {
        final i = _rnd.nextInt(424);
        map[i] = map[i]!.merge({'rateUpload': _rnd.nextInt(800000)});
      }
      state = TorrentsState(byId: map, hashes: state.hashes, loaded: true);
    });
    ref.onDispose(timer.cancel);
    final map = {for (var i = 0; i < 424; i++) i: Torrent(_json(i))};
    return TorrentsState(byId: map, hashes: const {}, loaded: true);
  }
}

class _Tracker implements TrackerApi {
  @override
  void close() {}
  @override
  Tracker get tracker => Tracker.c411;
  @override
  List<ReleaseSort> get sorts => ReleaseSort.values;
  @override
  Set<ReleaseSort> get serverSorts => ReleaseSort.values.toSet();
  @override
  Future<List<Category>> categories() async => const [];
  @override
  Future<ReleasePage> releases({int page = 1, int perPage = 50, int? categoryId,
      int? subcategoryId, String query = '', ReleaseSort sort = ReleaseSort.date,
      bool ascending = false}) async => ReleasePage([
        for (var k = 0; k < perPage; k++)
          Release(
            tracker: Tracker.c411,
            id: '${page * 100 + k}',
            infoHash: 'x${page * 100 + k}',
            name: 'Release.${page * 100 + k}.MULTi.1080p.WEB.H265-GRP',
            title: 'Film ${page * 100 + k}',
            year: 2000 + k,
            posterUrl: _posters[(page * 7 + k) % _posters.length],
            resolution: '1080p',
            source: 'WEB-DL',
            languages: const ['MULTI', 'VFF'],
            subcategory: 'Film',
            size: 2000000000,
            seeders: 50 - k,
            createdAt: DateTime.now().subtract(Duration(minutes: page * 100 + k)),
          ),
      ], page, 3, 150);
  @override
  Future<Uint8List> downloadTorrent(Release release) async => Uint8List(0);
}

class _Prefs extends UiPrefsNotifier {
  _Prefs(this.grid);
  final bool grid;
  @override
  UiPrefs build() => UiPrefs(releasesGrid: grid, themeMode: ThemeMode.dark);
}

Widget _app(Widget page, SharedPreferencesWithCache prefs, {bool grid = true}) =>
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        uiPrefsProvider.overrideWith(() => _Prefs(grid)),
        torrentsProvider.overrideWith(_Torrents.new),
        transmissionProvider.overrideWithValue(TransmissionClient(url: 'http://127.0.0.1:1')),
        currentTrackerApiProvider.overrideWithValue(_Tracker()),
        trackersProvider.overrideWithValue({Tracker.c411: _Tracker()}),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        // Format téléphone.
        builder: (context, child) => Center(
          child: SizedBox(width: 390, height: 844, child: child),
        ),
        home: page,
      ),
    );

/// Défile vite vers le bas puis vers le haut, en laissant les images arriver.
Future<void> _scroll(WidgetTester tester, Finder list) async {
  for (var round = 0; round < 3; round++) {
    for (final dy in [-1500.0, -1500.0, -1500.0, 1500.0, 1500.0, 1500.0]) {
      await tester.fling(list, Offset(0, dy), 4000);
      for (var f = 0; f < 45; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('transferts', (tester) async {
    await tester.pumpWidget(_app(const DownloadsPage(), await loadSharedPrefs()));
    await tester.pump(const Duration(seconds: 1));
    await binding.watchPerformance(
        () => _scroll(tester, find.byType(ListView).last),
        reportKey: 'transferts');
  });

  for (final grid in [true, false]) {
    testWidgets('sorties ${grid ? 'grille' : 'liste'}', (tester) async {
      await tester.pumpWidget(
          _app(const ReleasesPage(), await loadSharedPrefs(), grid: grid));
      await tester.pump(const Duration(seconds: 2));
      await binding.watchPerformance(
          () => _scroll(tester,
              find.byType(grid ? GridView : ListView).last),
          reportKey: 'sorties_${grid ? 'grille' : 'liste'}');
    });
  }
}
