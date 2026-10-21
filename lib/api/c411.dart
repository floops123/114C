import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'c411_profile.dart';
import 'quota.dart';
import 'tracker.dart';

/// Client JSON de C411 authentifié par le cookie de session du site
/// (en plus de l'origine). Utilisé pour les endpoints qui exigent d'être
/// connecté : liste des sorties « palliatives » (sans seeder depuis un
/// certain temps), par exemple.
///
/// Le format de réponse est le même que [C411Api] (mêmes clés `data` et
/// `meta`), donc on réutilise [_release] et [parsePage].
class C411SiteApi {
  C411SiteApi(this.cookie, {String? baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? Tracker.c411.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (_) => true,
          headers: {
            'Cookie': cookie,
            'Origin': 'https://c411.org',
            'Accept': 'application/json',
          },
        ));

  final String cookie;
  final Dio _dio;

  /// Sorties « palliatives » de C411 (sans seeder depuis un certain temps),
  /// triées par bounty décroissant. `age` est la valeur du paramètre
  /// `palliativeAge` (`recent`, `old`, etc.). Catégoriser (`cat`, `subcat`)
  /// n'est pas documenté par l'endpoint : on ne les envoie pas.
  Future<ReleasePage> palliative({
    String age = 'recent',
    int page = 1,
    int perPage = 25,
  }) async {
    try {
      final res = await trackerRequest(
          Tracker.c411,
          quota: c411SessionQuota,
          () => _dio.get<Map<String, dynamic>>(
                '/api/torrents',
                queryParameters: {
                  'palliative': 'only',
                  'palliativeAge': age,
                  'sortBy': 'bounty',
                  'sortOrder': 'desc',
                  'page': page,
                  'perPage': perPage,
                },
              ));
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw TrackerException('Cookie de session C411 refusé');
      }
      if (res.statusCode != 200 || res.data == null) {
        throw TrackerException(
            'Réponse C411 inattendue (HTTP ${res.statusCode})');
      }
      return C411Api.parsePage(res.data!, page);
    } on DioException catch (e) {
      throw TrackerException(
          'C411 injoignable : ${e.message ?? e.type.name}');
    }
  }

  /// Le .torrent d'une sortie, par le site (`/api/torrents/<infohash>/download`)
  /// : authentifié par le cookie de session plutôt que par la clé API. Pas
  /// d'espacement entre téléchargements sur cette voie (seule la voie par
  /// clé API se faisait refuser) ; budget du cookie ([c411SessionQuota],
  /// 200 / min), avec la reprise sur 429.
  Future<Uint8List> downloadTorrent(Release release) async {
    final hash = release.infoHash;
    if (hash == null || hash.isEmpty) {
      throw const TrackerException('C411 : sortie sans infohash');
    }
    final Response<List<int>> res;
    try {
      res = await trackerRequest(
          Tracker.c411,
          quota: c411SessionQuota,
          () => _dio.get<List<int>>('/api/torrents/$hash/download',
              options: Options(
                responseType: ResponseType.bytes,
                headers: {'Accept': 'application/x-bittorrent, */*'},
              )));
    } on DioException catch (e) {
      throw TrackerException(
          'C411 injoignable : ${e.message ?? e.type.name}');
    }
    return switch (res.statusCode) {
      200 => checkTorrent(Tracker.c411, res.data),
      401 || 403 => throw const TrackerException(
          'Cookie de session C411 refusé : recolle-le dans les Réglages'),
      404 => throw const TrackerException('C411 : torrent introuvable'),
      429 => throw const TrackerException('Limite de requêtes C411 '
          'atteinte malgré l’attente, réessaie dans une minute'),
      _ => throw TrackerException(
          'Réponse C411 inattendue (HTTP ${res.statusCode})'),
    };
  }

  /// GET d'un endpoint JSON du site, dans le budget du cookie.
  Future<Map<String, dynamic>> _json(String path, [Map<String, Object>? query]) async {
    final Response<Object> res;
    try {
      res = await trackerRequest(Tracker.c411, quota: c411SessionQuota,
          () => _dio.get<Object>(path, queryParameters: query));
    } on DioException catch (e) {
      throw TrackerException('C411 injoignable : ${e.message ?? e.type.name}');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const TrackerException('Cookie de session C411 refusé');
    }
    final data = res.data;
    if (res.statusCode != 200 || data is! Map) {
      throw TrackerException('Réponse C411 inattendue (HTTP ${res.statusCode})');
    }
    return data.cast<String, dynamic>();
  }

  /// Compte, niveau, Zen (solde, versements des [days] derniers jours,
  /// journée en cours), réanimations et classement, en parallèle. Une partie en échec manque ; un cookie
  /// refusé est une erreur.
  Future<C411Overview> overview({int days = 30}) async {
    Future<T?> part<T>(Future<T?> Function() load) async {
      try {
        return await load();
      } on TrackerException catch (e) {
        if (e.message.contains('refusé')) rethrow;
        return null;
      } on Object {
        return null; // Format inattendu : la partie manque.
      }
    }

    final results = await Future.wait<Object?>([
      part(() async => C411Account.parse(await _json('/api/auth/me'))),
      part(() async => C411Level.parse(await _json('/api/ic/level'))),
      part(() async => ZenBalance.parse(await _json('/api/tokens/balance'))),
      part(() async => ZenHistory.parse(
          await _json('/api/tokens/daily-stats', {'days': days}))),
      part(() async => ZenForecast.parse(await _json('/api/tokens/forecast'))),
      part(() async => C411Revival.parseList(await _json(
          '/api/profile/revivals', {'status': 'all', 'perPage': 100}))),
      part(() async => C411Leaderboard.parse(
          await _json('/api/ic/leaderboard/all_time', {'limit': 10}))),
    ]);
    return C411Overview(
      account: results[0] as C411Account?,
      level: results[1] as C411Level?,
      balance: results[2] as ZenBalance?,
      history: results[3] as ZenHistory?,
      forecast: results[4] as ZenForecast?,
      revivals: results[5] as List<C411Revival>?,
      leaderboard: results[6] as C411Leaderboard?,
    );
  }

  /// La journée en cours torrent par torrent, notée par le site (page
  /// [page]), par Zen décroissants.
  Future<ZenTorrentScores> forecastTorrents({int page = 1, int perPage = 100}) async =>
      ZenTorrentScores.parse(await _json('/api/tokens/forecast-torrents',
          {'page': page, 'perPage': perPage, 'order': 'desc'}));

  /// Toutes les pages de [forecastTorrents], [maxPages] au plus.
  Future<List<ZenTorrentScore>> allTorrentScores({int maxPages = 40}) async {
    final all = <ZenTorrentScore>[];
    for (var page = 1; page <= maxPages; page++) {
      final r = await forecastTorrents(page: page);
      all.addAll(r.items);
      if (r.items.isEmpty || all.length >= r.total) break;
    }
    return all;
  }

  void close() => _dio.close();
}

/// Clé de profil dans le champ `quality` d'une sortie : une chaîne
/// (`hc_optimized`), ou un objet dont l'une des valeurs en est une. Null
/// sinon (le champ est souvent vide).
String? qualityKey(Object? quality) {
  const keys = {'pure', 'hc_optimized', 'optimization', 'compatibility'};
  final candidates = switch (quality) {
    final String s => [s],
    final Map m => m.values.whereType<String>(),
    _ => const <String>[],
  };
  return candidates
      .map((s) => s.trim().toLowerCase())
      .where(keys.contains)
      .firstOrNull;
}

/// API JSON native de C411 : bien plus riche que son flux Torznab
/// (métadonnées TMDB, infos techniques, tri, compteurs).
class C411Api implements TrackerApi {
  C411Api(this.apiKey)
      : _dio = trackerDio(
            baseUrl: Tracker.c411.baseUrl,
            headers: {'Authorization': 'Bearer $apiKey'});

  final String apiKey;
  final Dio _dio;

  @override
  Tracker get tracker => Tracker.c411;

  @override
  List<ReleaseSort> get sorts => ReleaseSort.values;

  @override
  Set<ReleaseSort> get serverSorts => ReleaseSort.values.toSet();

  @override
  Future<ReleasePage> releases({
    int page = 1,
    int perPage = 50,
    int? categoryId,
    int? subcategoryId,
    String query = '',
    ReleaseSort sort = ReleaseSort.date,
    bool ascending = false,
  }) async {
    final res = await trackerGet<Map<String, dynamic>>(
        _dio, tracker, '/api/torrents',
        query: {
          'page': page,
          'perPage': perPage,
          'cat': ?categoryId,
          'subcat': ?subcategoryId,
          if (query.isNotEmpty) 'name': query,
          'sortBy': sort.apiField,
          'sortOrder': ascending ? 'asc' : 'desc',
        });
    return parsePage(res.data!, page);
  }

  /// Réponse de `/api/torrents`.
  static ReleasePage parsePage(Map<String, dynamic> body, [int page = 1]) {
    final meta = body['meta'] as Map<String, dynamic>? ?? const {};
    return ReleasePage(
      (body['data'] as List).cast<Map<String, dynamic>>().map(_release).toList(),
      (meta['page'] as num?)?.toInt() ?? page,
      (meta['totalPages'] as num?)?.toInt() ?? page,
      (meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<List<Category>> categories() async {
    final res =
        await trackerGet<Map<String, dynamic>>(_dio, tracker, '/api/categories');
    return (res.data!['data'] as List).cast<Map<String, dynamic>>().map((c) {
      final subs = (c['subcategories'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map((s) => Subcategory((s['id'] as num).toInt(), s['name'] as String))
          .toList();
      return Category((c['id'] as num).toInt(), c['name'] as String, subs);
    }).toList();
  }

  /// Le .torrent n'est exposé que par l'endpoint Torznab, qui attend la clé
  /// en paramètre `apikey` (le header Bearer y est refusé).
  @override
  Future<Uint8List> downloadTorrent(Release release) async {
    final res = await trackerGet<List<int>>(_dio, tracker, '/api',
        query: {'t': 'get', 'id': release.infoHash, 'apikey': apiKey},
        type: ResponseType.bytes,
        download: true);
    return checkTorrent(tracker, res.data);
  }

  @override
  void close() => _dio.close();

  static Release _release(Map<String, dynamic> json) {
    final media = json['media'] as Map<String, dynamic>? ?? const {};
    final tech = json['tech'] as Map<String, dynamic>? ?? const {};
    List<String> strings(Object? v) =>
        (v as List? ?? const []).whereType<String>().toList();
    int? integer(Object? v) => (v as num?)?.toInt();

    return Release(
      tracker: Tracker.c411,
      id: '${json['id']}',
      infoHash: (json['infoHash'] as String?)?.toLowerCase(),
      name: json['name'] as String? ?? '',
      title: media['title'] as String?,
      originalTitle: media['originalTitle'] as String?,
      year: integer(media['year']),
      subcategory: (json['subcategory'] as Map?)?['name'] as String? ?? '',
      categories: [
        for (final k in ['category', 'subcategory'])
          if ((json[k] as Map?)?['name'] case final String n) n,
      ],
      size: integer(json['size']) ?? 0,
      seeders: integer(json['seeders']) ?? 0,
      leechers: integer(json['leechers']) ?? 0,
      completions: integer(json['completions']) ?? 0,
      uploader: json['uploader'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      isFreeleech: json['isFreeleech'] == true,
      isExclusive: json['isExclusive'] == true,
      // Les jeux, livres, etc. n'ont pas d'affiche TMDB mais une image générique.
      posterUrl: json['posterUrl'] as String? ?? media['imageUrl'] as String?,
      backdropUrl: media['backdropUrl'] as String?,
      overview: media['overview'] as String?,
      rating: (media['rating'] as num?)?.toDouble(),
      runtime: integer(media['runtime']),
      genres: strings(media['genres']),
      directors: strings(media['directors']),
      cast: strings(media['cast']),
      resolution: tech['resolution'] as String?,
      source: tech['source'] as String?,
      videoCodec: tech['videoCodec'] as String?,
      hdrFormat: tech['hdrFormat'] as String?,
      audioCodec: tech['audioCodec'] as String?,
      audioChannels: tech['audioChannels'] as String?,
      languages: strings(tech['languages']),
      mediaKind: media['kind'] as String?,
      qualityProfile: qualityKey(json['quality']),
      bountyZen: (json['bountyZen'] as num?)?.toInt() ?? 0,
    );
  }
}
