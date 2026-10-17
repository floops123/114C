import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';

class TmdbException implements Exception {
  const TmdbException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum TmdbType {
  movie('Film'),
  tv('Série');

  const TmdbType(this.label);
  final String label;
}

/// Dates de sortie en France d'un film (`/movie/{id}/release_dates`).
class FrenchDates {
  const FrenchDates({this.cinema, this.digital, this.physical});

  /// Sortie en salles (types 3, sinon 2 limitée).
  final DateTime? cinema;

  /// VOD / plateformes (type 4) et DVD / Blu-ray (type 5).
  final DateTime? digital;
  final DateTime? physical;

  bool get isEmpty => cinema == null && digital == null && physical == null;

  /// Types TMDB : 1 avant-première, 2 limitée, 3 salles, 4 numérique,
  /// 5 physique, 6 télévision. On garde la plus ancienne date de chaque type.
  factory FrenchDates.fromApi(Map<String, dynamic> body) {
    final byType = <int, DateTime>{};
    for (final country in (body['results'] as List? ?? const []).whereType<Map>()) {
      if (country['iso_3166_1'] != 'FR') continue;
      for (final d in (country['release_dates'] as List? ?? const []).whereType<Map>()) {
        final type = (d['type'] as num?)?.toInt();
        final date = DateTime.tryParse(d['release_date'] as String? ?? '');
        if (type == null || date == null) continue;
        final day = DateTime(date.year, date.month, date.day);
        if (byType[type] == null || day.isBefore(byType[type]!)) byType[type] = day;
      }
    }
    return FrenchDates(
      cinema: byType[3] ?? byType[2],
      digital: byType[4],
      physical: byType[5],
    );
  }
}

/// Film ou série TMDB, avec de quoi l'afficher et le chercher sur les trackers.
class TmdbTitle {
  const TmdbTitle({
    required this.id,
    required this.type,
    required this.title,
    this.originalTitle,
    this.date,
    this.posterUrl,
    this.overview,
    this.french,
  });

  final int id;
  final TmdbType type;

  /// Titre français (langue demandée à TMDB).
  final String title;
  final String? originalTitle;

  /// Sortie mondiale (films) ou première diffusion (séries).
  final DateTime? date;
  final String? posterUrl;
  final String? overview;

  /// Dates françaises (films), lues à l'ajout dans la liste.
  final FrenchDates? french;

  String get key => '${type.name}:$id';

  @override
  bool operator ==(Object other) => other is TmdbTitle && other.key == key;

  @override
  int get hashCode => key.hashCode;

  int? get year => date?.year;

  /// Prochaine étape qui compte pour trouver le film : la sortie en salles en
  /// France, puis la VOD (souvent la première version en torrent).
  DateTime? get nextDate {
    final now = DateTime.now();
    final f = french;
    for (final d in [f?.cinema, f?.digital, f?.physical]) {
      if (d != null && d.isAfter(now)) return d;
    }
    return f?.digital ?? f?.cinema ?? date;
  }

  /// Sortie à venir (ou date inconnue).
  bool get upcoming {
    final d = french?.cinema ?? date;
    return d == null || d.isAfter(DateTime.now());
  }

  TmdbTitle withFrench(FrenchDates? french) => TmdbTitle(
        id: id,
        type: type,
        title: title,
        originalTitle: originalTitle,
        date: date,
        posterUrl: posterUrl,
        overview: overview,
        french: french,
      );

  factory TmdbTitle.fromApi(Map<String, dynamic> json, TmdbType type) {
    final movie = type == TmdbType.movie;
    final poster = json['poster_path'] as String?;
    final overview = (json['overview'] as String?)?.trim();
    return TmdbTitle(
      id: (json['id'] as num).toInt(),
      type: type,
      title: (json[movie ? 'title' : 'name'] as String?) ?? '',
      originalTitle: json[movie ? 'original_title' : 'original_name'] as String?,
      date: DateTime.tryParse(
          json[movie ? 'release_date' : 'first_air_date'] as String? ?? ''),
      posterUrl: poster == null ? null : '${TmdbApi.imageBase}$poster',
      overview: overview == null || overview.isEmpty ? null : overview,
    );
  }

  static String? _day(DateTime? d) => d?.toIso8601String().substring(0, 10);
  static DateTime? _parse(Object? v) => DateTime.tryParse(v as String? ?? '');

  factory TmdbTitle.fromJson(Map<String, dynamic> json) {
    final fr = json['fr'] as Map?;
    return TmdbTitle(
      id: (json['id'] as num).toInt(),
      type: TmdbType.values.byName(json['type'] as String),
      title: json['title'] as String? ?? '',
      originalTitle: json['originalTitle'] as String?,
      date: _parse(json['date']),
      posterUrl: json['posterUrl'] as String?,
      overview: json['overview'] as String?,
      french: fr == null
          ? null
          : FrenchDates(
              cinema: _parse(fr['cinema']),
              digital: _parse(fr['digital']),
              physical: _parse(fr['physical'])),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'originalTitle': ?originalTitle,
        'date': ?_day(date),
        'posterUrl': ?posterUrl,
        'overview': ?overview,
        if (french case final f?)
          'fr': {
            'cinema': ?_day(f.cinema),
            'digital': ?_day(f.digital),
            'physical': ?_day(f.physical),
          },
      };
}

class TmdbPerson {
  const TmdbPerson(this.name, {this.role, this.photoUrl});
  final String name;

  /// Personnage joué, ou poste dans l'équipe.
  final String? role;
  final String? photoUrl;
}

/// Fiche complète d'un film ou d'une série (`append_to_response`).
class TmdbDetails {
  const TmdbDetails({
    this.tagline,
    this.genres = const [],
    this.runtime,
    this.seasons,
    this.episodes,
    this.status,
    this.rating,
    this.votes = 0,
    this.backdropUrl,
    this.certification,
    this.directors = const [],
    this.writers = const [],
    this.cast = const [],
    this.networks = const [],
    this.trailer,
    this.recommendations = const [],
    this.french,
  });

  final String? tagline;
  final List<String> genres;

  /// Durée en minutes (films) ; saisons et épisodes (séries).
  final int? runtime;
  final int? seasons;
  final int? episodes;

  /// Statut de production (« Sorti », « En production »… traduits ici).
  final String? status;
  final double? rating;
  final int votes;
  final String? backdropUrl;

  /// Classification française (« 12 », « Tous publics »…).
  final String? certification;

  /// Réalisation (films) ou création (séries), et scénario.
  final List<TmdbPerson> directors;
  final List<TmdbPerson> writers;
  final List<TmdbPerson> cast;

  /// Chaînes ou plateformes de diffusion (séries).
  final List<String> networks;

  /// Bande-annonce YouTube (en français de préférence).
  final Uri? trailer;
  final List<TmdbTitle> recommendations;
  final FrenchDates? french;

  static const _statuses = {
    'Released': 'Sorti',
    'Post Production': 'En post-production',
    'In Production': 'En production',
    'Planned': 'Prévu',
    'Rumored': 'Annoncé',
    'Canceled': 'Annulé',
    'Returning Series': 'En cours',
    'Ended': 'Terminée',
    'Pilot': 'Pilote',
  };

  factory TmdbDetails.fromApi(Map<String, dynamic> j, TmdbType type) {
    List<Map<String, dynamic>> list(Object? v) =>
        (v as List? ?? const []).whereType<Map<String, dynamic>>().toList();
    String? image(Object? path, [String size = 'w185']) =>
        path is String ? 'https://image.tmdb.org/t/p/$size$path' : null;
    final credits = j['credits'] as Map<String, dynamic>? ?? const {};
    final crew = list(credits['crew']);
    List<TmdbPerson> jobs(Set<String> names) {
      final seen = <String>{};
      return [
        for (final c in crew)
          if (names.contains(c['job']) && seen.add(c['name'] as String))
            TmdbPerson(c['name'] as String,
                role: c['job'] as String?, photoUrl: image(c['profile_path'])),
      ];
    }

    final videos = [
      for (final v in list((j['videos'] as Map?)?['results']))
        if (v['site'] == 'YouTube' && (v['type'] == 'Trailer' || v['type'] == 'Teaser'))
          v,
    ]..sort((a, b) {
        int score(Map v) =>
            (v['iso_639_1'] == 'fr' ? 0 : 2) + (v['type'] == 'Trailer' ? 0 : 1);
        return score(a) - score(b);
      });

    String? certification;
    if (type == TmdbType.movie) {
      for (final c in list((j['release_dates'] as Map?)?['results'])) {
        if (c['iso_3166_1'] != 'FR') continue;
        for (final d in list(c['release_dates'])) {
          final v = (d['certification'] as String?)?.trim();
          if (v != null && v.isNotEmpty) certification ??= v;
        }
      }
    } else {
      for (final c in list((j['content_ratings'] as Map?)?['results'])) {
        if (c['iso_3166_1'] == 'FR') certification = c['rating'] as String?;
      }
    }

    final runtimes = j['episode_run_time'] as List?;
    final tagline = (j['tagline'] as String?)?.trim();
    final rating = (j['vote_average'] as num?)?.toDouble();
    return TmdbDetails(
      tagline: tagline == null || tagline.isEmpty ? null : tagline,
      genres: [for (final g in list(j['genres'])) g['name'] as String],
      runtime: (j['runtime'] as num?)?.toInt() ??
          (runtimes != null && runtimes.isNotEmpty
              ? (runtimes.first as num).toInt()
              : null),
      seasons: (j['number_of_seasons'] as num?)?.toInt(),
      episodes: (j['number_of_episodes'] as num?)?.toInt(),
      status: _statuses[j['status']] ?? j['status'] as String?,
      rating: rating == null || rating == 0 ? null : rating,
      votes: (j['vote_count'] as num?)?.toInt() ?? 0,
      backdropUrl: image(j['backdrop_path'], 'w780'),
      certification: certification,
      directors: type == TmdbType.movie
          ? jobs({'Director'})
          : [
              for (final c in list(j['created_by']))
                TmdbPerson(c['name'] as String,
                    role: 'Création', photoUrl: image(c['profile_path'])),
            ],
      writers: jobs({'Screenplay', 'Writer', 'Novel'}),
      cast: [
        for (final c in list(credits['cast']).take(20))
          TmdbPerson(c['name'] as String,
              role: c['character'] as String?,
              photoUrl: image(c['profile_path'])),
      ],
      networks: [for (final n in list(j['networks'])) n['name'] as String],
      trailer: videos.isEmpty
          ? null
          : Uri.https('www.youtube.com', '/watch', {'v': videos.first['key']}),
      recommendations: TmdbApi.parseTitles(
          j['recommendations'] as Map<String, dynamic>? ?? const {}, type),
      french: type == TmdbType.movie && j['release_dates'] is Map
          ? FrenchDates.fromApi(j['release_dates'] as Map<String, dynamic>)
          : null,
    );
  }
}

class TmdbGenre {
  const TmdbGenre(this.id, this.name);
  final int id;
  final String name;
}

/// Une liste de titres à parcourir (rangée de la page Découvrir, genre…).
/// Égalité par [key] : sert de clé de cache aux providers.
class TmdbFeed {
  const TmdbFeed(this.key, this.label, this.path, this.query, {this.type});

  final String key;
  final String label;
  final String path;
  final Map<String, Object> query;

  /// Type des résultats ; null : donné par chaque résultat (`media_type`).
  final TmdbType? type;

  @override
  bool operator ==(Object other) => other is TmdbFeed && other.key == key;

  @override
  int get hashCode => key.hashCode;

  static String _day(DateTime d) => d.toIso8601String().substring(0, 10);

  /// Rangées de la page Découvrir, centrées sur les sorties françaises : les
  /// filtres `region` + `with_release_type` portent sur les dates en France.
  static List<TmdbFeed> discover([DateTime? today]) {
    final now = today ?? DateTime.now();
    final day = _day(now);
    final ago = _day(now.subtract(const Duration(days: 90)));
    final soon = _day(now.add(const Duration(days: 180)));
    return [
      const TmdbFeed('trending', 'Tendances de la semaine', '/trending/all/week', {}),
      const TmdbFeed('now_playing', 'Au cinéma en France', '/movie/now_playing',
          {'region': 'FR'}, type: TmdbType.movie),
      TmdbFeed('fr_upcoming', 'Bientôt au cinéma en France', '/discover/movie', {
        'region': 'FR',
        'with_release_type': '2|3',
        'release_date.gte': day,
        'release_date.lte': soon,
        'sort_by': 'popularity.desc',
      }, type: TmdbType.movie),
      TmdbFeed('fr_digital', 'Récemment sortis en VOD en France', '/discover/movie', {
        'region': 'FR',
        'with_release_type': '4|5',
        'release_date.gte': ago,
        'release_date.lte': day,
        'sort_by': 'popularity.desc',
      }, type: TmdbType.movie),
      TmdbFeed('fr_movies', 'Films français à venir', '/discover/movie', {
        'region': 'FR',
        'with_original_language': 'fr',
        'with_release_type': '2|3',
        'release_date.gte': day,
        'sort_by': 'popularity.desc',
      }, type: TmdbType.movie),
      const TmdbFeed('popular_movies', 'Films populaires', '/movie/popular',
          {'region': 'FR'}, type: TmdbType.movie),
      const TmdbFeed('trending_tv', 'Séries tendance', '/trending/tv/week', {},
          type: TmdbType.tv),
      const TmdbFeed('on_the_air', 'Séries en cours de diffusion', '/tv/on_the_air',
          {}, type: TmdbType.tv),
      const TmdbFeed('fr_tv', 'Séries françaises', '/discover/tv', {
        'with_origin_country': 'FR',
        'sort_by': 'popularity.desc',
      }, type: TmdbType.tv),
    ];
  }

  /// Films populaires d'un genre, sortis ou à venir en France.
  factory TmdbFeed.genre(TmdbGenre g, TmdbType type) => TmdbFeed(
        'genre:${type.name}:${g.id}',
        g.name,
        '/discover/${type.name}',
        {
          'with_genres': '${g.id}',
          'sort_by': 'popularity.desc',
          if (type == TmdbType.movie) ...{
            'region': 'FR',
            'with_release_type': '2|3|4|5',
          },
        },
        type: type,
      );
}

/// API TMDB v3. La clé est soit la « clé d'API » (v3, 32 caractères), soit le
/// « jeton d'accès en lecture » (v4, un JWT), tous deux sur
/// themoviedb.org → Paramètres → API.
class TmdbEpisode {
  const TmdbEpisode({
    required this.season,
    required this.number,
    required this.name,
    this.overview,
    this.stillUrl,
    this.airDate,
    this.runtime,
  });

  factory TmdbEpisode.fromApi(Map<String, dynamic> json) {
    final still = json['still_path'] as String?;
    final overview = (json['overview'] as String?)?.trim();
    return TmdbEpisode(
      season: (json['season_number'] as num?)?.toInt() ?? 0,
      number: (json['episode_number'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      overview: overview == null || overview.isEmpty ? null : overview,
      stillUrl: still == null ? null : '${TmdbApi.imageBase}$still',
      airDate: DateTime.tryParse(json['air_date'] as String? ?? ''),
      runtime: (json['runtime'] as num?)?.toInt(),
    );
  }

  final int season;
  final int number;
  final String name;
  final String? overview;
  final String? stillUrl;
  final DateTime? airDate;

  /// En minutes.
  final int? runtime;
}

class TmdbApi {
  TmdbApi(String key)
      : _jwt = key.startsWith('eyJ'),
        _key = key,
        _dio = Dio(BaseOptions(
          baseUrl: 'https://api.themoviedb.org/3',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: (_) => true,
          headers: {if (key.startsWith('eyJ')) 'Authorization': 'Bearer $key'},
        ));

  static const imageBase = 'https://image.tmdb.org/t/p/w500';

  final bool _jwt;
  final String _key;
  final Dio _dio;

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, dynamic> query = const {}]) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.get(path, queryParameters: {
        ...query,
        'language': 'fr-FR',
        if (!_jwt) 'api_key': _key,
      });
    } on DioException catch (e) {
      throw TmdbException('TMDB injoignable : ${e.message ?? e.type.name}');
    }
    return switch (res.statusCode) {
      200 => res.data ?? const {},
      401 => throw const TmdbException('Clé TMDB refusée'),
      429 => throw const TmdbException(
          'Limite de requêtes TMDB atteinte, réessaie dans un instant'),
      _ => throw TmdbException('Réponse TMDB inattendue (HTTP ${res.statusCode})'),
    };
  }

  /// Films et séries d'une réponse paginée ; les personnes sont ignorées.
  static List<TmdbTitle> parseTitles(Map<String, dynamic> body, [TmdbType? type]) => [
        for (final r in (body['results'] as List? ?? const [])
            .whereType<Map<String, dynamic>>())
          if (type ?? TmdbType.values.asNameMap()[r['media_type']] case final t?)
            TmdbTitle.fromApi(r, t),
      ];

  /// Vérifie la clé.
  Future<void> check() => _get('/authentication');

  Future<List<TmdbTitle>> search(String query) async => parseTitles(
      await _get('/search/multi', {'query': query, 'include_adult': false}));

  /// Une page (20 titres) d'une liste ; les adultes sont exclus.
  Future<({List<TmdbTitle> items, int totalPages})> feed(TmdbFeed feed,
      {int page = 1}) async {
    final body = await _get(
        feed.path, {...feed.query, 'page': page, 'include_adult': false});
    return (
      items: parseTitles(body, feed.type),
      totalPages: (body['total_pages'] as num?)?.toInt() ?? page,
    );
  }

  Future<List<TmdbGenre>> genres(TmdbType type) async {
    final body = await _get('/genre/${type.name}/list');
    return [
      for (final g in (body['genres'] as List? ?? const []).whereType<Map>())
        TmdbGenre((g['id'] as num).toInt(), g['name'] as String? ?? ''),
    ];
  }

  Future<TmdbDetails> details(TmdbTitle t) async => TmdbDetails.fromApi(
      await _get('/${t.type.name}/${t.id}', {
        'append_to_response': [
          'credits',
          'videos',
          'recommendations',
          t.type == TmdbType.movie ? 'release_dates' : 'content_ratings',
        ].join(','),
        // Bandes-annonces françaises, sinon anglaises.
        'include_video_language': 'fr,en',
      }),
      t.type);

  /// Le titre le plus probable pour un nom de fichier : recherche avec
  /// l'année, puis sans (année du fichier parfois fausse ou absente).
  Future<TmdbTitle?> identify(String query, TmdbType type, {int? year}) async {
    final movie = type == TmdbType.movie;
    for (final y in [?year, null]) {
      final results = parseTitles(
          await _get('/search/${type.name}', {
            'query': query,
            'include_adult': false,
            movie ? 'year' : 'first_air_date_year': ?y,
          }),
          type);
      if (results.isNotEmpty) return results.first;
      if (year == null) break;
    }
    return null;
  }

  /// Épisodes d'une saison : titres, résumés, images.
  Future<List<TmdbEpisode>> season(int tvId, int season) async {
    final body = await _get('/tv/$tvId/season/$season');
    return [
      for (final e in (body['episodes'] as List? ?? const [])
          .whereType<Map<String, dynamic>>())
        TmdbEpisode.fromApi(e),
    ];
  }

  Future<FrenchDates> frenchDates(int movieId) async =>
      FrenchDates.fromApi(await _get('/movie/$movieId/release_dates'));
}

final tmdbProvider = Provider<TmdbApi?>((ref) {
  final key = ref.watch(settingsProvider).value?.tmdbKey ?? '';
  return key.isEmpty ? null : TmdbApi(key);
});
