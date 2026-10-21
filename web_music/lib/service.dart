import 'dart:async';
import 'dart:io';

import 'package:c411_core/music_name.dart';

import 'library.dart';
import 'musicbrainz.dart';
import 'scanner.dart';

/// La discothèque vivante : lue au démarrage, reparcourue régulièrement et
/// sur demande, puis complétée album par album par MusicBrainz.
class MusicService {
  MusicService({
    required this.statePath,
    required this.scanner,
    required this.musicBrainz,
    this.scanEvery = Duration.zero,
    this.busyPause = const Duration(minutes: 1),
  }) : _library = MusicLibrary.read(statePath) {
    _catalog = Catalog.of(_library);
  }

  final String statePath;
  final Scanner scanner;
  final MusicBrainz musicBrainz;
  final Duration scanEvery;

  /// Pause quand MusicBrainz reste saturé.
  final Duration busyPause;

  MusicLibrary _library;
  late Catalog _catalog;
  Timer? _timer;

  bool scanning = false;
  bool identifying = false;

  /// Étape en cours (« Dossier /musique/… », « MusicBrainz 3/40 »).
  String? step;
  String? warning;
  String? error;

  MusicLibrary get library => _library;
  Catalog get catalog => _catalog;

  /// Parcours au démarrage, puis tous les [scanEvery].
  void start() {
    unawaited(scan());
    if (scanEvery > Duration.zero) {
      _timer = Timer.periodic(scanEvery, (_) => unawaited(scan()));
    }
  }

  Map<String, Object?> status() => {
        'scanning': scanning,
        'identifying': identifying,
        'step': step,
        'warning': warning,
        'error': error,
        'scannedAt': _library.scannedAt?.toIso8601String(),
        'albums': _catalog.albums.length,
        'identified': _catalog.albums.where((a) => a.release != null).length,
      };

  void _set(MusicLibrary library) {
    _library = library;
    _catalog = Catalog.of(library);
    try {
      library.write(statePath);
    } on FileSystemException catch (e) {
      error = 'Discothèque non enregistrée : ${e.message}';
    }
  }

  /// Reparcourt le serveur, puis cherche les albums nouveaux sur
  /// MusicBrainz. Sans effet si un parcours est en cours.
  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    error = null;
    try {
      final result = await scanner.scan(_library, onStatus: (s) => step = s);
      warning = result.warning;
      _set(result.library);
    } on Object catch (e) {
      error = 'Parcours impossible : $e';
    } finally {
      scanning = false;
      step = null;
    }
    await identify();
  }

  /// Albums pas encore cherchés (ou cherchés en vain il y a plus d'une
  /// semaine) : leur fiche MusicBrainz, un par un.
  Future<void> identify() async {
    if (identifying) return;
    identifying = true;
    try {
      final pending = [
        for (final a in _catalog.albums)
          if (_library.mb[a.dir] == null || _library.mb[a.dir]!.stale) a,
      ];
      for (final (i, album) in pending.indexed) {
        step = 'MusicBrainz ${i + 1}/${pending.length} : ${album.guess.title}';
        MbRelease? release;
        Object? failure;
        // Saturé : une pause, puis le même album, trois fois au plus.
        for (var tries = 0; tries < 3; tries++) {
          try {
            release = await musicBrainz.find(album.guess, trackCount: album.tracks.length);
            failure = null;
            break;
          } on MusicBrainzBusy catch (e) {
            failure = e;
            step = 'MusicBrainz saturé, nouvel essai dans une minute…';
            await Future<void>.delayed(busyPause);
          } on Object catch (e) {
            failure = e;
            break;
          }
        }
        if (failure != null) {
          // Réseau ou service en panne : on reprendra au prochain parcours.
          error = 'MusicBrainz injoignable : $failure';
          break;
        }
        final mb = {..._library.mb, album.dir: MbMatch(checked: DateTime.now(), release: release)};
        _library = MusicLibrary(
          files: _library.files,
          mb: mb,
          scannedAt: _library.scannedAt,
          pathFrom: _library.pathFrom,
          pathTo: _library.pathTo,
        );
        // Enregistré et visible au fil de l'eau.
        if (release != null || i == pending.length - 1 || i % 10 == 9) _set(_library);
      }
      _set(_library);
    } finally {
      identifying = false;
      step = null;
    }
  }

  /// Oublie la fiche d'un album et la recherche à nouveau.
  Future<void> reidentify(String albumId) async {
    final album = _catalog.album(albumId);
    if (album == null) return;
    _library.mb.remove(album.dir);
    await identify();
  }

  void close() {
    _timer?.cancel();
    scanner.close();
    musicBrainz.close();
  }
}

/// Nombre de dossiers d'albums distincts parmi [files] (pour les messages).
int albumCount(Iterable<MusicFile> files) => {for (final f in files) albumDirOf(f.path)}.length;
