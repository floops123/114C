import 'titles.dart';

// Reconnaissance des albums et des pistes d'après les dossiers et les noms
// de fichiers : `/musique/Daft Punk/Random Access Memories (2013) [FLAC]/
// 03 - Giorgio by Moroder.flac` → album « Random Access Memories » de
// « Daft Punk », 2013, piste 3 « Giorgio by Moroder ».

/// Extensions des fichiers audio retenus.
const audioExtensions = {
  'mp3', 'flac', 'm4a', 'aac', 'ogg', 'oga', 'opus', 'wav', 'wma', 'ape',
  'wv', 'aiff', 'aif', 'alac', 'mka', 'dsf', 'webm',
};

String extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  return dot > slash + 1 ? path.substring(dot + 1).toLowerCase() : '';
}

bool isAudioPath(String path) {
  final ext = extensionOf(path);
  // .webm est aussi une vidéo : il n'est audio que sous un nom de piste.
  return audioExtensions.contains(ext) && ext != 'webm';
}

/// Taille minimale d'une piste : en dessous, jingles, bruitages, extraits.
const minTrackBytes = 300 * 1024;

/// Sous-dossier de disque : `CD1`, `Disc 2`, `Disque 1 - Live`…
final _discFolder = RegExp(
    r'^(?:cd|disc|disk|disque|dis[ck]o)\s*[-_.]?\s*(\d{1,2})(?:\b|$)',
    caseSensitive: false);

/// Numéro de disque d'un dossier comme `CD2`, sinon null.
int? discOfFolder(String name) =>
    int.tryParse(_discFolder.firstMatch(name.trim())?.group(1) ?? '');

/// Dossier de l'album d'un fichier : son dossier, ou le dossier au-dessus
/// pour un sous-dossier de disque.
String albumDirOf(String path) {
  final parts = path.split('/');
  if (parts.length < 2) return '/';
  final dir = parts.sublist(0, parts.length - 1);
  if (dir.length > 1 && discOfFolder(dir.last) != null) dir.removeLast();
  final joined = dir.join('/');
  return joined.isEmpty ? '/' : joined;
}

/// Mots qui ne disent rien du titre : formats, sources, qualité.
final _tag = RegExp(
    r'^(?:flac|mp3|aac|alac|ogg|opus|wav|m4a|ape|wv|dsd|lossless|hi-?res|'
    r'web|webflac|cd|cdda|cdrip|vinyl|lp|ep|single|2cd|3cd|4cd|\d+cd|'
    r'v0|v2|vbr|cbr|320|256|192|128|\d+\s?kbps|\d+(?:[-.,]\d+)?\s?k?hz|'
    r'\d+\s?bits?|\d+bit|16|24|32|44|48|88|96|176|192|'
    r'retail|proper|repack|promo|bonus|mixed|remastered?|deluxe|'
    r'multi|vbr\s?v0|itunes|qobuz|deezer|tidal|bandcamp|spotify|amazon)$',
    caseSensitive: false);

/// Dossiers génériques : ce n'est pas un artiste.
const _generic = {
  'music', 'musique', 'musiques', 'musics', 'torrents', 'torrent',
  'downloads', 'download', 'complete', 'completed', 'telechargements',
  'albums', 'album', 'mp3', 'flac', 'data', 'media', 'medias', 'files',
  'audio', 'seed', 'seeding', 'incoming', 'singles', 'compilations', 'va',
  'divers', 'misc', 'various', 'various artists', 'new', 'tmp',
};

bool _isYear(String s) {
  final y = int.tryParse(s.trim());
  return y != null && y >= 1900 && y <= 2100 && s.trim().length == 4;
}

bool _isTagWord(String s) {
  final t = s.trim();
  if (t.isEmpty) return true;
  return t.split(RegExp(r'[\s,+/]+')).every((w) => w.isEmpty || _tag.hasMatch(w));
}

/// Un nom « de scène » : sans espace, mots reliés par `_` ou `.`, champs par
/// `-` (`Daft_Punk-Random_Access_Memories-WEB-2013-GRP`).
bool _isScene(String name) => !name.trim().contains(' ') && name.contains('-');

String _spaces(String s) => s.replaceAll(RegExp(r'[_]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Ce qu'on devine d'un album d'après son dossier (et celui de l'artiste).
class AlbumGuess {
  const AlbumGuess({required this.title, this.artist, this.year});

  final String title;
  final String? artist;
  final int? year;

  /// Clé de comparaison : artiste et titre, sans accents ni casse.
  String get key => '${titleKey(artist ?? '')}|${titleKey(title)}';

  /// [dir] : le dossier de l'album (voir [albumDirOf]).
  static AlbumGuess parse(String dir) {
    final parts = dir.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return const AlbumGuess(title: '');
    final name = parts.last;
    final parent = parts.length > 1 ? _spaces(parts[parts.length - 2]) : null;
    final parentArtist = parent == null ||
            _generic.contains(foldAccents(parent).toLowerCase()) ||
            _isScene(parts[parts.length - 2])
        ? null
        : parent;
    return _isScene(name) ? _scene(name, parentArtist) : _plain(name, parentArtist);
  }

  static AlbumGuess _scene(String name, String? parentArtist) {
    final fields = name.split('-').map((f) => f.replaceAll(RegExp(r'[_.]+'), ' ').trim()).toList();
    int? year;
    final words = <String>[];
    for (final (i, f) in fields.indexed) {
      if (f.isEmpty) continue;
      if (_isYear(f)) {
        year ??= int.parse(f);
        continue;
      }
      // Référence de catalogue (entre parenthèses), format, groupe (le
      // dernier champ, après l'année ou un format).
      if (f.startsWith('(') || _isTagWord(f)) continue;
      if (i == fields.length - 1 && words.length >= 2) continue;
      words.add(f);
    }
    if (words.length >= 2) {
      return AlbumGuess(artist: words[0], title: words[1], year: year);
    }
    return AlbumGuess(
        artist: parentArtist, title: words.isEmpty ? _spaces(name) : words.first, year: year);
  }

  static AlbumGuess _plain(String raw, String? parentArtist) {
    int? year;
    var name = _spaces(raw);
    // Groupes entre crochets ou parenthèses : année, format, édition.
    name = name.replaceAllMapped(RegExp(r'[\[({]([^\])}]*)[\])}]'), (m) {
      final inner = m.group(1)!.trim();
      final y = RegExp(r'\b(19|20)\d{2}\b').firstMatch(inner);
      if (y != null && inner.replaceAll(RegExp(r'[\d\s.-]'), '').length <= 2) {
        year ??= int.parse(y.group(0)!);
        return ' ';
      }
      if (m.group(0)!.startsWith('[') || _isTagWord(inner)) return ' ';
      return m.group(0)!;
    }).replaceAll(RegExp(r'\s+'), ' ').trim();

    var fields = name.split(RegExp(r'\s+[-–—]\s+')).map((f) => f.trim()).where((f) => f.isNotEmpty).toList();
    fields = [
      for (final f in fields)
        if (_isYear(f))
          () {
            year ??= int.parse(f);
            return '';
          }()
        else if (!_isTagWord(f))
          f,
    ].where((f) => f.isNotEmpty).toList();
    // « 2013 Album » : année en tête.
    if (fields.isNotEmpty) {
      final lead = RegExp(r'^((?:19|20)\d{2})[.\s]+(.+)$').firstMatch(fields.last);
      if (lead != null) {
        year ??= int.parse(lead.group(1)!);
        fields[fields.length - 1] = lead.group(2)!;
      }
    }
    // Format en fin de titre : « Album FLAC », « Album 24bit ».
    String strip(String s) {
      final words = s.split(' ');
      while (words.length > 1 && _isTagWord(words.last)) {
        words.removeLast();
      }
      return words.join(' ');
    }

    return switch (fields) {
      [] => AlbumGuess(artist: parentArtist, title: _spaces(raw), year: year),
      [final only] => AlbumGuess(artist: parentArtist, title: strip(only), year: year),
      [final artist, ...final rest] => AlbumGuess(
          artist: artist, title: strip(rest.join(' - ')), year: year),
    };
  }
}

/// Ce qu'on devine d'une piste d'après son nom de fichier.
class TrackGuess {
  const TrackGuess({required this.title, this.number, this.disc, this.artist});

  final String title;
  final int? number;
  final int? disc;

  /// Artiste en tête du nom (`01 - Artiste - Titre`), s'il y en a un.
  final String? artist;

  /// [path] : chemin du fichier ; le disque vient aussi d'un dossier `CD2`.
  static TrackGuess parse(String path) {
    final parts = path.split('/');
    final file = parts.last;
    final folderDisc = parts.length > 1 ? discOfFolder(parts[parts.length - 2]) : null;
    final ext = extensionOf(file);
    var base = (ext.isEmpty ? file : file.substring(0, file.length - ext.length - 1)).trim();

    int? disc = folderDisc, number;
    // « 1-03 Titre », « 2.05 - Titre » : disque et piste.
    final dt = RegExp(r'^(\d)[-.](\d{2})(?:\s*[-._)]\s*|\s+)(.*)$').firstMatch(base);
    final n = RegExp(r'^(\d{1,3})(?:\s*[-._)]\s*|\s+|(?=[A-Za-z]))(.*)$').firstMatch(base);
    if (dt != null) {
      disc ??= int.parse(dt.group(1)!);
      number = int.parse(dt.group(2)!);
      base = dt.group(3)!;
    } else if (n != null && n.group(2)!.trim().isNotEmpty) {
      final v = int.parse(n.group(1)!);
      // « 103 » : disque 1, piste 3.
      if (n.group(1)!.length == 3 && v >= 100) {
        disc ??= v ~/ 100;
        number = v % 100;
      } else {
        number = v;
      }
      base = n.group(2)!;
    }
    base = base.trim();

    String? artist;
    if (!base.contains(' ') && base.contains('-')) {
      // Scène : artiste-titre-groupe.
      final fields = base
          .split('-')
          .map((f) => f.replaceAll(RegExp('[_.]+'), ' ').trim())
          .where((f) => f.isNotEmpty)
          .toList();
      if (fields.length >= 3) {
        artist = fields[0];
        base = fields[1];
      } else if (fields.length == 2) {
        artist = fields[0];
        base = fields[1];
      }
    } else {
      base = _spaces(base);
      final fields = base.split(RegExp(r'\s+[-–—]\s+'));
      if (fields.length >= 2) {
        artist = fields.first.trim();
        base = fields.sublist(1).join(' - ').trim();
      }
    }
    return TrackGuess(
      title: base.isEmpty ? file : base,
      number: number,
      disc: disc,
      artist: artist,
    );
  }
}

/// Un fichier audio : chemin (sur le serveur ou le FTP), taille, et infohash
/// du torrent d'origine s'il en vient.
typedef AudioFile = ({String path, int size, String? hash});

/// Part de l'audio, en octets, au-delà de laquelle un torrent est de la
/// musique : un jeu ou un film avec sa bande-son n'en est pas.
const musicShare = 0.5;

/// Les fichiers audio des torrents terminés (réponse `torrent-get` avec
/// `hashString`, `downloadDir`, `percentDone`, `files`) qui sont de la
/// musique : chemins sur le serveur.
List<AudioFile> musicOfTorrents(List<Map<String, dynamic>> torrents) {
  final out = <AudioFile>[];
  for (final t in torrents) {
    if (((t['percentDone'] as num?) ?? 0) < 1) continue;
    var total = 0, audio = 0;
    final found = <AudioFile>[];
    for (final f in (t['files'] as List? ?? const []).whereType<Map>()) {
      final size = (f['length'] as num?)?.toInt() ?? 0;
      final path = '${t['downloadDir']}/${f['name']}'.replaceAll(RegExp('/+'), '/');
      total += size;
      if (!isAudioPath(path)) continue;
      audio += size;
      if (size >= minTrackBytes) {
        found.add((path: path, size: size, hash: '${t['hashString'] ?? ''}'.toLowerCase()));
      }
    }
    if (total > 0 && audio / total >= musicShare) out.addAll(found);
  }
  return out;
}

/// Garde, parmi les fichiers audio trouvés dans des dossiers, les albums qui
/// ressemblent à de la musique : au plus 100 pistes, de 1,5 Mo en moyenne au
/// moins (les dossiers de bruitages d'un jeu en ont des centaines, toutes
/// petites), sans les pistes de moins de [minTrackBytes].
List<AudioFile> plausibleAlbums(Iterable<AudioFile> files) {
  final byDir = <String, List<AudioFile>>{};
  for (final f in files) {
    if (f.size < minTrackBytes) continue;
    (byDir[albumDirOf(f.path)] ??= []).add(f);
  }
  return [
    for (final group in byDir.values)
      if (group.length <= 100 &&
          group.fold(0, (n, f) => n + f.size) / group.length >= 1.5 * 1024 * 1024)
        ...group,
  ];
}
