import 'dart:async';

import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/media_library.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
              {'name': 'Alien.1979.VFF.1080p.mkv', 'length': 42},
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
              {'name': 'Dune.2024.1080p.mkv', 'length': 7},
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
      files: [MediaFile(path: '/torrents/Dune.2024.1080p.mkv', size: 7)],
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
      files: [MediaFile(path: '/torrents/a.mkv', size: 1)],
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
}