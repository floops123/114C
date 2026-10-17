import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:c411_remote/api/astra.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/bencode.dart';
import 'package:c411_remote/state/cross_seed.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Encodeur bencode minimal pour fabriquer des .torrent de test.
Uint8List benc(Object v) {
  final out = BytesBuilder();
  void w(Object v) {
    switch (v) {
      case int n:
        out.add(ascii.encode('i${n}e'));
      case String s:
        final b = utf8.encode(s);
        out.add(ascii.encode('${b.length}:'));
        out.add(b);
      case List l:
        out.addByte(0x6c);
        for (final e in l) {
          w(e as Object);
        }
        out.addByte(0x65);
      case Map m:
        out.addByte(0x64);
        for (final k in (m.keys.cast<String>().toList()..sort())) {
          w(k);
          w(m[k] as Object);
        }
        out.addByte(0x65);
    }
  }

  w(v);
  return out.toBytes();
}

Uint8List torrentFile(String name, List<(List<String>, int)>? files, {int? length}) =>
    benc({
      'announce': 'https://tracker.example/announce',
      'info': {
        'name': name,
        'piece length': 262144,
        'pieces': 'x' * 20,
        if (files != null)
          'files': [
            for (final (path, len) in files) {'path': path, 'length': len},
          ]
        else
          'length': length!,
      },
    });

/// Transmission : un torrent C411 (dossier), un tr4ker (fichier seul), un
/// d'un autre tracker, un non terminé.
class _Transmission extends TransmissionClient {
  _Transmission() : super(url: 'http://x');
  final added = <AddOptions>[];

  static final torrents = [
    {
      'id': 1, 'name': 'Film.2024.MULTi.1080p.WEB-GRP', 'hashString': 'AAA',
      'totalSize': 3000, 'downloadDir': '/data/films', 'percentDone': 1.0,
      'trackers': [{'announce': 'https://tracker.c411.org/abc/announce'}],
      'files': [
        {'name': 'Film.2024.MULTi.1080p.WEB-GRP/film.mkv', 'length': 2900},
        {'name': 'Film.2024.MULTi.1080p.WEB-GRP/film.nfo', 'length': 100},
      ],
    },
    {
      'id': 2, 'name': 'Serie.S01E01.1080p-GRP.mkv', 'hashString': 'bbb',
      'totalSize': 500, 'downloadDir': '/data/series', 'percentDone': 1.0,
      'trackers': [{'announce': 'https://tr4ker.net/announce/xyz'}],
      'files': [{'name': 'Serie.S01E01.1080p-GRP.mkv', 'length': 500}],
    },
    {
      'id': 3, 'name': 'Doc.2023-GRP', 'hashString': 'ccc', 'totalSize': 700,
      'downloadDir': '/data/docs', 'percentDone': 1.0,
      'trackers': [{'announce': 'udp://autre.example:80/announce'}],
      'files': [{'name': 'Doc.2023-GRP/doc.mkv', 'length': 700}],
    },
    {
      'id': 4, 'name': 'EnCours-GRP', 'hashString': 'ddd', 'totalSize': 9,
      'downloadDir': '/data', 'percentDone': 0.5, 'trackers': [], 'files': [],
    },
  ];

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async => (
        torrents: [
          for (final t in torrents)
            if (ids is! List || ids.contains(t['id'])) Map<String, dynamic>.from(t),
        ],
        removed: <int>[],
      );

  @override
  Future<bool> addTorrent(
      {Uint8List? metainfo, String? filename, AddOptions options = const AddOptions()}) async {
    added.add(options);
    return true;
  }
}

class _Tracker implements TrackerApi {
  _Tracker(this.tracker, this.results, this.files);
  @override
  final Tracker tracker;
  final Map<String, List<Release>> results;
  final Map<String, Uint8List> files;
  final queries = <String>[];
  var downloads = 0;

  @override
  List<ReleaseSort> get sorts => const [];
  @override
  Set<ReleaseSort> get serverSorts => const {};
  @override
  Future<List<Category>> categories() async => const [];
  @override
  Future<ReleasePage> releases({int page = 1, int perPage = 50, int? categoryId,
      int? subcategoryId, String query = '', ReleaseSort sort = ReleaseSort.date,
      bool ascending = false}) async {
    queries.add(query);
    final r = results[query] ?? const [];
    return ReleasePage(r, 1, 1, r.length);
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async {
    downloads++;
    return files[release.id]!;
  }
}

Release _rel(Tracker t, String id, String name, int size, {String? hash}) => Release(
    tracker: t, id: id, name: name, size: size, infoHash: hash ?? 'h$id',
    createdAt: DateTime(2026));

class _NoTorrents extends TorrentsNotifier {
  @override
  TorrentsState build() => const TorrentsState();
  @override
  Future<void> refresh({bool full = false}) async {}
}

/// AstraTorrent : scanner par lots, correspondances par infohash local.
class _Astra extends AstraApi {
  _Astra(this.matches, this.files) : super('passkey');
  final Map<String, Release> matches;
  final Map<String, Uint8List> files;
  final scans = <List<AstraQuery>>[];

  @override
  Future<Map<String, Release>> bulkScan(List<AstraQuery> items) async {
    scans.add(items);
    return {
      for (final i in items)
        i.hash: ?matches[i.hash],
    };
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async => files[release.id]!;
}

void main() {
  test('bencode : torrent à plusieurs fichiers et à fichier seul', () {
    final multi = TorrentContent.parse(torrentFile('Dossier', [
      (['a', 'film.mkv'], 10),
      (['film.nfo'], 2),
    ]));
    expect(multi.files, [('Dossier/a/film.mkv', 10), ('Dossier/film.nfo', 2)]);
    expect(multi.totalSize, 12);
    final single = TorrentContent.parse(torrentFile('Film.mkv', null, length: 5));
    expect(single.files, [('Film.mkv', 5)]);
    expect(() => TorrentContent.parse(Uint8List.fromList(utf8.encode('d4:spami1ee'))),
        throwsFormatException);
  });

  test('origine d’après les annonces, nom recherché, comparaison', () {
    expect(Tracker.fromAnnounces(['https://tracker.c411.org/x/announce']), Tracker.c411);
    expect(Tracker.fromAnnounces(['https://tr4ker.net/announce']), Tracker.tr4ker);
    expect(Tracker.fromAnnounces(['https://nostradamus.foo/announce/abc']), Tracker.nostradamus);
    expect(Tracker.fromAnnounces(['udp://open.example:80']), isNull);
    expect(crossSeedQuery('Serie.S01E01.1080p-GRP.mkv'), 'Serie.S01E01.1080p-GRP');
    expect(crossSeedQuery('Film.2024.MULTi.1080p.WEB-GRP'), 'Film.2024.MULTi.1080p.WEB-GRP');
    expect(sameFiles([('a', 1), ('b', 2)], [('b', 2), ('a', 1)]), isTrue);
    expect(sameFiles([('a', 1)], [('a', 2)]), isFalse);
  });

  test('analyse dans les deux sens, mémoire et ajout', () async {
    // tr4ker : le film C411 existe (mêmes fichiers) ; le doc existe avec un
    // autre nom de dossier (même taille).
    final tr4ker = _Tracker(Tracker.tr4ker, {
      'Film.2024.MULTi.1080p.WEB-GRP': [
        _rel(Tracker.tr4ker, 't1', 'Film.2024.MULTi.1080p.WEB-GRP', 3000),
        _rel(Tracker.tr4ker, 't0', 'Film.2024.MULTi.1080p.WEB-AUTRE', 3100),
      ],
      'Doc.2023-GRP': [_rel(Tracker.tr4ker, 't2', 'Doc.2023-GRP', 700)],
    }, {
      't1': torrentFile('Film.2024.MULTi.1080p.WEB-GRP', [
        (['film.mkv'], 2900),
        (['film.nfo'], 100),
      ]),
      't2': torrentFile('Doc.2023.REPACK-GRP', [(['doc.mkv'], 700)]),
    });
    // C411 : la série tr4ker y est déjà dans Transmission (même infohash) ;
    // le doc est introuvable.
    final c411 = _Tracker(Tracker.c411, {
      'Serie.S01E01.1080p-GRP': [
        _rel(Tracker.c411, 'c1', 'Serie.S01E01.1080p-GRP', 500, hash: 'aaa'),
      ],
    }, {});

    final transmission = _Transmission();
    final cache = MemoryCrossSeedCache();
    ProviderContainer container() {
      final c = ProviderContainer(overrides: [
        transmissionProvider.overrideWithValue(transmission),
        trackersProvider.overrideWithValue({Tracker.c411: c411, Tracker.tr4ker: tr4ker}),
        crossSeedCacheProvider.overrideWithValue(cache),
        crossSeedDelayProvider.overrideWithValue(Duration.zero),
        torrentsProvider.overrideWith(_NoTorrents.new),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    final first = container();
    await first.read(crossSeedProvider.notifier).scan();
    var s = first.read(crossSeedProvider);
    final byKey = {for (final i in s.items) '${i.name}→${i.target.label}': i};
    expect(byKey.keys.toSet(), {
      'Film.2024.MULTi.1080p.WEB-GRP→tr4ker', // C411 → tr4ker
      'Serie.S01E01.1080p-GRP.mkv→C411', // tr4ker → C411
      'Doc.2023-GRP→C411', // autre tracker → les deux
      'Doc.2023-GRP→tr4ker',
    }, reason: 'le torrent non terminé est ignoré');
    expect(byKey['Film.2024.MULTi.1080p.WEB-GRP→tr4ker']!.status, CrossSeedStatus.match);
    expect(byKey['Serie.S01E01.1080p-GRP.mkv→C411']!.status, CrossSeedStatus.present);
    expect(byKey['Doc.2023-GRP→C411']!.status, CrossSeedStatus.notFound);
    final doc = byKey['Doc.2023-GRP→tr4ker']!;
    expect(doc.status, CrossSeedStatus.mismatch);
    expect(doc.detail, contains('nom différent'));
    expect(tr4ker.downloads, 2, reason: 'seul le candidat de même taille est téléchargé');
    expect(s.running, isFalse);

    // Ajout : dans le dossier existant, avec l'étiquette cross-seed.
    expect(await first.read(crossSeedProvider.notifier).addAll(), 1);
    expect(transmission.added.single.downloadDir, '/data/films');
    expect(transmission.added.single.labels, ['cross-seed']);
    expect(first.read(crossSeedProvider).count(CrossSeedStatus.added), 1);

    // Nouvelle analyse : introuvables / différents / déjà partagés mémorisés.
    final second = container();
    await second.read(crossSeedProvider.notifier).scan();
    s = second.read(crossSeedProvider);
    expect(s.skipped, 3);
    expect(s.items.single.name, 'Film.2024.MULTi.1080p.WEB-GRP');

    // « Tout réanalyser » ignore la mémoire.
    await second.read(crossSeedProvider.notifier).scan(force: true);
    expect(second.read(crossSeedProvider).items, hasLength(4));
  });

  test('AstraTorrent : un scan par lots, puis vérification des fichiers', () async {
    final astra = _Astra({
      'aaa': _rel(Tracker.astra, 'a1', 'Film.2024.MULTi.1080p.WEB-GRP', 3000),
      'ccc': _rel(Tracker.astra, 'a3', 'Doc.2023-GRP', 700),
    }, {
      'a1': torrentFile('Film.2024.MULTi.1080p.WEB-GRP', [
        (['film.mkv'], 2900),
        (['film.nfo'], 100),
      ]),
      'a3': torrentFile('Doc.2023-GRP', [(['autre.mkv'], 700)]),
    });
    final transmission = _Transmission();
    final container = ProviderContainer(overrides: [
      transmissionProvider.overrideWithValue(transmission),
      trackersProvider.overrideWithValue({Tracker.astra: astra}),
      crossSeedCacheProvider.overrideWithValue(MemoryCrossSeedCache()),
      crossSeedDelayProvider.overrideWithValue(Duration.zero),
      torrentsProvider.overrideWith(_NoTorrents.new),
    ]);
    addTearDown(container.dispose);

    await container.read(crossSeedProvider.notifier).scan();
    expect(astra.scans.single.map((q) => (q.hash, q.size)),
        [('aaa', 3000), ('bbb', 500), ('ccc', 700)],
        reason: 'les torrents terminés, en un seul lot');
    final status = {
      for (final i in container.read(crossSeedProvider).items) i.hash: i.status,
    };
    expect(status, {
      'aaa': CrossSeedStatus.match,
      'bbb': CrossSeedStatus.notFound,
      'ccc': CrossSeedStatus.mismatch,
    });
    expect(await container.read(crossSeedProvider.notifier).addAll(), 1);
    expect(transmission.added.single.downloadDir, '/data/films');
  });

  test('AstraTorrent : lecture de la réponse bulk_scan', () {
    final matches = AstraApi.parseScan('''{"results": [
      {"matched": true, "query": {"name": "Film", "size": 3000, "info_hash": "AAA"},
       "torrent": {"id": 42, "name": "Film", "size_bytes": 3000,
                   "size_formatted": "2.9 KB", "download_url": "/download.php?id=42&passkey=x",
                   "is_sauveur": true}},
      {"matched": false, "query": {"name": "Autre", "size": 1, "info_hash": "bbb"}}
    ]}''');
    expect(matches.keys, ['aaa']);
    final r = matches['aaa']!;
    expect((r.id, r.size, r.downloadUrl), ('42', 3000, '/download.php?id=42&passkey=x'));
    expect(() => AstraApi.parseScan({'status': 'success', 'user': null, 'results': []}),
        throwsA(isA<TrackerException>()));
    expect(() => AstraApi.parseScan({'error': 'Passkey invalide'}),
        throwsA(isA<TrackerException>()
            .having((e) => e.message, 'message', contains('Passkey invalide'))));
  });

  test('AstraTorrent : liste des sorties (torrents.php)', () {
    final items = AstraApi.parseTorrents(
        File('test/fixtures/astra_torrents.json').readAsStringSync(), 'PASSKEY');
    expect(items, hasLength(2));
    final r = items.first;
    expect(r.tracker, Tracker.astra);
    expect(r.name, 'Rendition 2007 MULTi VFF 1080p BluRay AC3 x265-Winks');
    expect(r.title, 'Détention secrète');
    expect(r.year, 2007);
    expect(r.resolution, '1080p');
    expect(r.infoHash, '89d2cf08806d0e9b7079868d400e54f8ff750ee6');
    expect((r.size, r.seeders, r.completions), (5268155992, 3, 12));
    expect(r.subcategory, 'Longs-métrages / Cinéma');
    expect(r.posterUrl, startsWith('https://image.tmdb.org/'));
    expect(r.downloadUrl, '/api/download.php?id=17530&passkey=PASSKEY');
    // 15:17:38 à Paris, heure d'été (le RSS du site donne +0200).
    expect(r.createdAt, DateTime.utc(2026, 10, 17, 13, 17, 38));
    expect(parseParisTime('2026-01-10 12:00:00'), DateTime.utc(2026, 1, 10, 11));
    expect(parseParisTime('2026-10-25 03:30:00'), DateTime.utc(2026, 10, 25, 2, 30));
  });

  test('sens choisis : origines et destinations exclues', () async {
    final tr4ker = _Tracker(Tracker.tr4ker, {}, {});
    final c411 = _Tracker(Tracker.c411, {}, {});
    final container = ProviderContainer(overrides: [
      transmissionProvider.overrideWithValue(_Transmission()),
      trackersProvider.overrideWithValue({Tracker.c411: c411, Tracker.tr4ker: tr4ker}),
      crossSeedCacheProvider.overrideWithValue(MemoryCrossSeedCache()),
      crossSeedDelayProvider.overrideWithValue(Duration.zero),
      torrentsProvider.overrideWith(_NoTorrents.new),
    ]);
    addTearDown(container.dispose);
    final directions = container.read(crossSeedDirectionsProvider.notifier)
      ..toggleFrom(null) // pas les torrents d'autres trackers
      ..toggleTo(Tracker.c411); // rien vers C411
    final d = container.read(crossSeedDirectionsProvider);
    expect((d.from(null), d.from(Tracker.c411), d.to(Tracker.c411)), (false, true, false));

    await container.read(crossSeedProvider.notifier).scan();
    expect(
        container.read(crossSeedProvider).items.map((i) => '${i.source?.label}→${i.target.label}'),
        ['C411→tr4ker']);
    expect(c411.queries, isEmpty);

    // Recocher rétablit le sens.
    directions.toggleTo(Tracker.c411);
    await container.read(crossSeedProvider.notifier).scan();
    expect(c411.queries, ['Serie.S01E01.1080p-GRP']);
  });
}
