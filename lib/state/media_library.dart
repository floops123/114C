import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/ftp.dart';
import '../api/media_relay.dart';
import '../api/tmdb.dart';
import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/media_name.dart';
import '../core/preferences.dart';
import '../core/release_name.dart';
import '../core/settings.dart';
import '../core/titles.dart';

// Notre propre base de films et séries : les fichiers vidéo des torrents
// terminés et des dossiers choisis, lus sur le FTP du serveur, reconnus
// d'après leur nom puis rattachés à leur fiche TMDB. Rangée sur l'appareil.

/// Un fichier vidéo du serveur, chemin FTP.
class MediaFile {
  MediaFile({required this.path, required this.size, this.hash, this.added});

  factory MediaFile.fromJson(Map<String, dynamic> json) => MediaFile(
        path: json['path'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
        hash: json['hash'] as String?,
        added: DateTime.tryParse(json['added'] as String? ?? ''),
      );

  final String path;
  final int size;

  /// Infohash du torrent d'origine, s'il vient de Transmission.
  final String? hash;

  /// Première apparition dans la base.
  final DateTime? added;

  late final MediaGuess guess = MediaGuess.parse(path);
  String get name => path.split('/').last;

  /// Clé de reprise de lecture.
  String get resumeKey => 'ftp:$path';

  MediaFile copyWith({String? hash, DateTime? added}) => MediaFile(
      path: path, size: size, hash: hash ?? this.hash, added: added ?? this.added);

  Map<String, dynamic> toJson() => {
        'path': path,
        'size': size,
        'hash': ?hash,
        'added': ?added?.toIso8601String(),
      };
}

/// Un film ou une série de la base, avec ses fichiers.
class MediaTitle {
  MediaTitle(this.key, this.files, this.tmdb);

  final String key;
  final List<MediaFile> files;

  /// Fiche TMDB, si elle a été trouvée.
  final TmdbTitle? tmdb;

  MediaGuess get _guess => files.first.guess;
  TmdbType get type => _guess.isEpisode ? TmdbType.tv : TmdbType.movie;
  bool get isSeries => type == TmdbType.tv;
  String get title => tmdb?.title ?? _guess.title;
  int? get year => tmdb?.year ?? _guess.year;
  DateTime? get added => files
      .map((f) => f.added)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

  /// Épisodes par saison, triés.
  Map<int, List<MediaFile>> get seasons {
    final bySeason = <int, List<MediaFile>>{};
    for (final f in files) {
      (bySeason[f.guess.season ?? 0] ??= []).add(f);
    }
    for (final list in bySeason.values) {
      list.sort((a, b) => (a.guess.episode ?? 0).compareTo(b.guess.episode ?? 0));
    }
    return Map.fromEntries(
        bySeason.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  /// Versions d'un film (ou d'un épisode), la meilleure d'abord.
  static List<MediaFile> best(List<MediaFile> files) => [...files]
    ..sort((a, b) {
      int res(MediaFile f) =>
          int.tryParse(RegExp(r'\d+').stringMatch(f.guess.resolution ?? '') ?? '') ?? 0;
      final r = res(b).compareTo(res(a));
      return r != 0 ? r : b.size.compareTo(a.size);
    });
}

class MediaLibrary {
  MediaLibrary({
    this.files = const [],
    this.tmdb = const {},
    this.scannedAt,
    this.pathFrom,
    this.pathTo,
  });

  factory MediaLibrary.fromJson(Map<String, dynamic> json) => MediaLibrary(
        files: [
          for (final f in (json['files'] as List? ?? const []).whereType<Map<String, dynamic>>())
            MediaFile.fromJson(f),
        ],
        tmdb: {
          for (final MapEntry(:key, :value)
              in ((json['tmdb'] as Map?) ?? const {}).entries)
            key as String: value == null
                ? null
                : TmdbTitle.fromJson((value as Map).cast<String, dynamic>()),
        },
        scannedAt: DateTime.tryParse(json['scannedAt'] as String? ?? ''),
        pathFrom: json['pathFrom'] as String?,
        pathTo: json['pathTo'] as String?,
      );

  final List<MediaFile> files;

  /// Clé de regroupement → fiche TMDB ; null : cherchée, rien trouvé.
  final Map<String, TmdbTitle?> tmdb;
  final DateTime? scannedAt;

  /// Chemins Transmission → chemins FTP : [pathFrom] est remplacé par
  /// [pathTo] (souvent vide : le FTP montre la fin du chemin du serveur).
  final String? pathFrom;
  final String? pathTo;

  bool get isEmpty => files.isEmpty;

  static String groupKey(MediaGuess g) => g.isEpisode
      ? 'tv:${titleKey(g.title)}'
      : 'movie:${titleKey(g.title)}:${g.year ?? ''}';

  late final List<MediaTitle> titles = () {
    final groups = <String, List<MediaFile>>{};
    for (final f in files) {
      (groups[groupKey(f.guess)] ??= []).add(f);
    }
    // Deux noms différents pour la même fiche TMDB (« Dune Part Two » et
    // « Dune Deuxieme Partie ») : regroupés.
    final byTmdb = <String, MediaTitle>{};
    final result = <MediaTitle>[];
    for (final MapEntry(:key, value: list) in groups.entries) {
      final t = tmdb[key];
      final existing = t == null ? null : byTmdb[t.key];
      if (existing != null) {
        existing.files.addAll(list);
        continue;
      }
      final title = MediaTitle(key, list, t);
      if (t != null) byTmdb[t.key] = title;
      result.add(title);
    }
    return result;
  }();

  /// Le titre de la base correspondant à une fiche TMDB.
  MediaTitle? forTmdb(TmdbTitle t) {
    for (final m in titles) {
      if (m.tmdb?.key == t.key) return m;
    }
    final keys = {titleKey(t.title), if (t.originalTitle case final o?) titleKey(o)};
    for (final m in titles) {
      if (m.type != t.type || m.tmdb != null) continue;
      if (!keys.contains(titleKey(m._guess.title))) continue;
      final y = m._guess.year;
      if (t.type == TmdbType.movie && y != null && t.year != null &&
          (y - t.year!).abs() > 1) {
        continue;
      }
      return m;
    }
    return null;
  }

  /// Index pour [forRelease] : infohash, noms de fichiers et de dossiers,
  /// titres (une recherche par tuile des Sorties, à chaque image).
  late final _index = () {
    final byHash = <String, MediaTitle>{};
    final byName = <String, MediaTitle>{};
    final byTitle = <String, List<MediaTitle>>{};
    for (final m in titles) {
      (byTitle[titleKey(m._guess.title)] ??= []).add(m);
      for (final f in m.files) {
        if (f.hash case final h?) byHash[h.toLowerCase()] = m;
        for (final part in f.path.split('/')) {
          if (part.isNotEmpty) byName[part] = m;
        }
        final dot = f.name.lastIndexOf('.');
        if (dot > 0) byName[f.name.substring(0, dot)] = m;
      }
    }
    return (byHash: byHash, byName: byName, byTitle: byTitle);
  }();

  /// Le titre de la base correspondant à une sortie : même torrent, même
  /// nom de fichier ou de dossier, sinon même titre (et année pour un film).
  MediaTitle? forRelease(Release r) {
    if (files.isEmpty) return null;
    final index = _index;
    if (r.infoHash case final h? when index.byHash[h.toLowerCase()] != null) {
      return index.byHash[h.toLowerCase()];
    }
    if (index.byName[r.name] case final m?) return m;
    final name = ReleaseName.parse(r.name);
    final series = name.kind == 'Série' || r.mediaKind == 'tv';
    for (final m in index.byTitle[titleKey(name.title)] ?? const <MediaTitle>[]) {
      if (m.isSeries != series) continue;
      if (!series && name.year != null && m._guess.year != null &&
          (name.year! - m._guess.year!).abs() > 1) {
        continue;
      }
      return m;
    }
    return null;
  }

  MediaLibrary copyWith({
    List<MediaFile>? files,
    Map<String, TmdbTitle?>? tmdb,
    DateTime? scannedAt,
    String? pathFrom,
    String? pathTo,
  }) =>
      MediaLibrary(
        files: files ?? this.files,
        tmdb: tmdb ?? this.tmdb,
        scannedAt: scannedAt ?? this.scannedAt,
        pathFrom: pathFrom ?? this.pathFrom,
        pathTo: pathTo ?? this.pathTo,
      );

  Map<String, dynamic> toJson() => {
        'files': [for (final f in files) f.toJson()],
        'tmdb': {
          for (final MapEntry(:key, :value) in tmdb.entries) key: value?.toJson(),
        },
        'scannedAt': ?scannedAt?.toIso8601String(),
        'pathFrom': ?pathFrom,
        'pathTo': ?pathTo,
      };
}

abstract class MediaLibraryStore {
  MediaLibrary load();
  void save(MediaLibrary library);
}

class PrefsMediaLibraryStore implements MediaLibraryStore {
  PrefsMediaLibraryStore(this._prefs);
  final SharedPreferencesWithCache _prefs;
  static const key = 'mediaLibrary';

  @override
  MediaLibrary load() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return MediaLibrary();
      return MediaLibrary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return MediaLibrary();
    }
  }

  @override
  void save(MediaLibrary library) =>
      _prefs.setString(key, jsonEncode(library.toJson()));
}

class MemoryMediaLibraryStore implements MediaLibraryStore {
  MemoryMediaLibraryStore([MediaLibrary? library]) : _library = library ?? MediaLibrary();
  MediaLibrary _library;
  @override
  MediaLibrary load() => _library;
  @override
  void save(MediaLibrary library) => _library = library;
}

final mediaLibraryStoreProvider = Provider<MediaLibraryStore>((ref) {
  try {
    return PrefsMediaLibraryStore(ref.watch(sharedPrefsProvider));
  } on Object {
    return MemoryMediaLibraryStore(); // Préférences non initialisées (tests).
  }
});

FtpConfig ftpConfigOf(AppSettings s) => FtpConfig(
    host: s.ftpHost,
    port: s.ftpPort,
    user: s.ftpUser,
    password: s.ftpPassword,
    tls: s.ftpTls);

/// Ouvre une connexion FTP (remplacé dans les tests).
final ftpConnectProvider = Provider<Future<FtpClient> Function(FtpConfig)>(
    (ref) => (config) async {
          final ftp = FtpClient(config);
          await ftp.connect();
          return ftp;
        });

/// Relais local pour le lecteur ; null sans FTP configuré.
final mediaRelayProvider = Provider<MediaRelay?>((ref) {
  final s = ref.watch(settingsProvider).value;
  if (s == null || !s.hasFtp) return null;
  final config = ftpConfigOf(s);
  final connect = ref.watch(ftpConnectProvider);
  final relay = MediaRelay(config, connect: () => connect(config));
  ref.onDispose(relay.close);
  return relay;
});

/// Parcours du FTP : fichiers vidéo sous [roots] (sans extraits ni bonus).
Future<List<MediaFile>> scanFolders(FtpClient ftp, List<String> roots,
    {void Function(String path)? onFolder, int depth = 8}) async {
  final found = <MediaFile>[];
  Future<void> walk(String dir, int left) async {
    onFolder?.call(dir);
    final List<FtpEntry> entries;
    try {
      entries = await ftp.list(dir);
    } on FtpException {
      return; // Dossier illisible : on passe.
    }
    for (final e in entries) {
      if (e.name.startsWith('.')) continue;
      final path = dir == '/' ? '/${e.name}' : '$dir/${e.name}';
      if (e.isDir) {
        if (left > 0) await walk(path, left - 1);
      } else if (isVideoPath(path) && !MediaGuess.isExtra(path)) {
        found.add(MediaFile(path: path, size: e.size));
      }
    }
  }

  for (final root in roots) {
    final r = root.trim();
    if (r.isEmpty) continue;
    await walk(r.length > 1 && r.endsWith('/') ? r.substring(0, r.length - 1) : r, depth);
  }
  return found;
}

/// Fichiers vidéo des torrents terminés : (chemin sur le serveur, taille,
/// infohash).
List<({String path, int size, String hash})> completedVideos(
    List<Map<String, dynamic>> torrents) => [
      for (final t in torrents)
        if (((t['percentDone'] as num?) ?? 0) >= 1)
          for (final f in (t['files'] as List? ?? const []).whereType<Map>())
            if ('${t['downloadDir']}/${f['name']}'.replaceAll('//', '/')
                case final path
                when isVideoPath(path) && !MediaGuess.isExtra(path))
              (
                path: path,
                size: (f['length'] as num?)?.toInt() ?? 0,
                hash: t['hashString'] as String? ?? '',
              ),
    ];

/// Retrouve sur le FTP un fichier connu par son chemin sur le serveur :
/// le FTP montre en général la fin du chemin (`/APPBOX_DATA/apps/x/torrents/a.mkv`
/// → `/torrents/a.mkv`). Retourne (préfixe à retirer, préfixe FTP).
Future<(String, String)?> detectPathMap(
    FtpClient ftp, String serverPath, int size, List<String> ftpRoots) async {
  final parts = serverPath.split('/').where((p) => p.isNotEmpty).toList();
  final prefixes = {
    '',
    for (final r in ftpRoots)
      if (r.trim().isNotEmpty && r.trim() != '/') r.trim().replaceAll(RegExp(r'/+$'), ''),
  };
  for (var i = 0; i < parts.length; i++) {
    for (final to in prefixes) {
      final candidate = '$to/${parts.sublist(i).join('/')}';
      final found = await ftp.size(candidate);
      if (found != null && (size == 0 || found == size)) {
        return ('/${parts.sublist(0, i).join('/')}', to);
      }
    }
  }
  return null;
}

class MediaLibraryState {
  const MediaLibraryState(this.library, {this.scanning = false, this.status, this.error});
  final MediaLibrary library;
  final bool scanning;

  /// Étape en cours (« Dossier /torrents/… », « Fiches TMDB 3/12 »).
  final String? status;
  final String? error;
}

class MediaLibraryNotifier extends Notifier<MediaLibraryState> {
  static const staleAfter = Duration(hours: 1);

  /// Réglages qui changent le contenu de la base.
  static String _signature(AppSettings s) => [
        s.ftpHost, s.ftpPort, s.ftpUser, s.ftpTls, ...s.mediaFolders,
      ].join('|');

  @override
  MediaLibraryState build() {
    final library = ref.watch(mediaLibraryStoreProvider).load();
    final stale = library.scannedAt == null ||
        DateTime.now().difference(library.scannedAt!) > staleAfter;
    // Parcours au lancement si la base date, et dès que l'accès FTP ou les
    // dossiers changent.
    ref.listen(settingsProvider, (previous, next) {
      final before = previous?.value, now = next.value;
      if (now == null || !now.hasFtp) return;
      if (before == null ? stale : _signature(before) != _signature(now)) {
        Future(scan);
      }
    }, fireImmediately: true);
    return MediaLibraryState(library);
  }

  void _set(MediaLibraryState s) {
    if (ref.mounted) state = s;
  }

  void _save(MediaLibrary library) {
    ref.read(mediaLibraryStoreProvider).save(library);
    _set(MediaLibraryState(library, scanning: true, status: state.status));
  }

  Future<void> scan() async {
    if (!ref.mounted || state.scanning) return;
    final settings = ref.read(settingsProvider).value;
    if (settings == null || !settings.hasFtp) {
      _set(MediaLibraryState(state.library,
          error: 'Renseigne l’accès FTP dans les Réglages'));
      return;
    }
    final connect = ref.read(ftpConnectProvider);
    final transmission = ref.read(transmissionProvider);
    final tmdb = ref.read(tmdbProvider);
    final previous = state.library;
    void status(String s) =>
        _set(MediaLibraryState(state.library, scanning: true, status: s));
    status('Connexion au FTP…');

    FtpClient? ftp;
    try {
      ftp = await connect(ftpConfigOf(settings));
      final roots = settings.mediaFolders;
      final found = <String, MediaFile>{
        for (final f in await scanFolders(ftp, roots,
            onFolder: (d) => status('Dossier $d')))
          f.path: f,
      };

      var pathFrom = previous.pathFrom, pathTo = previous.pathTo;
      String? warning;
      if (transmission != null) {
        status('Torrents terminés…');
        final torrents = (await transmission.torrentGet(
                ['id', 'hashString', 'downloadDir', 'percentDone', 'files']))
            .torrents;
        final videos = completedVideos(torrents);
        if (videos.isNotEmpty) {
          // Correspondance connue : encore valable ? (dossier déplacé, autre
          // compte FTP…)
          final first = videos.first;
          if (pathFrom != null &&
              (!first.path.startsWith(pathFrom) ||
                  await ftp.size('$pathTo${first.path.substring(pathFrom.length)}') == null)) {
            pathFrom = pathTo = null;
          }
          if (pathFrom == null) {
            status('Correspondance des chemins Transmission…');
            final map = await detectPathMap(
                ftp, videos.first.path, videos.first.size, roots);
            if (map != null) (pathFrom, pathTo) = map;
          }
          if (pathFrom == null) {
            warning = 'Fichiers des torrents introuvables sur le FTP '
                '(${videos.first.path})';
          } else {
            for (final v in videos) {
              if (!v.path.startsWith(pathFrom)) continue;
              final path = '$pathTo${v.path.substring(pathFrom.length)}';
              found[path] = (found[path] ??
                      MediaFile(path: path, size: v.size))
                  .copyWith(hash: v.hash);
            }
          }
        }
      }

      final before = {for (final f in previous.files) f.path: f};
      final now = DateTime.now();
      // Construite en entier : une correspondance abandonnée reste vide.
      var library = MediaLibrary(
        tmdb: previous.tmdb,
        files: [
          for (final f in found.values)
            f.copyWith(added: before[f.path]?.added ?? now),
        ],
        scannedAt: now,
        pathFrom: pathFrom,
        pathTo: pathTo,
      );
      _save(library);

      if (tmdb != null) library = await _identify(library, tmdb);
      ref.read(mediaLibraryStoreProvider).save(library);
      _set(MediaLibraryState(library, error: warning));
    } on Object catch (e) {
      _set(MediaLibraryState(state.library, error: '$e'));
    } finally {
      unawaited(ftp?.close());
    }
  }

  /// Fiches TMDB des titres pas encore cherchés.
  Future<MediaLibrary> _identify(MediaLibrary library, TmdbApi tmdb) async {
    final pending = <String, MediaGuess>{
      for (final f in library.files)
        if (!library.tmdb.containsKey(MediaLibrary.groupKey(f.guess)))
          MediaLibrary.groupKey(f.guess): f.guess,
    };
    var done = 0;
    final found = {...library.tmdb};
    for (final MapEntry(:key, value: guess) in pending.entries) {
      _set(MediaLibraryState(library,
          scanning: true, status: 'Fiches TMDB ${++done}/${pending.length}'));
      try {
        found[key] = await tmdb.identify(
            guess.title, guess.isEpisode ? TmdbType.tv : TmdbType.movie,
            year: guess.isEpisode ? null : guess.year);
      } on TmdbException {
        continue; // Réessayé au prochain parcours.
      }
      if (!ref.mounted) break;
      // Enregistré par paquets : rien de perdu si l'appli est fermée.
      if (done % 10 == 0) {
        library = library.copyWith(tmdb: {...found});
        ref.read(mediaLibraryStoreProvider).save(library);
      }
    }
    return library.copyWith(tmdb: found);
  }

  /// Oublie la correspondance des chemins (dossier de Transmission changé).
  void resetPathMap() {
    final l = state.library;
    final library = MediaLibrary(files: l.files, tmdb: l.tmdb, scannedAt: l.scannedAt);
    ref.read(mediaLibraryStoreProvider).save(library);
    _set(MediaLibraryState(library));
  }
}

final mediaLibraryProvider =
    NotifierProvider<MediaLibraryNotifier, MediaLibraryState>(MediaLibraryNotifier.new);

/// Épisodes TMDB d'une saison : (id de la série, saison).
final tmdbSeasonProvider =
    FutureProvider.family<List<TmdbEpisode>, (int, int)>((ref, key) async {
  final tmdb = ref.watch(tmdbProvider);
  if (tmdb == null) return const [];
  return tmdb.season(key.$1, key.$2);
});
