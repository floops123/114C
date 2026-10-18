import 'dart:typed_data';

import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/preferences.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:c411_remote/ui/downloads_page.dart';
import 'package:c411_remote/ui/releases_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Les lignes de liste ont une hauteur fixe (fluidité du défilement) : elles
// ne doivent jamais déborder, quelle que soit la largeur ou la taille de
// police du système.

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
          bool ascending = false}) async =>
      ReleasePage([
        for (var i = 0; i < 6; i++)
          Release(
            tracker: Tracker.c411,
            id: '$i',
            infoHash: 'x$i',
            name: 'Outlander.Blood.of.My.Blood.S02E05.MULTi.VFF.2160p.WEB.DV.HDR10.EAC3.5.1.H265-BYOR',
            title: 'Outlander: Blood of My Blood',
            year: 2025,
            subcategory: 'Animation Série',
            resolution: '2160p',
            source: 'WEB-DL',
            languages: const ['MULTI', 'VFF'],
            isFreeleech: true,
            isExclusive: true,
            size: 48975635091,
            seeders: 1234,
            leechers: 567,
            createdAt: DateTime(2026, 10, 17),
          ),
      ], 1, 1, 6);
  @override
  Future<Uint8List> downloadTorrent(Release release) async => Uint8List(0);
}

class _Prefs extends UiPrefsNotifier {
  @override
  UiPrefs build() => const UiPrefs(releasesGrid: false);
}

class _Torrents extends TorrentsNotifier {
  @override
  TorrentsState build() => TorrentsState(byId: {
        for (var i = 0; i < 6; i++)
          i: Torrent({
            'id': i,
            'name': 'Esprits.Criminels.2005.S19.MULTI.VFF.2160p.WEB.DV.HDR10.EAC3.5.1.H265-SUPPLY',
            'hashString': 'h$i',
            'status': i.isEven ? 4 : 6,
            'percentDone': i.isEven ? 0.42 : 1.0,
            'sizeWhenDone': 48975635091,
            'leftUntilDone': i.isEven ? 28000000000 : 0,
            'rateDownload': 12345678,
            'rateUpload': 2345678,
            'eta': 3600,
            'uploadRatio': 1.23,
            'labels': ['cross-seed', 'films'],
            'bandwidthPriority': 1,
          }),
      }, hashes: const {}, loaded: true);
}

void main() {
  for (final (width, height) in [(390.0, 844.0), (1705.0, 900.0)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('lignes sans débordement : ${width.toInt()} px, police ×$scale',
          (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        Widget app(Widget page) => ProviderScope(
              overrides: [
                uiPrefsProvider.overrideWith(_Prefs.new),
                trackersProvider.overrideWithValue({Tracker.c411: _Tracker()}),
                torrentsProvider.overrideWith(_Torrents.new),
                transmissionProvider
                    .overrideWithValue(TransmissionClient(url: 'http://x')),
              ],
              child: MaterialApp(
                theme: buildTheme(Brightness.dark),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: page,
              ),
            );

        // Lignes de sorties (résultats de recherche, versions d'un titre), à
        // la hauteur fixe calculée par ReleaseRow.extent.
        final releases = (await _Tracker().releases()).items;
        await tester.pumpWidget(app(Scaffold(
          body: Builder(
            builder: (context) => ListView(
              itemExtent: ReleaseRow.extent(context),
              children: [for (final r in releases) ReleaseRow(release: r)],
            ),
          ),
        )));
        await tester.pump();
        expect(find.byType(ReleaseRow), findsWidgets);
        expect(tester.takeException(), isNull, reason: 'Sorties');

        await tester.pumpWidget(app(const DownloadsPage()));
        await tester.pump();
        expect(find.textContaining('Esprits.Criminels'), findsWidgets);
        expect(tester.takeException(), isNull, reason: 'Transferts');
      });
    }
  }
}
