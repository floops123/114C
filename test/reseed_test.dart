import 'dart:io';
import 'dart:typed_data';

import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/state/palliative.dart';
import 'package:c411_remote/state/reseed.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'palliative_test.dart' show FakeTorrents, FakeTracker;
import 'torrent_fixture.dart';

Release _rel(String id, String name, int size, {String? hash}) => Release(
    tracker: Tracker.tr4ker, id: id, name: name, size: size, seeders: 4, infoHash: hash, createdAt: DateTime(2026));

/// Transmission : ajout, puis vérification qui finit à [percentDone] selon
/// le dossier donné.
class _Transmission extends TransmissionClient {
  _Transmission(this.percentDone) : super(url: 'http://127.0.0.1:9091/transmission/rpc');
  final double Function(String downloadDir) percentDone;
  final added = <AddOptions>[];
  final actions = <String>[];
  final renamed = <String>[];
  final _dirOf = <int, String>{};
  var _polls = 0;

  @override
  Future<({bool added, String? hash})> addTorrentWithHash(
      {Uint8List? metainfo, String? filename, AddOptions options = const AddOptions()}) async {
    added.add(options);
    _dirOf[added.length] = options.downloadDir!;
    return (added: true, hash: 'h${added.length}');
  }

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async {
    final list = ids as List;
    if (list.first is String) {
      return (torrents: [{'id': int.parse((list.first as String).substring(1))}], removed: <int>[]);
    }
    final id = list.first as int;
    // Un premier passage « vérification en cours », puis le résultat.
    final checking = (_polls++).isEven;
    return (
      torrents: [
        {
          'id': id,
          'status': checking ? 2 : 0,
          'recheckProgress': checking ? 0.5 : 1,
          'percentDone': checking ? 0 : percentDone(_dirOf[id]!),
        },
      ],
      removed: <int>[],
    );
  }

  @override
  Future<void> renamePath(int id, String path, String name) async => renamed.add('$id:$path→$name');

  @override
  Future<void> action(String method, List<int>? ids) async => actions.add('$method $ids');
}

void main() {
  late Directory dir;
  final movie = testBytes(100, 1), a = testBytes(40, 2), b = testBytes(25, 3);
  final movieTorrent = realTorrent('Film.A-GRP.mkv', [(const [], movie)]);
  final packTorrent = realTorrent('Pack-GRP', [(['a.txt'], a), (['sous', 'b.txt'], b)]);

  setUp(() {
    ReseedNotifier.pollEvery = Duration.zero;
    dir = Directory.systemTemp.createTempSync('reseed');
    File('${dir.path}/Film.A-GRP.mkv').writeAsBytesSync(movie);
    File('${dir.path}/Pack-GRP/a.txt')
      ..createSync(recursive: true)
      ..writeAsBytesSync(a);
    File('${dir.path}/Pack-GRP/sous/b.txt')
      ..createSync(recursive: true)
      ..writeAsBytesSync(b);
    // Même nom et même taille sur le tracker, mais d'autres données.
    File('${dir.path}/Autre.mkv').writeAsBytesSync(testBytes(100, 9));
    File('${dir.path}/Inconnu.mkv').writeAsBytesSync(testBytes(10, 4));
    File('${dir.path}/.cache').writeAsBytesSync([1]);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('candidats : premier niveau, ou aussi les sous-dossiers', () async {
    final top = await reseedCandidates(dir.path);
    expect([for (final (p, s, _) in top) (p.split('/').last, s)],
        [('Autre.mkv', 100), ('Film.A-GRP.mkv', 100), ('Inconnu.mkv', 10), ('Pack-GRP', 65)]);
    final deep = await reseedCandidates(dir.path, deep: true);
    expect(deep.map((e) => e.$1.split('/').last), containsAll(['Pack-GRP', 'a.txt', 'sous']));
  });

  test('chemin vu par Transmission : même dossier ou montage', () {
    expect(transmissionPath('/home/moi/Films/x', folder: '/home/moi/Films', transmissionFolder: '/data/films/'),
        '/data/films/x');
    expect(transmissionPath('/home/moi/Films', folder: '/home/moi/Films', transmissionFolder: '/data/films'),
        '/data/films');
    expect(transmissionPath('/home/moi/Films/a/b', folder: '/home/moi/Films', transmissionFolder: r'D:\Films'),
        r'D:\Films\a\b');
  });

  test('recherche, puis ajout sur place vérifié ; incomplet : laissé en pause', () async {
    final tracker = FakeTracker(Tracker.tr4ker, results: {
      'Film.A-GRP': [_rel('f', 'Film.A-GRP', 100), _rel('g', 'Film.A-GRP.autre', 50)],
      'Pack-GRP': [_rel('p', 'Pack-GRP', 65)],
      'Autre': [_rel('o', 'Autre', 100)],
    })
      ..files['f'] = movieTorrent
      ..files['p'] = packTorrent
      ..files['o'] = realTorrent('Autre.mkv', [(const [], testBytes(100, 1))]);
    // Le pack n'est pas vu par Transmission au chemin donné.
    final transmission = _Transmission((dir) => dir.endsWith('/srv') ? 1 : 0.2);
    final c = ProviderContainer(overrides: [
      trackersProvider.overrideWithValue({Tracker.tr4ker: tracker}),
      transmissionProvider.overrideWithValue(transmission),
      torrentsProvider.overrideWith(FakeTorrents.new),
      c411SiteApiProvider.overrideWithValue(null),
    ]);
    addTearDown(c.dispose);
    final notifier = c.read(reseedProvider.notifier);
    await notifier.scan(folder: dir.path, tracker: Tracker.tr4ker);

    var state = c.read(reseedProvider);
    final byName = {for (final i in state.items) i.name: i};
    expect({for (final e in byName.entries) e.key: e.value.status}, {
      'Autre.mkv': ReseedStatus.mismatch,
      'Film.A-GRP.mkv': ReseedStatus.match,
      'Inconnu.mkv': ReseedStatus.notFound,
      'Pack-GRP': ReseedStatus.match,
    });
    expect(state.selected.map((i) => i.name), unorderedEquals(['Film.A-GRP.mkv', 'Pack-GRP']));

    // Le film est vu à /srv, le pack ailleurs (chemin faux).
    notifier.toggle(byName['Pack-GRP']!.key, false);
    expect(await notifier.addSelected(folder: dir.path, transmissionFolder: '/srv'), 1);
    expect(transmission.added.single.downloadDir, '/srv');
    expect(transmission.added.single.paused, isTrue);
    expect(transmission.actions, ['torrent-verify [1]', 'torrent-start [1]']);
    state = c.read(reseedProvider);
    expect(state.items.firstWhere((i) => i.name == 'Film.A-GRP.mkv').status, ReseedStatus.added);

    notifier.toggle(byName['Pack-GRP']!.key, true);
    expect(await notifier.addSelected(folder: dir.path, transmissionFolder: '/ailleurs'), 0);
    final pack = c.read(reseedProvider).items.firstWhere((i) => i.name == 'Pack-GRP');
    expect(pack.status, ReseedStatus.incomplete);
    expect(pack.detail, contains('laissé en pause'));
    expect(transmission.actions.where((a) => a.startsWith('torrent-start')), hasLength(1),
        reason: 'pas relancé : il retéléchargerait');
  });
}
