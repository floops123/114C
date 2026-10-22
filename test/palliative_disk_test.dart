import 'dart:io';
import 'dart:typed_data';

import 'package:c411_remote/api/c411.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/bencode.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/cross_seed.dart';
import 'package:c411_remote/state/media_library.dart';
import 'package:c411_remote/state/palliative.dart';
import 'package:c411_remote/state/palliative_match.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ftp.dart';
import 'palliative_test.dart' show FakeTorrents, FakeTracker;
import 'torrent_fixture.dart';


Release _rel(String id, String name, int size) => Release(
    tracker: Tracker.c411, id: id, name: name, size: size, seeders: 0, infoHash: 'h$id', createdAt: DateTime(2026));

class _Site extends C411SiteApi {
  _Site(this.items, this.files) : super('cookie');
  final List<Release> items;
  final Map<String, Uint8List> files;
  final downloads = <String>[];

  @override
  Future<ReleasePage> palliative({String age = 'recent', int page = 1, int perPage = 25}) async =>
      ReleasePage(page == 1 ? items : const [], page, 1, items.length);

  @override
  Future<Uint8List> downloadTorrent(Release release) async {
    downloads.add(release.id);
    return files[release.id]!;
  }
}

class _Transmission extends TransmissionClient {
  _Transmission({super.url = 'http://seedbox:9091/transmission/rpc', this.torrents = const []});
  final List<Map<String, dynamic>> torrents;
  final added = <(Uint8List?, AddOptions)>[];
  final actions = <(String, List<int>?)>[];
  final renamed = <(int, String, String)>[];

  @override
  Future<({bool added, String? hash})> addTorrentWithHash(
      {Uint8List? metainfo, String? filename, AddOptions options = const AddOptions()}) async {
    added.add((metainfo, options));
    return (added: true, hash: 'nouveau');
  }

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async => (
        torrents: ids == null ? torrents : [{'id': 42, 'hashString': 'nouveau'}],
        removed: <int>[],
      );

  @override
  Future<Map<String, dynamic>> sessionGet() async => {'download-dir': '/APPBOX/torrents'};

  @override
  Future<void> renamePath(int id, String path, String name) async => renamed.add((id, path, name));

  @override
  Future<void> action(String method, List<int>? ids) async => actions.add((method, ids));
}

class _Settings extends SettingsNotifier {
  _Settings(this.port);
  final int port;
  @override
  Future<AppSettings> build() async => AppSettings(
      ftpHost: '127.0.0.1', ftpPort: port, ftpUser: 'moi', ftpPassword: 'secret', ftpTls: false);
}

void main() {
  late Directory dir;
  final movie = testBytes(100, 1); // Film à un fichier, 7 morceaux.
  final a = testBytes(40, 2), b = testBytes(25, 3); // Pack à deux fichiers.
  final movieTorrent = realTorrent('Film.A-GRP.mkv', [(const [], movie)]);
  final packTorrent = realTorrent('Pack-GRP', [(['a.txt'], a), (['sous', 'b.txt'], b)]);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('palliatif');
    // Le film, renommé ; un autre fichier de même taille mais différent ; le
    // pack dans un dossier au nom différent.
    File('${dir.path}/Mon film.mkv').writeAsBytesSync(movie);
    File('${dir.path}/Autre/meme taille.mkv')
      ..createSync(recursive: true)
      ..writeAsBytesSync(testBytes(100, 9));
    File('${dir.path}/Mon pack/a.txt')
      ..createSync(recursive: true)
      ..writeAsBytesSync(a);
    File('${dir.path}/Mon pack/sous/b.txt')
      ..createSync(recursive: true)
      ..writeAsBytesSync(b);
    File('${dir.path}/.cache/ignoré').createSync(recursive: true);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('correspondance', () {
    test('disque : tailles, chemins, empreintes du premier et du dernier morceau', () async {
      final index = await LocalIndex.scan(dir.path);
      expect(index.files, hasLength(4), reason: 'sans les dossiers cachés');
      expect(index.mayHold(100), isTrue);
      expect(index.mayHold(65), isTrue, reason: 'un dossier de 65 octets');
      expect(index.mayHold(64), isFalse);

      final film = await matchLocal(TorrentContent.parse(movieTorrent), index);
      expect(film?.root, '${dir.path}/Mon film.mkv', reason: 'pas l’autre fichier de même taille');
      final pack = await matchLocal(TorrentContent.parse(packTorrent), index);
      expect(pack?.root, '${dir.path}/Mon pack');
      expect([for (final f in pack!.files) (f.$1, f.$2)], [
        ('Pack-GRP/a.txt', '${dir.path}/Mon pack/a.txt'),
        ('Pack-GRP/sous/b.txt', '${dir.path}/Mon pack/sous/b.txt'),
      ]);

      // Même taille, autres données : refusé par les empreintes.
      File('${dir.path}/Mon film.mkv').writeAsBytesSync(testBytes(100, 5));
      expect(await matchLocal(TorrentContent.parse(movieTorrent), await LocalIndex.scan(dir.path)), isNull);
    });

    test('Transmission : mêmes fichiers dans un torrent terminé', () {
      final content = TorrentContent.parse(packTorrent);
      Map<String, dynamic> t(String name, List<(String, int)> files, {double done = 1}) => {
            'name': name,
            'percentDone': done,
            'files': [for (final (n, l) in files) {'name': n, 'length': l}],
          };
      final same = t('Pack-GRP', [('Pack-GRP/a.txt', 40), ('Pack-GRP/sous/b.txt', 25)]);
      expect(matchClient(content, [t('Autre', [('Autre/a.txt', 65)]), same]), same);
      expect(matchClient(content, [{...same, 'percentDone': 0.5}]), isNull, reason: 'pas terminé');
      expect(matchClient(content, [t('Pack', [('Pack/a.txt', 40), ('Pack/sous/b.txt', 25)])]), isNull,
          reason: 'autres chemins : le client ne les trouverait pas');
    });
  });

  group('soins palliatifs', () {
    ProviderContainer container({
      required _Transmission transmission,
      required _Site site,
      int ftpPort = 1,
      MediaLibrary? library,
    }) {
      final c = ProviderContainer(overrides: [
        transmissionProvider.overrideWithValue(transmission),
        trackersProvider.overrideWithValue({Tracker.c411: FakeTracker(Tracker.c411)}),
        c411SiteApiProvider.overrideWithValue(site),
        palliativeStoreProvider.overrideWithValue(MemoryPalliativeStore()),
        torrentsProvider.overrideWith(FakeTorrents.new),
        settingsProvider.overrideWith(() => _Settings(ftpPort)),
        mediaLibraryStoreProvider.overrideWithValue(MemoryMediaLibraryStore(library)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    final items = [
      _rel('f', 'Film.A-GRP', movie.length),
      _rel('p', 'Pack-GRP', a.length + b.length),
      _rel('x', 'Absent-GRP', 12345),
    ];
    final files = {'f': movieTorrent, 'p': packTorrent};

    test('dans Transmission : cross-seed sur les mêmes fichiers', () async {
      final transmission = _Transmission(torrents: [
        {
          'id': 7, 'hashString': 'autre', 'name': 'Pack-GRP', 'downloadDir': '/APPBOX/torrents/tr4ker',
          'percentDone': 1,
          'files': [
            {'name': 'Pack-GRP/a.txt', 'length': 40},
            {'name': 'Pack-GRP/sous/b.txt', 'length': 25},
          ],
        },
      ]);
      final site = _Site(items, files);
      final c = container(transmission: transmission, site: site);
      await c.read(settingsProvider.future);
      await c.read(palliativeProvider.notifier).scanClient();

      final state = c.read(palliativeProvider);
      expect({for (final i in state.items) i.key: i.status}, {
        'f': PalliativeStatus.noMatch,
        'p': PalliativeStatus.seeding,
        'x': PalliativeStatus.noMatch,
      });
      expect(site.downloads, ['p'], reason: '.torrent téléchargé seulement si la taille correspond');
      final (metainfo, options) = transmission.added.single;
      expect(metainfo, packTorrent);
      expect(options.downloadDir, '/APPBOX/torrents/tr4ker');
      expect(options.labels, [CrossSeedNotifier.label]);
      expect(state.running, isFalse);
    });

    test('sur l’ordinateur, Transmission sur le serveur : envoi par FTP puis ajout', () async {
      final server = await FakeFtpServer.start({'/torrents/existant.mkv': [1]});
      addTearDown(server.close);
      final transmission = _Transmission();
      final c = container(
        transmission: transmission,
        site: _Site(items, files),
        ftpPort: server.port,
        library: MediaLibrary(pathFrom: '/APPBOX', pathTo: ''),
      );
      await c.read(settingsProvider.future);
      await c.read(palliativeProvider.notifier).scanFolder(dir.path);

      final state = c.read(palliativeProvider);
      expect({for (final i in state.items) i.key: i.status}, {
        'f': PalliativeStatus.seeding,
        'p': PalliativeStatus.seeding,
        'x': PalliativeStatus.noMatch,
      });
      // Aux chemins du torrent, dans le dossier de Transmission vu du FTP.
      expect(server.files['/torrents/Film.A-GRP.mkv'], movie);
      expect(server.files['/torrents/Pack-GRP/a.txt'], a);
      expect(server.files['/torrents/Pack-GRP/sous/b.txt'], b);
      expect([for (final (m, o) in transmission.added) (m, o.downloadDir)], [
        (movieTorrent, '/APPBOX/torrents'),
        (packTorrent, '/APPBOX/torrents'),
      ]);
    });

    test('sur l’ordinateur, chemins du serveur inconnus : erreur claire, rien d’ajouté', () async {
      final transmission = _Transmission();
      final c = container(transmission: transmission, site: _Site(items, files));
      await c.read(settingsProvider.future);
      await c.read(palliativeProvider.notifier).scanFolder(dir.path);
      final film = c.read(palliativeProvider).items.firstWhere((i) => i.key == 'f');
      expect(film.status, PalliativeStatus.error);
      expect(film.detail, contains('parcours'));
      expect(transmission.added, isEmpty);
    });

    test('sur l’ordinateur, Transmission local : partagé en place, renommé', () async {
      final transmission = _Transmission(url: 'http://127.0.0.1:9091/transmission/rpc');
      final c = container(transmission: transmission, site: _Site(items, files));
      await c.read(settingsProvider.future);
      await c.read(palliativeProvider.notifier).scanFolder(dir.path);

      expect([for (final (_, o) in transmission.added) (o.downloadDir, o.paused)], [
        (dir.path, true),
        (dir.path, true),
      ]);
      // Le fichier et le dossier ont un autre nom que dans le torrent.
      expect(transmission.renamed, [(42, 'Film.A-GRP.mkv', 'Mon film.mkv'), (42, 'Pack-GRP', 'Mon pack')]);
      expect([for (final (m, ids) in transmission.actions) '$m $ids'], [
        'torrent-verify [42]', 'torrent-start [42]',
        'torrent-verify [42]', 'torrent-start [42]',
      ]);
    });
  });
}
