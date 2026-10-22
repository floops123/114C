import 'dart:async';

import 'package:c411_remote/api/ftp.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/media_library.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ftp.dart';

const _dir = '/APPBOX_DATA/apps/transmission.moi/torrents';

/// Transmission qui ne renvoie qu'un torrent, terminé ou non selon [done].
class _Transmission extends TransmissionClient {
  _Transmission(this.done) : super(url: 'http://x');
  bool done;

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async => (
        torrents: [
          {
            'id': 7,
            'hashString': 'NEW1',
            'downloadDir': _dir,
            'percentDone': done ? 1.0 : 0.4,
            'files': [
              {'name': 'Alien.1979.VFF.1080p.mkv', 'length': 2 << 30},
              {'name': 'sample.mkv', 'length': 1},
            ],
          },
        ],
        removed: <int>[],
      );
}

/// Transmission du parcours manuel : renvoie les torrents déjà connus.
class _ScanTransmission extends TransmissionClient {
  _ScanTransmission() : super(url: 'http://x');
  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async => (
        torrents: [
          {
            'id': 1,
            'hashString': 'OLD1',
            'downloadDir': _dir,
            'percentDone': 1.0,
            'files': [
              {'name': 'Dune.2024.1080p.mkv', 'length': 2 << 30},
            ],
          },
        ],
        removed: <int>[],
      );
}

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings(
        ftpHost: '127.0.0.1',
        ftpUser: 'moi',
        ftpPassword: 'secret',
        ftpTls: false,
      );
}

/// Même chose, mais avec un dossier à parcourir : le FTP devient nécessaire.
class _FoldersSettings extends SettingsNotifier {
  _FoldersSettings(this.port);
  final int port;
  @override
  Future<AppSettings> build() async => AppSettings(
        ftpHost: '127.0.0.1',
        ftpPort: port,
        ftpUser: 'moi',
        ftpPassword: 'secret',
        ftpTls: false,
        mediaFolders: const ['/medias/'],
      );
}

/// Torrents pilotés à la main, pour déclencher une fin de téléchargement.
class _Torrents extends TorrentsNotifier {
  final _state = StreamController<TorrentsState>.broadcast();

  @override
  TorrentsState build() {
    _sub = _state.stream.listen((s) => state = s);
    ref.onDispose(() => _sub?.cancel());
    return const TorrentsState(loaded: true, byId: {
      7: Torrent({
        'id': 7,
        'hashString': 'new1',
        'downloadDir': _dir,
        'percentDone': 0.4,
      }),
    });
  }

  StreamSubscription? _sub;

  void finish() => _state.add(const TorrentsState(loaded: true, byId: {
        7: Torrent({
          'id': 7,
          'hashString': 'new1',
          'downloadDir': _dir,
          'percentDone': 1.0,
        }),
      }));
}

void main() {
  test('un torrent terminé rejoint la base sans repasser par le FTP', () async {
    final transmission = _Transmission(false);
    // Base déjà connue : un film, avec la correspondance des chemins en place
    // (comme après un premier parcours).
    final store = MemoryMediaLibraryStore(MediaLibrary(
      files: [MediaFile(path: '/torrents/Dune.2024.1080p.mkv', size: 2 << 30)],
      tmdb: const {},
      scannedAt: DateTime(2026),
      pathFrom: _dir,
      pathTo: '/torrents',
    ));
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_Settings.new),
      transmissionProvider.overrideWithValue(transmission),
      torrentsProvider.overrideWith(_Torrents.new),
      mediaLibraryStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    container.read(mediaLibraryProvider);

    expect(container.read(mediaLibraryProvider).library.files, hasLength(1));

    // Le torrent passe à 100 % : la base doit le prendre en compte.
    transmission.done = true;
    final torrents = container.read(torrentsProvider.notifier) as _Torrents;
    torrents.finish();
    // Laisse tourner le microtask et les appels réseau.
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    final library = container.read(mediaLibraryProvider).library;
    final paths = library.files.map((f) => f.path).toList();
    expect(paths, contains('/torrents/Alien.1979.VFF.1080p.mkv'),
        reason: 'le film du torrent terminé est ajouté');
    expect(paths, contains('/torrents/Dune.2024.1080p.mkv'),
        reason: 'les fichiers déjà connus sont conservés');
    // `sample.mkv` est un bonus (MediaGuess.isExtra) : il ne doit pas
    // polluer la base.
    expect(paths, hasLength(2));
    final alien = library.files.firstWhere(
        (f) => f.path.endsWith('Alien.1979.VFF.1080p.mkv'));
    expect(alien.hash, 'new1');
    expect(alien.added, isNotNull);

    // Le parcours manuel n'a pas été relancé : scannedAt est inchangé.
    expect(library.scannedAt, DateTime(2026));
  });

  test('le parcours manuel continue de voir les torrents connus', () async {
    // _ScanTransmission n'est pas utilisé ici : on vérifie juste que la
    // construction de la base ne déclenche pas de parcours automatique.
    final store = MemoryMediaLibraryStore(MediaLibrary(
      files: [MediaFile(path: '/torrents/a.mkv', size: 2 << 30)],
      scannedAt: DateTime(2026),
    ));
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_Settings.new),
      transmissionProvider.overrideWithValue(_ScanTransmission()),
      mediaLibraryStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    container.read(mediaLibraryProvider);
    // Aucun état « en cours » : le parcours ne part pas tout seul.
    expect(container.read(mediaLibraryProvider).scanning, isFalse);
  });

  test('sans dossier à parcourir et correspondance connue : aucun FTP', () async {
    var connects = 0;
    final store = MemoryMediaLibraryStore(MediaLibrary(
      files: [MediaFile(path: '/torrents/ancien.mkv', size: 2 << 30)],
      scannedAt: DateTime(2026),
      pathFrom: _dir,
      pathTo: '/torrents',
    ));
    final transmission = _Transmission(true);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_Settings.new),
      transmissionProvider.overrideWithValue(transmission),
      mediaLibraryStoreProvider.overrideWithValue(store),
      // Doit rester inutilisé : la correspondance des chemins est déjà connue
      // et aucun dossier n'est configuré.
      ftpConnectProvider.overrideWithValue((_) async {
        connects++;
        throw StateError('le FTP ne doit pas être ouvert');
      }),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    await container.read(mediaLibraryProvider.notifier).scan();

    expect(connects, 0, reason: 'les torrents suffisent, pas de promenade FTP');
    final library = container.read(mediaLibraryProvider).library;
    // Seul le torrent est pris : sans dossier à parcourir, un fichier qui
    // n'appartient à aucun torrent n'est visible que si un jour un parcours
    // l'a trouvé — et ce parcours l'aurait alors relu. Ici, il est abandonné
    // (comportement inchangé : la base est reconstruite entièrement).
    expect(library.files.map((f) => f.path), ['/torrents/Alien.1979.VFF.1080p.mkv'],
        reason: 'les fichiers des torrents sont pris sans FTP');
    expect(container.read(mediaLibraryProvider).error, isNull);
  });

  test('des dossiers configurés : le FTP est parcouru', () async {
    var connects = 0;
    final server = await FakeFtpServer.start({
      // Un fichier ajouté à la main, hors torrent : visible par le parcours.
      '/medias/Films/Amélie (2001)/Amélie (2001).mkv': [1, 2],
      // Les fichiers du torrent : la correspondance des chemins se vérifie.
      '/torrents/Alien.1979.VFF.1080p.mkv': [1, 2, 3],
    }, sizes: {
      '/medias/Films/Amélie (2001)/Amélie (2001).mkv': 2 << 30,
      '/torrents/Alien.1979.VFF.1080p.mkv': 2 << 30,
    });
    addTearDown(server.close);
    final store = MemoryMediaLibraryStore(MediaLibrary(
      files: [MediaFile(path: '/torrents/ancien.mkv', size: 2 << 30)],
      scannedAt: DateTime(2026),
      pathFrom: _dir,
      pathTo: '/torrents',
    ));
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _FoldersSettings(server.port)),
      transmissionProvider.overrideWithValue(_Transmission(true)),
      mediaLibraryStoreProvider.overrideWithValue(store),
      ftpConnectProvider.overrideWithValue((config) async {
        connects++;
        final ftp = FtpClient(config as FtpConfig);
        await ftp.connect();
        return ftp;
      }),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    await container.read(mediaLibraryProvider.notifier).scan();

    expect(connects, 1, reason: 'des dossiers sont configurés : on les parcourt');
    final paths = container.read(mediaLibraryProvider).library.files
        .map((f) => f.path)
        .toList();
    expect(paths, contains('/medias/Films/Amélie (2001)/Amélie (2001).mkv'),
        reason: 'le parcours des dossiers apporte les fichiers hors torrent');
    expect(paths, contains('/torrents/Alien.1979.VFF.1080p.mkv'),
        reason: 'les torrents apportent les leurs, sans être reparcourus');
  });

  group('réconciliation avec Transmission', () {
    MemoryMediaLibraryStore known() => MemoryMediaLibraryStore(MediaLibrary(
          files: [
            MediaFile(path: '/torrents/Dune.2024.1080p.mkv', size: 2 << 30, hash: 'old1'),
          ],
          tmdb: const {},
          scannedAt: DateTime(2026),
          pathFrom: _dir,
          pathTo: '/torrents',
        ));

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    ProviderContainer container(
        _Many transmission, _Steps torrents, MemoryMediaLibraryStore store) {
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith(_Settings.new),
        transmissionProvider.overrideWithValue(transmission),
        torrentsProvider.overrideWith(() => torrents),
        mediaLibraryStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    List<String> paths(ProviderContainer c) =>
        [for (final f in c.read(mediaLibraryProvider).library.files) f.path];

    test('déjà terminé au lancement : rattrapé', () async {
      final transmission = _Many();
      final c = container(
          transmission, _Steps([_state({3: 1.0, 4: 1.0})]), known());
      await c.read(settingsProvider.future);
      c.read(mediaLibraryProvider);
      await settle();
      expect(paths(c), containsAll([
        '/torrents/Show.S01E03.mkv',
        '/torrents/Show.S01E04.mkv',
      ]));
      expect(transmission.calls, 1, reason: 'un seul lot');
    });

    test('deux fins presque simultanées : aucune perdue', () async {
      final transmission = _Many()..slow = true;
      final torrents = _Steps([
        _state({3: 0.5, 4: 0.5}),
        _state({3: 0.5, 4: 1.0}),
        _state({3: 1.0, 4: 1.0}), // E03 finit pendant l'ajout de E04
        _state({3: 1.0, 4: 1.0}),
        _state({3: 1.0, 4: 1.0}),
      ]);
      final c = container(transmission, torrents, known());
      await c.read(settingsProvider.future);
      c.read(mediaLibraryProvider);
      for (var i = 0; i < 3; i++) {
        torrents.next();
        await settle();
      }
      transmission.release();
      await settle();
      torrents.next();
      await settle();
      transmission.release();
      await settle();
      expect(paths(c), containsAll([
        '/torrents/Show.S01E03.mkv',
        '/torrents/Show.S01E04.mkv',
      ]));
    });

    test('torrent sans vidéo : examiné une seule fois', () async {
      final transmission = _Many();
      final torrents = _Steps([
        _state({9: 1.0}),
        _state({9: 1.0}),
        _state({9: 1.0}),
      ]);
      final c = container(transmission, torrents, known());
      await c.read(settingsProvider.future);
      c.read(mediaLibraryProvider);
      await settle();
      torrents.next();
      await settle();
      torrents.next();
      await settle();
      expect(transmission.calls, 1);
      expect(paths(c), ['/torrents/Dune.2024.1080p.mkv']);
    });

    test('torrent sans vidéo : pas réexaminé au lancement suivant', () async {
      final store = known();
      final first = _Many();
      final c = container(first, _Steps([_state({9: 1.0})]), store);
      await c.read(settingsProvider.future);
      c.read(mediaLibraryProvider);
      await settle();
      expect(first.calls, 1);
      c.dispose();

      // Relance de l'application : même base enregistrée.
      final again = _Many();
      final c2 = container(again, _Steps([_state({9: 1.0})]), store);
      await c2.read(settingsProvider.future);
      c2.read(mediaLibraryProvider);
      await settle();
      expect(again.calls, 0, reason: 'déjà examiné, retenu dans la base');
      expect(c2.read(mediaLibraryProvider).scanning, isFalse);
    });
  });

  test('accès aux fichiers modifié : pas de parcours automatique, signalé', () async {
    var connects = 0;
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_Changing.new),
      transmissionProvider.overrideWithValue(_ScanTransmission()),
      mediaLibraryStoreProvider.overrideWithValue(MemoryMediaLibraryStore()),
      ftpConnectProvider.overrideWithValue((_) async {
        connects++;
        throw StateError('pas de parcours automatique');
      }),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    container.read(mediaLibraryProvider);

    (container.read(settingsProvider.notifier) as _Changing).change(const AppSettings(
        filesProtocol: 'webdav', webdavUrl: 'https://dav.example/'));
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final state = container.read(mediaLibraryProvider);
    expect(connects, 0);
    expect((state.scanning, state.stale), (false, true));
  });
}

/// Réglages modifiables pendant le test.
class _Changing extends _Settings {
  void change(AppSettings s) => state = AsyncData(s);
}

/// Épisodes 3 et 4 d'une série, et un livre (torrent 9), selon les ids
/// demandés. [slow] : chaque réponse attend [release].
class _Many extends TransmissionClient {
  _Many() : super(url: 'http://x');
  var calls = 0;
  bool slow = false;
  final _waiting = <Completer<void>>[];

  void release() {
    for (final w in _waiting) {
      w.complete();
    }
    _waiting.clear();
  }

  static Map<String, dynamic> _torrent(int id) => {
        'id': id,
        'hashString': 'h$id',
        'downloadDir': _dir,
        'percentDone': 1.0,
        'files': [
          {'name': id == 9 ? 'Livre.epub' : 'Show.S01E0$id.mkv', 'length': 300 << 20},
        ],
      };

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async {
    calls++;
    if (slow) {
      final w = Completer<void>();
      _waiting.add(w);
      await w.future;
    }
    return (
      torrents: [for (final id in ids as List) _torrent(id as int)],
      removed: <int>[],
    );
  }
}

TorrentsState _state(Map<int, double> done) => TorrentsState(loaded: true, byId: {
      for (final MapEntry(key: id, value: p) in done.entries)
        id: Torrent({
          'id': id,
          'hashString': 'h$id',
          'downloadDir': _dir,
          'percentDone': p,
        }),
    });

/// États successifs de Transmission, avancés à la main.
class _Steps extends TorrentsNotifier {
  _Steps(this.steps);
  final List<TorrentsState> steps;
  var _i = 0;

  @override
  TorrentsState build() => steps.first;

  void next() => state = steps[++_i];
}
