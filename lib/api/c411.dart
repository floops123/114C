import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'tracker.dart';

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
    final body = res.data!;
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
        type: ResponseType.bytes);
    return checkTorrent(tracker, res.data);
  }

  Release _release(Map<String, dynamic> json) {
    final media = json['media'] as Map<String, dynamic>? ?? const {};
    final tech = json['tech'] as Map<String, dynamic>? ?? const {};
    List<String> strings(Object? v) =>
        (v as List? ?? const []).whereType<String>().toList();
    int? integer(Object? v) => (v as num?)?.toInt();

    return Release(
      tracker: tracker,
      id: '${json['id']}',
      infoHash: (json['infoHash'] as String?)?.toLowerCase(),
      name: json['name'] as String? ?? '',
      title: media['title'] as String?,
      originalTitle: media['originalTitle'] as String?,
      year: integer(media['year']),
      subcategory: (json['subcategory'] as Map?)?['name'] as String? ?? '',
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
    );
  }
}
