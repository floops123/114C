import 'dart:convert';
import 'dart:io';

import 'package:c411_core/media_name.dart';
import 'package:c411_core/titles.dart';

/// Un fichier vidéo de la vidéothèque, sur le FTP.
class CatalogFile {
  CatalogFile({
    required this.id,
    required this.path,
    required this.size,
    required this.guess,
    this.added,
  });

  /// Identifiant stable (dérivé du chemin), utilisé dans les URL.
  final String id;
  final String path;
  final int size;
  final MediaGuess guess;
  final DateTime? added;

  String get name => path.split('/').last;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'season': guess.season,
        'episode': guess.episode,
        'resolution': guess.resolution,
        'source': guess.source,
        'codec': guess.videoCodec,
        'added': added?.toIso8601String(),
      };
}

/// Un film ou une série : sa fiche TMDB (si l'application l'a trouvée) et
/// ses fichiers.
class CatalogTitle {
  CatalogTitle({
    required this.id,
    required this.series,
    required this.title,
    required this.files,
    this.year,
    this.overview,
    this.poster,
    this.rating,
    this.tmdbId,
  });

  final String id;
  final bool series;
  final String title;
  final int? year;
  final String? overview;
  final String? poster;
  final double? rating;
  final int? tmdbId;
  final List<CatalogFile> files;

  DateTime? get added => files
      .map((f) => f.added)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

  Map<String, Object?> toJson() => {
        'id': id,
        'type': series ? 'tv' : 'movie',
        'title': title,
        'year': year,
        'overview': overview,
        'poster': poster,
        'rating': rating,
        'tmdbId': tmdbId,
        'added': added?.toIso8601String(),
        'files': [for (final f in files) f.toJson()],
      };
}

/// La vidéothèque de l'application, relue quand son fichier change.
class Catalog {
  Catalog(this.titles)
      : _files = {
          for (final t in titles)
            for (final f in t.files) f.id: f,
        };

  final List<CatalogTitle> titles;
  final Map<String, CatalogFile> _files;

  CatalogFile? file(String id) => _files[id];

  Map<String, Object?> toJson() => {
        'titles': [for (final t in titles) t.toJson()],
      };

  /// Depuis le fichier de préférences de l'application (clé `mediaLibrary`,
  /// une chaîne JSON) ou un export de la base seule (`files`, `tmdb`).
  static Catalog parse(String source) {
    final json = jsonDecode(source);
    if (json is! Map) throw const FormatException('Vidéothèque illisible');
    final raw = json['mediaLibrary'] ?? json['flutter.mediaLibrary'];
    final library = raw == null
        ? json
        : raw is String
            ? jsonDecode(raw) as Map
            : raw as Map;
    return fromLibrary(library.cast<String, dynamic>());
  }

  /// Même regroupement que l'application (`MediaLibrary.titles`) : par titre
  /// (et année pour un film), puis deux noms pour une même fiche TMDB
  /// réunis.
  static Catalog fromLibrary(Map<String, dynamic> library) {
    final tmdb = ((library['tmdb'] as Map?) ?? const {}).cast<String, dynamic>();
    final groups = <String, List<CatalogFile>>{};
    for (final f in (library['files'] as List? ?? const []).whereType<Map>()) {
      final path = f['path'] as String? ?? '';
      final size = (f['size'] as num?)?.toInt() ?? 0;
      // Trop petit pour un film (500 Mo) ou un épisode (100 Mo) : vidéos
      // de jeux, extraits… Même règle que l'application.
      if (path.isEmpty || !isMediaSize(path, size)) continue;
      final guess = MediaGuess.parse(path);
      final key = guess.isEpisode
          ? 'tv:${titleKey(guess.title)}'
          : 'movie:${titleKey(guess.title)}:${guess.year ?? ''}';
      (groups[key] ??= []).add(CatalogFile(
        id: fileId(path),
        path: path,
        size: size,
        guess: guess,
        added: DateTime.tryParse(f['added'] as String? ?? ''),
      ));
    }

    final byTmdb = <String, CatalogTitle>{};
    final titles = <CatalogTitle>[];
    for (final MapEntry(:key, value: files) in groups.entries) {
      final t = (tmdb[key] as Map?)?.cast<String, dynamic>();
      final tmdbKey = t == null ? null : '${t['type']}:${t['id']}';
      if (tmdbKey != null && byTmdb[tmdbKey] != null) {
        byTmdb[tmdbKey]!.files.addAll(files);
        continue;
      }
      final guess = files.first.guess;
      final title = CatalogTitle(
        id: fileId(tmdbKey ?? key),
        series: t == null ? guess.isEpisode : t['type'] == 'tv',
        title: t?['title'] as String? ?? guess.title,
        year: _year(t?['date'] as String?) ?? guess.year,
        overview: t?['overview'] as String?,
        poster: t?['posterUrl'] as String?,
        rating: (t?['rating'] as num?)?.toDouble(),
        tmdbId: (t?['id'] as num?)?.toInt(),
        files: files,
      );
      if (tmdbKey != null) byTmdb[tmdbKey] = title;
      titles.add(title);
    }
    for (final t in titles) {
      t.files.sort((a, b) {
        final s = (a.guess.season ?? 0).compareTo(b.guess.season ?? 0);
        if (s != 0) return s;
        final e = (a.guess.episode ?? 0).compareTo(b.guess.episode ?? 0);
        return e != 0 ? e : a.name.compareTo(b.name);
      });
    }
    return Catalog(titles);
  }

  static int? _year(String? date) =>
      date == null || date.length < 4 ? null : int.tryParse(date.substring(0, 4));

  /// Identifiant court et stable (FNV-1a 64 bits, en hexadécimal).
  static String fileId(String text) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final byte in utf8.encode(text)) {
      hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

/// Le catalogue de [path], relu quand le fichier change.
class CatalogSource {
  CatalogSource(this.path);
  final String path;
  DateTime? _modified;
  Catalog _catalog = Catalog(const []);

  Catalog get current {
    final file = File(path);
    final modified = file.existsSync() ? file.lastModifiedSync() : null;
    if (modified != null && modified != _modified) {
      _catalog = Catalog.parse(file.readAsStringSync());
      _modified = modified;
    }
    return _catalog;
  }
}
