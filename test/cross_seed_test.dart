import 'dart:convert';
import 'dart:typed_data';

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
}
