import 'release_name.dart';
import 'titles.dart';

/// Extensions des fichiers vidéo retenus dans la base.
const videoExtensions = {
  'mkv', 'mp4', 'm4v', 'avi', 'ts', 'm2ts', 'webm', 'mov', 'wmv', 'mpg', 'mpeg',
};

bool isVideoPath(String path) {
  final dot = path.lastIndexOf('.');
  return dot > 0 && videoExtensions.contains(path.substring(dot + 1).toLowerCase());
}

/// Ce qu'on devine d'un fichier vidéo d'après son nom et ses dossiers :
/// `/torrents/The.Bear.S03.MULTi.1080p-GRP/The.Bear.S03E01.mkv` → série
/// « The Bear », saison 3, épisode 1.
/// Taille minimale d'un film : en dessous, ce n'est pas un film (vidéos de
/// jeux, extraits, bandes-annonces…).
const minMovieBytes = 500 * 1024 * 1024;

/// Taille minimale d'un épisode reconnu (S01E03, 1x03…) : un épisode court
/// en H.265 pèse souvent 200 à 450 Mo.
const minEpisodeBytes = 100 * 1024 * 1024;

/// Le fichier est-il un film ou un épisode, au vu de sa taille ? Une taille
/// inconnue (0) ne l'écarte pas.
bool isMediaSize(String path, int size) =>
    size <= 0 ||
    size >= (MediaGuess.parse(path).isEpisode ? minEpisodeBytes : minMovieBytes);

class MediaGuess {
  const MediaGuess({
    required this.title,
    this.year,
    this.season,
    this.episode,
    this.resolution,
    this.source,
    this.videoCodec,
  });

  final String title;
  final int? year;
  final int? season;
  final int? episode;
  final String? resolution;
  final String? source;
  final String? videoCodec;

  bool get isEpisode => episode != null;

  static final _sxe = RegExp(r'(?:^|[^A-Za-z0-9])S(\d{1,2})[ ._-]?E(\d{1,3})',
      caseSensitive: false);
  static final _seasonMark =
      RegExp(r'(?:^|[ ._-])S(\d{1,2})(?:E\d{1,3})?(?:[ ._-]|$)', caseSensitive: false);
  static final _nxn = RegExp(r'(?:^|[^0-9])(\d{1,2})x(\d{2,3})(?:[^0-9]|$)');
  static final _seasonDir = RegExp(
      r'^(?:s(?:aison|eason)?[ ._-]*\d{1,2}|specials?)$', caseSensitive: false);
  static final _extrasDir = RegExp(
      r'^(?:extras?|featurettes?|bonus|samples?|behind the scenes)$',
      caseSensitive: false);

  /// Fichier à ignorer : extrait (« sample ») ou bonus.
  static bool isExtra(String path) {
    final parts = path.split('/');
    if (parts.length > 1 && parts.sublist(0, parts.length - 1).any(_extrasDir.hasMatch)) {
      return true;
    }
    return RegExp(r'(^|[^a-z])sample([^a-z]|$)', caseSensitive: false)
        .hasMatch(parts.last);
  }

  static String _stem(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 && isVideoPath(name) ? name.substring(0, dot) : name;
  }

  /// Nom débarrassé de ce qui gêne l'analyse : « Titre - S01E01 - Nom »,
  /// « Titre (2024) [1080p] ».
  static String _clean(String s) => s
      .replaceAll(RegExp(r'[\[\]()]'), ' ')
      .replaceAll(RegExp(r'\s+-\s+'), ' ')
      .trim();

  /// Titre lisible avant le marqueur d'épisode, ou null s'il est vide.
  static String? _titleBefore(String s, int index) {
    final t = titleWords(s.substring(0, index)).join(' ');
    return t.isEmpty ? null : ReleaseName.parse(s.substring(0, index)).title;
  }

  static MediaGuess parse(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    final file = _clean(_stem(parts.isEmpty ? path : parts.last));
    // Dossiers parents, du plus proche au plus lointain, sans « Saison 1 ».
    final dirs = [
      for (final d in parts.reversed.skip(1))
        if (!_seasonDir.hasMatch(d.trim())) _clean(d),
    ];
    final release = ReleaseName.parse(file);

    final m = _sxe.firstMatch(file) ?? _nxn.firstMatch(file);
    if (m != null) {
      String? title;
      int? year;
      // Dossier du torrent (« Titre.S01.MULTi.1080p-GRP ») : mieux nommé que
      // les fichiers, parfois abrégés (« dxr.s01e10.mkv »).
      if (_seasonMark.firstMatch(dirs.firstOrNull ?? '') case final dm?) {
        title = _titleBefore(dirs.first, dm.start);
        year = ReleaseName.parse(dirs.first).year;
      }
      title ??= _titleBefore(file, m.start);
      year ??= release.year;
      // « S01E01 - Pilote.mkv » : le titre est dans un dossier parent.
      for (final d in dirs) {
        if (title != null) break;
        final parsed = ReleaseName.parse(d);
        title = parsed.title;
        year ??= parsed.year;
      }
      return MediaGuess(
        title: title ?? release.title,
        year: year,
        season: int.parse(m[1]!),
        episode: int.parse(m[2]!),
        resolution: release.resolution,
        source: release.source,
        videoCodec: release.videoCodec,
      );
    }

    // Film : le dossier du torrent est souvent mieux nommé que le fichier
    // (« Film.2024.1080p-GRP/grp-film-1080p.mkv »).
    var best = release;
    if (best.year == null && dirs.isNotEmpty) {
      final folder = ReleaseName.parse(dirs.first);
      if (folder.year != null) best = folder;
    }
    return MediaGuess(
      title: best.title,
      year: best.year,
      resolution: release.resolution ?? best.resolution,
      source: release.source ?? best.source,
      videoCodec: release.videoCodec ?? best.videoCodec,
    );
  }
}
