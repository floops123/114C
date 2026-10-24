import 'dart:async';
import 'dart:io';

import 'discogs.dart';
import 'library.dart';
import 'musicbrainz.dart';

/// La discothèque vivante : la musique que l'application a relevée pendant
/// son parcours (relue quand sa base change), complétée album par album par
/// MusicBrainz, et par Discogs si un jeton est donné.
class MusicService {
  MusicService({
    required this.appLibrary,
    required this.statePath,
    required this.musicBrainz,
    this.discogs,
    this.checkEvery = const Duration(seconds: 30),
    this.busyPause = const Duration(minutes: 1),
  }) : _library = MusicLibrary(mb: MusicLibrary.readMb(statePath)) {
    _catalog = Catalog.of(_library);
  }

  /// Préférences de l'application (sa base).
  final String appLibrary;

  /// Fiches MusicBrainz (et pochettes à côté).
  final String statePath;
  final MusicBrainz musicBrainz;

  /// Albums inconnus de MusicBrainz, pochettes et styles manquants.
  final Discogs? discogs;

  /// Intervalle de vérification de la base de l'application.
  final Duration checkEvery;

  /// Pause quand MusicBrainz reste saturé.
  final Duration busyPause;

  MusicLibrary _library;
  late Catalog _catalog;
  DateTime? _modified;
  Timer? _timer;

  bool identifying = false;

  /// Étape en cours (« MusicBrainz 3/40 : Moon Safari »).
  String? step;
  String? error;

  MusicLibrary get library => _library;
  Catalog get catalog => _catalog;

  /// Lit la base, puis la surveille.
  void start() {
    refresh();
    _timer = Timer.periodic(checkEvery, (_) => refresh());
  }

  /// Relit la base de l'application si elle a changé, et cherche les
  /// nouveaux albums sur MusicBrainz. Vrai si elle a changé.
  bool refresh() {
    final file = File(appLibrary);
    final modified = file.existsSync() ? file.lastModifiedSync() : null;
    if (modified == null || modified == _modified) return false;
    try {
      final app = MusicLibrary.parseApp(file.readAsStringSync());
      _modified = modified;
      _library = _library.copyWith(files: app.files, scannedAt: app.scannedAt);
      _catalog = Catalog.of(_library);
      error = null;
    } on Object catch (e) {
      // Fichier en cours d'écriture : relu à la prochaine vérification.
      error = 'Base de l’application illisible : $e';
      return false;
    }
    unawaited(identify());
    return true;
  }

  Map<String, Object?> status() => {
        'identifying': identifying,
        'step': step,
        'error': error,
        'scannedAt': _library.scannedAt?.toIso8601String(),
        'albums': _catalog.music.length,
        'identified': _catalog.music.where((a) => a.release != null).length,
        'audiobooks': _catalog.albums.where((a) => a.kind == AlbumKind.audiobook).length,
        'discogs': discogs != null,
        'fromDiscogs': _catalog.albums.where((a) => a.release?.source == 'discogs').length,
        'discogsProblem': discogs?.problem,
      };

  void _save() {
    _catalog = Catalog.of(_library);
    try {
      _library.writeMb(statePath);
    } on FileSystemException catch (e) {
      error = 'Fiches non enregistrées : ${e.message}';
    }
  }

  /// Discogs n'a pas encore été consulté pour [m], alors qu'il pourrait
  /// apporter quelque chose (fiche, pochette, styles).
  bool _wantsDiscogs(MbMatch? m) =>
      discogs != null &&
      m != null &&
      m.discogs == null &&
      (m.release == null || (m.release!.source == 'musicbrainz' && (!m.release!.cover || m.release!.genres.isEmpty)));

  /// Albums pas encore cherchés (ou cherchés en vain il y a plus d'une
  /// semaine) : leur fiche MusicBrainz, un par un. Puis Discogs, une fois par
  /// album : la fiche s'il est inconnu de MusicBrainz, sinon pochette et
  /// styles s'il en manque.
  Future<void> identify() async {
    if (identifying) return;
    identifying = true;
    try {
      final pending = [
        // La musique seulement : un livre audio n'a pas de fiche MusicBrainz.
        for (final a in _catalog.music)
          if (_library.mb[a.dir] == null || _library.mb[a.dir]!.stale || _wantsDiscogs(_library.mb[a.dir])) a,
      ];
      for (final (i, album) in pending.indexed) {
        final known = _library.mb[album.dir];
        if (known != null && !known.stale) {
          // Déjà cherché sur MusicBrainz : seulement Discogs.
          step = 'Discogs ${i + 1}/${pending.length} : ${album.guess.title}';
          _library.mb[album.dir] = await _withDiscogs(album, known.release, checked: known.checked);
          if (i % 10 == 9) _save();
          continue;
        }
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
          // Réseau ou service en panne : repris au prochain changement de
          // la base, ou au redémarrage.
          error = 'MusicBrainz injoignable : $failure';
          break;
        }
        final match = MbMatch(checked: DateTime.now(), release: release);
        _library.mb[album.dir] = _wantsDiscogs(match) ? await _withDiscogs(album, release, checked: match.checked) : match;
        // Enregistré et visible au fil de l'eau.
        if (release != null || i % 10 == 9) _save();
      }
      _save();
    } finally {
      identifying = false;
      step = null;
    }
  }

  /// [release] (de MusicBrainz, ou null) complétée ou remplacée par Discogs.
  Future<MbMatch> _withDiscogs(Album album, MbRelease? release, {required DateTime checked}) async {
    final d = discogs!;
    if (!d.ready) return MbMatch(checked: checked, release: release);
    final result = release == null
        ? await d.find(album.guess, trackCount: album.tracks.length)
        : await d.complete(release, album.guess);
    return MbMatch(checked: checked, release: result ?? release, discogs: DateTime.now());
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
    musicBrainz.close();
    discogs?.close();
  }
}
