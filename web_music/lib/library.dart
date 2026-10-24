import 'dart:convert';
import 'dart:io';

import 'package:c411_core/music_name.dart';
import 'package:c411_core/titles.dart';

/// Un fichier audio du serveur, chemin FTP.
class MusicFile {
  MusicFile({required this.path, required this.size, this.hash, this.added});

  factory MusicFile.fromJson(Map<String, dynamic> json) => MusicFile(
        path: json['path'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
        hash: json['hash'] as String?,
        added: DateTime.tryParse(json['added'] as String? ?? ''),
      );

  final String path;
  final int size;

  /// Infohash du torrent d'origine, s'il vient de Transmission.
  final String? hash;

  /// Première apparition dans la discothèque.
  final DateTime? added;

  late final String id = fileId(path);
  late final TrackGuess guess = TrackGuess.parse(path);
  String get albumDir => albumDirOf(path);
  String get name => path.split('/').last;
  String get format => extensionOf(path);

  MusicFile copyWith({String? hash, DateTime? added}) =>
      MusicFile(path: path, size: size, hash: hash ?? this.hash, added: added ?? this.added);

  Map<String, dynamic> toJson() => {
        'path': path,
        'size': size,
        'hash': ?hash,
        'added': ?added?.toIso8601String(),
      };
}

/// Une piste d'une fiche MusicBrainz.
class MbTrack {
  const MbTrack({
    required this.disc,
    required this.position,
    required this.title,
    this.length,
    this.artist,
  });

  factory MbTrack.fromJson(Map<String, dynamic> j) => MbTrack(
        disc: (j['disc'] as num?)?.toInt() ?? 1,
        position: (j['position'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        length: (j['length'] as num?)?.toInt(),
        artist: j['artist'] as String?,
      );

  final int disc;
  final int position;
  final String title;

  /// Durée en millisecondes.
  final int? length;

  /// Artiste de la piste, s'il diffère de celui de l'album.
  final String? artist;

  Map<String, dynamic> toJson() => {
        'disc': disc,
        'position': position,
        'title': title,
        'length': ?length,
        'artist': ?artist,
      };
}

/// Une parution (release) MusicBrainz, ce qu'on en garde.
class MbRelease {
  const MbRelease({
    this.source = 'musicbrainz',
    required this.id,
    required this.title,
    required this.artist,
    this.artistName,
    this.groupId,
    this.artistId,
    this.date,
    this.country,
    this.label,
    this.type,
    this.cover = false,
    this.groupCover = false,
    this.image,
    this.genres = const [],
    this.tracks = const [],
  });

  factory MbRelease.fromJson(Map<String, dynamic> j) => MbRelease(
        source: j['source'] as String? ?? 'musicbrainz',
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        artistName: j['artistName'] as String?,
        groupId: j['groupId'] as String?,
        artistId: j['artistId'] as String?,
        date: j['date'] as String?,
        country: j['country'] as String?,
        label: j['label'] as String?,
        type: j['type'] as String?,
        cover: j['cover'] as bool? ?? false,
        groupCover: j['groupCover'] as bool? ?? false,
        image: j['image'] as String?,
        genres: (j['genres'] as List? ?? const []).cast<String>(),
        tracks: [
          for (final t in (j['tracks'] as List? ?? const []).whereType<Map>())
            MbTrack.fromJson(t.cast<String, dynamic>()),
        ],
      );

  /// `musicbrainz` ou `discogs` (album que MusicBrainz ne connaît pas).
  final String source;

  /// Identifiant de la parution chez sa [source].
  final String id;
  final String title;

  /// Artiste crédité, tel que MusicBrainz l'écrit (« Daft Punk feat. … »).
  final String artist;

  /// Premier artiste crédité : son nom et son identifiant.
  final String? artistName;
  final String? artistId;
  final String? groupId;
  final String? date;
  final String? country;
  final String? label;

  /// Album, EP, Single, Compilation…
  final String? type;

  /// La Cover Art Archive a une pochette de cette parution ; sinon, peut-être
  /// une de son groupe de parutions.
  final bool cover;
  final bool groupCover;

  /// Pochette Discogs (fiche Discogs, ou complément d'une fiche MusicBrainz
  /// sans pochette propre).
  final String? image;
  final List<String> genres;
  final List<MbTrack> tracks;

  int? get year => date == null || date!.length < 4 ? null : int.tryParse(date!.substring(0, 4));

  /// La pochette de la parution (Cover Art Archive), sinon celle de Discogs,
  /// sinon peut-être celle du groupe de parutions.
  String? get coverUrl => cover
      ? 'https://coverartarchive.org/release/$id/front-500'
      : image ??
          (groupCover && groupId != null
              ? 'https://coverartarchive.org/release-group/$groupId/front-500'
              : null);

  /// La fiche chez sa source.
  String get url => source == 'discogs'
      ? 'https://www.discogs.com/release/$id'
      : 'https://musicbrainz.org/release/$id';

  MbRelease withGenres(List<String> genres) => withExtras(genres: genres);

  /// Complétée par Discogs : pochette, genres (null : inchangés).
  MbRelease withExtras({String? image, List<String>? genres}) => MbRelease(
        source: source,
        id: id,
        title: title,
        artist: artist,
        artistName: artistName,
        artistId: artistId,
        groupId: groupId,
        date: date,
        country: country,
        label: label,
        type: type,
        cover: cover,
        groupCover: groupCover,
        image: image ?? this.image,
        genres: genres ?? this.genres,
        tracks: tracks,
      );

  Map<String, dynamic> toJson() => {
        if (source != 'musicbrainz') 'source': source,
        'id': id,
        'title': title,
        'artist': artist,
        'artistName': ?artistName,
        'groupId': ?groupId,
        'artistId': ?artistId,
        'date': ?date,
        'country': ?country,
        'label': ?label,
        'type': ?type,
        'cover': cover,
        'groupCover': groupCover,
        'image': ?image,
        'genres': genres,
        'tracks': [for (final t in tracks) t.toJson()],
      };
}

/// Résultat d'une recherche MusicBrainz pour un album : la parution
/// retenue, ou rien (on réessaiera plus tard).
class MbMatch {
  const MbMatch({required this.checked, this.release, this.discogs});

  factory MbMatch.fromJson(Map<String, dynamic> j) => MbMatch(
        checked: DateTime.tryParse(j['checked'] as String? ?? '') ?? DateTime(2000),
        discogs: DateTime.tryParse(j['discogs'] as String? ?? ''),
        release: j['release'] == null
            ? null
            : MbRelease.fromJson((j['release'] as Map).cast<String, dynamic>()),
      );

  final DateTime checked;
  final MbRelease? release;

  /// Quand Discogs a été consulté pour cet album (null : jamais).
  final DateTime? discogs;

  /// Une recherche infructueuse est refaite au bout d'une semaine.
  bool get stale => release == null && DateTime.now().difference(checked).inDays >= 7;

  Map<String, dynamic> toJson() => {
        'checked': checked.toIso8601String(),
        'release': ?release?.toJson(),
        'discogs': ?discogs?.toIso8601String(),
      };
}

/// La discothèque : les fichiers audio relevés par l'application, et les
/// fiches MusicBrainz par dossier d'album.
class MusicLibrary {
  MusicLibrary({this.files = const [], Map<String, MbMatch>? mb, this.scannedAt})
      : mb = mb ?? {};

  final List<MusicFile> files;

  /// Par dossier d'album ; seule partie enregistrée par le serveur.
  final Map<String, MbMatch> mb;

  /// Dernier parcours de l'application.
  final DateTime? scannedAt;

  MusicLibrary copyWith({List<MusicFile>? files, Map<String, MbMatch>? mb, DateTime? scannedAt}) =>
      MusicLibrary(files: files ?? this.files, mb: mb ?? this.mb, scannedAt: scannedAt ?? this.scannedAt);

  /// Fiches MusicBrainz enregistrées à [path].
  static Map<String, MbMatch> readMb(String path) {
    final file = File(path);
    if (!file.existsSync()) return {};
    try {
      final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return {
        for (final MapEntry(:key, :value) in ((j['mb'] as Map?) ?? const {}).entries)
          if (value is Map) '$key': MbMatch.fromJson(value.cast<String, dynamic>()),
      };
    } on Object {
      return {}; // Illisible : on recherchera.
    }
  }

  /// Écrit les fiches d'un bloc (fichier temporaire renommé).
  void writeMb(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(jsonEncode({
      'mb': {for (final MapEntry(:key, :value) in mb.entries) key: value.toJson()},
    }));
    tmp.renameSync(path);
  }

  /// La musique de la base de l'application : son fichier de préférences
  /// (clé `mediaLibrary`, une chaîne JSON), ou un export de la base seule.
  static ({List<MusicFile> files, DateTime? scannedAt}) parseApp(String source) {
    final json = jsonDecode(source);
    if (json is! Map) throw const FormatException('Base de l’application illisible');
    final raw = json['flutter.mediaLibrary'] ?? json['mediaLibrary'];
    final library = raw == null
        ? json
        : raw is String
            ? jsonDecode(raw) as Map
            : raw as Map;
    return (
      files: [
        for (final f in (library['music'] as List? ?? const []).whereType<Map>())
          if (f['path'] is String) MusicFile.fromJson(f.cast<String, dynamic>()),
      ],
      scannedAt: DateTime.tryParse(library['scannedAt'] as String? ?? ''),
    );
  }
}

/// Une piste de la discothèque : un fichier, et sa piste MusicBrainz.
class Track {
  Track(this.file, this.mb);
  final MusicFile file;
  final MbTrack? mb;

  String get title => mb?.title ?? file.guess.title;
  int get disc => mb?.disc ?? file.guess.disc ?? 1;
  int? get number => mb?.position ?? file.guess.number;

  Map<String, Object?> toJson() => {
        'id': file.id,
        'title': title,
        'disc': disc,
        'number': number,
        'duration': mb?.length == null ? null : mb!.length! / 1000,
        'artist': mb?.artist,
        'format': file.format,
        'size': file.size,
      };
}

/// Ce qu'est un dossier de fichiers audio : de la musique, un livre audio,
/// ou des sons sans rapport (samples d'un logiciel, musiques d'un jeu…).
enum AlbumKind {
  music,
  audiobook,
  other;

  // Dossiers de catégorie : ceux de l'application dans Transmission
  // (`ContentKind.plural` : Musique, Livres, Logiciels…), sans accents ni
  // majuscules ; le premier rencontré depuis la racine décide.
  static const _categories = {
    'musique': music, 'music': music,
    'livres': audiobook, 'livre': audiobook, 'livres audio': audiobook, 'livre audio': audiobook,
    'audiobooks': audiobook, 'audiobook': audiobook, 'ebooks': audiobook, 'ebook': audiobook,
    'logiciels': other, 'jeux video': other, 'films': other, 'series': other,
    'documentaires': other, 'animation': other, 'adulte': other, 'autres': other,
  };
  static final _chapter = RegExp(r'\b(chapitre|chapter|chap)\b', caseSensitive: false);
  // Référence Audible (ASIN) dans les noms : [B0H9MD3W8Q].
  static final _asin = RegExp(r'\[B0[A-Z0-9]{8}\]');
  static final _named = RegExp(r'livres? audio|audio ?books?|\blu par\b', caseSensitive: false);

  /// D'après le dossier de catégorie, puis l'extension .m4b, puis les noms :
  /// « livre audio » dans le dossier, référence Audible, ou une majorité de
  /// pistes « Chapitre … ».
  static AlbumKind of(String dir, List<String> paths) {
    for (final segment in dir.split('/')) {
      if (_categories[_fold(segment)] case final kind?) return kind;
    }
    if (paths.any((p) => p.toLowerCase().endsWith('.m4b'))) return audiobook;
    if (_named.hasMatch(dir) || _asin.hasMatch(dir)) return audiobook;
    final names = [for (final p in paths) p.split('/').last];
    if (names.any(_asin.hasMatch)) return audiobook;
    if (names.isNotEmpty && names.where(_chapter.hasMatch).length * 2 >= names.length) return audiobook;
    return music;
  }

  static String _fold(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[\s_.-]+'), ' ')
      .trim();
}

/// Titre et auteur d'un livre audio, d'après le nom de son dossier :
/// « Auteur - Titre », « Titre - Auteur », « Sujet - Titre - Auteur »
/// (biographies), ou un nom de release (« Les.morts.ont.la.parole.FR.
/// [MP3.128.kbps]-NOTAG »).
class AudiobookName {
  const AudiobookName(this.title, this.author, this.year);

  final String title;
  final String? author;
  final int? year;

  static const _articles = {'le', 'la', 'les', 'l', 'un', 'une', 'des', 'du', 'the', 'a', 'an'};
  static const _particles = {'de', 'du', 'des', 'd', 'von', 'van', 'der', 'den', 'le', 'la', 'y', 'et'};

  /// « Prénom Nom » : deux à quatre mots qui commencent par une majuscule
  /// (particules permises), sans chiffre, et pas un article en tête.
  static bool _person(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2 || words.length > 4 || RegExp(r'\d').hasMatch(text)) return false;
    if (_articles.contains(words.first.toLowerCase().replaceAll(RegExp("['’]\$"), ''))) return false;
    if (words.first.contains(RegExp("['’]"))) return false; // « L'aube »
    return words.every((w) => _particles.contains(w.toLowerCase()) || RegExp(r'^[A-ZÀ-Ý][^\s]*$').hasMatch(w));
  }

  static AudiobookName parse(String dir) {
    var name = dir.split('/').where((s) => s.isNotEmpty).lastOrNull ?? dir;
    // Nom de release, sans espaces : les points et soulignés en tiennent lieu.
    final release = !name.contains(' ');
    name = name
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ') // [MP3.128.kbps], [B0H9MD3W8Q]
        .replaceAll(RegExp(r'-[A-Za-z0-9]+$'), ''); // -NOTAG (groupe de release)
    if (release) name = name.replaceAll(RegExp(r'[._]'), ' ');
    name = name.replaceAll(RegExp(r'\b(FR|FRENCH|MP3|M4B|AAC|\d+ ?kbps)\b', caseSensitive: false), ' ');
    int? year;
    name = name.replaceAllMapped(RegExp(r'\((\d{4})\)'), (m) {
      year = int.parse(m[1]!);
      return ' ';
    });
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    final parts = [for (final p in name.split(' - ')) if (p.trim().isNotEmpty) p.trim()];
    if (parts.length < 2) return AudiobookName(name, null, year);
    final int at;
    if (parts.length >= 3 && _person(parts.last)) {
      at = parts.length - 1;
    } else if (_person(parts.first)) {
      at = 0;
    } else if (_person(parts.last)) {
      at = parts.length - 1;
    } else {
      return AudiobookName(name, null, year);
    }
    return AudiobookName([for (final (i, p) in parts.indexed) if (i != at) p].join(' - '), parts[at], year);
  }
}

/// Un album : un dossier de fichiers audio, et sa fiche MusicBrainz.
class Album {
  Album({required this.dir, required this.guess, required this.tracks, this.release});

  final String dir;
  final AlbumGuess guess;
  final List<Track> tracks;
  final MbRelease? release;

  late final String id = fileId('album:$dir');

  /// Musique, livre audio ou autre ; seule la musique est cherchée sur
  /// MusicBrainz et Discogs.
  late final AlbumKind kind = AlbumKind.of(dir, [for (final t in tracks) t.file.path]);
  late final AudiobookName? _book = kind == AlbumKind.audiobook ? AudiobookName.parse(dir) : null;
  String get title => _book?.title ?? release?.title ?? guess.title;

  /// L'artiste ; pour un livre audio, l'auteur (vide s'il n'est pas dans le nom).
  String get artist => _book != null ? _book.author ?? '' : release?.artist ?? guess.artist ?? 'Artiste inconnu';
  int? get year => _book != null ? _book.year : release?.year ?? guess.year;

  /// Nom de l'artiste principal (le premier crédité).
  String get artistName => release?.artistName ?? artist;

  DateTime? get added => tracks
      .map((t) => t.file.added)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

  /// [artistId] : celui de son artiste dans le catalogue.
  Map<String, Object?> toJson({required String artistId}) => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'artist': artist,
        'artistId': artistId,
        'year': year,
        'date': release?.date,
        'type': release?.type,
        'label': release?.label,
        'country': release?.country,
        'genres': release?.genres ?? const [],
        'mbid': release?.source == 'musicbrainz' ? release?.id : null,
        'source': release?.source,
        'link': release?.url,
        'coverFrom': release == null ? null : release!.cover ? 'musicbrainz' : release!.image != null ? 'discogs' : release!.coverUrl != null ? 'musicbrainz' : null,
        'cover': release?.coverUrl != null,
        'added': added?.toIso8601String(),
        'formats': {for (final t in tracks) t.file.format}.toList(),
        'tracks': [for (final t in tracks) t.toJson()],
      };

  /// Rattache chaque fichier à sa piste MusicBrainz : par disque et numéro,
  /// sinon dans l'ordre si les nombres concordent, sinon par titre.
  static List<Track> match(List<MusicFile> files, MbRelease? release) {
    final sorted = [...files]..sort(_byPosition);
    final mbTracks = release?.tracks ?? const <MbTrack>[];
    if (mbTracks.isEmpty) return [for (final f in sorted) Track(f, null)];
    final discs = {for (final t in mbTracks) t.disc}.length;
    final byPosition = {for (final t in mbTracks) (t.disc, t.position): t};
    final used = <MbTrack>{};
    final numbered = sorted.every((f) => f.guess.number != null);
    final tracks = <Track>[];
    for (final (i, f) in sorted.indexed) {
      MbTrack? mb;
      if (numbered) {
        // Un seul disque dans le dossier mais plusieurs chez MusicBrainz :
        // les numéros peuvent continuer d'un disque à l'autre.
        mb = byPosition[(f.guess.disc ?? 1, f.guess.number!)];
        if (mb == null && discs > 1 && f.guess.disc == null) {
          var n = f.guess.number!;
          for (final d in {for (final t in mbTracks) t.disc}.toList()..sort()) {
            final count = mbTracks.where((t) => t.disc == d).length;
            if (n <= count) {
              mb = byPosition[(d, n)];
              break;
            }
            n -= count;
          }
        }
      } else if (sorted.length == mbTracks.length) {
        mb = mbTracks[i];
      }
      mb ??= _byTitle(f.guess.title, mbTracks, used);
      if (mb != null && used.contains(mb)) mb = null;
      if (mb != null) used.add(mb);
      tracks.add(Track(f, mb));
    }
    return tracks..sort((a, b) {
      final d = a.disc.compareTo(b.disc);
      if (d != 0) return d;
      final n = (a.number ?? 999).compareTo(b.number ?? 999);
      return n != 0 ? n : a.file.name.compareTo(b.file.name);
    });
  }

  static int _byPosition(MusicFile a, MusicFile b) {
    final d = (a.guess.disc ?? 1).compareTo(b.guess.disc ?? 1);
    if (d != 0) return d;
    final n = (a.guess.number ?? 999).compareTo(b.guess.number ?? 999);
    return n != 0 ? n : a.name.compareTo(b.name);
  }

  static MbTrack? _byTitle(String title, List<MbTrack> tracks, Set<MbTrack> used) {
    final key = titleKey(title);
    if (key.isEmpty) return null;
    for (final t in tracks) {
      if (used.contains(t)) continue;
      final k = titleKey(t.title);
      if (k == key || (k.length > 3 && (key.contains(k) || k.contains(key)))) return t;
    }
    return null;
  }
}

/// La discothèque vue par l'interface : albums et artistes.
class Catalog {
  Catalog(this.albums)
      : _files = {
          for (final a in albums)
            for (final t in a.tracks) t.file.id: t.file,
        },
        _albums = {for (final a in albums) a.id: a} {
    // Un album non reconnu rejoint l'artiste MusicBrainz de même nom.
    final byName = <String, String>{
      for (final a in albums)
        titleKey(a.artistName): ?a.release?.artistId,
    };
    for (final a in albums) {
      final key = a.release?.artistId ?? byName[titleKey(a.artistName)] ?? 'name:${titleKey(a.artistName)}';
      _artistOf[a.id] = fileId('artist:$key');
    }
  }

  final List<Album> albums;
  final Map<String, MusicFile> _files;
  final Map<String, Album> _albums;
  final _artistOf = <String, String>{};

  MusicFile? file(String id) => _files[id];
  Album? album(String id) => _albums[id];

  static Catalog of(MusicLibrary library) {
    final byDir = <String, List<MusicFile>>{};
    for (final f in library.files) {
      (byDir[f.albumDir] ??= []).add(f);
    }
    return Catalog([
      for (final MapEntry(key: dir, value: files) in byDir.entries)
        () {
          // Un livre audio ou des sons sans rapport : pas de fiche, même si
          // une ancienne recherche en avait trouvé une.
          final music = AlbumKind.of(dir, [for (final f in files) f.path]) == AlbumKind.music;
          final release = music ? library.mb[dir]?.release : null;
          return Album(
            dir: dir,
            guess: AlbumGuess.parse(dir),
            release: release,
            tracks: Album.match(files, release),
          );
        }(),
    ]..sort((a, b) => titleKey(a.title).compareTo(titleKey(b.title))));
  }

  /// Albums de musique (sans les livres audio ni les sons sans rapport).
  Iterable<Album> get music => albums.where((a) => a.kind == AlbumKind.music);

  Map<String, Object?> toJson() {
    final artists = <String, Map<String, Object?>>{};
    // Artistes : ceux de la musique seulement (pas les auteurs des livres audio).
    for (final a in music) {
      final id = _artistOf[a.id]!;
      final entry = artists[id] ??= {'id': id, 'name': a.artistName, 'mbid': null, 'albums': <String>[]};
      // Le nom et l'identifiant de MusicBrainz, s'il en a un.
      if (a.release?.artistId case final mbid?) {
        entry['name'] = a.artistName;
        entry['mbid'] = mbid;
      }
      (entry['albums'] as List<String>).add(a.id);
    }
    return {
      'albums': [for (final a in albums) a.toJson(artistId: _artistOf[a.id]!)],
      'artists': artists.values.toList(),
    };
  }
}

/// Identifiant court et stable (FNV-1a 64 bits, en hexadécimal).
String fileId(String text) {
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in utf8.encode(text)) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
