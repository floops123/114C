import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/release_name.dart';
import 'quota.dart';
import 'tracker.dart';

/// Torrent local soumis au scanner de cross-seed d'AstraTorrent.
typedef AstraQuery = ({String name, int size, String hash});

/// AstraTorrent :
/// - `/api/torrents.php` (public) : sorties en JSON, recherche `q`, filtre
///   `category`, tri `sort` (seeders, taille ; date par défaut, toujours
///   décroissant), `limit` jusqu'à 1000, sans pagination ;
/// - `/api/cross_seed.php` (passkey) : on lui envoie par lots les torrents
///   terminés (nom, taille, infohash), il renvoie ses correspondances ;
/// - `/api/download.php` (passkey) : le .torrent.
class AstraApi implements TrackerApi {
  AstraApi(this.passkey)
      : _dio = trackerDio(baseUrl: Tracker.astra.baseUrl, headers: {
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) C411Remote AstraCrossSeed',
        })
          ..options.receiveTimeout = const Duration(seconds: 60);

  final String passkey;
  final Dio _dio;

  /// Taille des lots, celle du script officiel.
  static const batchSize = 150;

  /// Plafond de `limit` côté site.
  static const maxLimit = 1000;

  /// Catégories (valeur du paramètre `category`), sans sous-catégories : le
  /// site en a des dizaines, mal normalisées.
  static const _categories = {
    1: ('films', 'Films'),
    2: ('series', 'Séries'),
    3: ('anime', 'Animés'),
    4: ('music', 'Musique'),
    5: ('books', 'Livres'),
    6: ('games', 'Jeux'),
    7: ('apps', 'Logiciels'),
    8: ('xxx', 'XXX'),
  };

  /// Tris décroissants faits par le site.
  static const _siteSorts = {
    ReleaseSort.date: null,
    ReleaseSort.seeders: 'seeders',
    ReleaseSort.size: 'size',
  };

  /// Les autres tris (et tous les tris croissants) portent sur les
  /// [maxLimit] dernières sorties, chargées une fois puis découpées en pages.
  ({String key, List<Release> items})? _sorted;

  @override
  Tracker get tracker => Tracker.astra;

  @override
  List<ReleaseSort> get sorts =>
      ReleaseSort.values.where((s) => s != ReleaseSort.comments).toList();

  /// Tous faits ici : le tri local de l'écran ne verrait qu'une partie.
  @override
  Set<ReleaseSort> get serverSorts => sorts.toSet();

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
    final filter = {
      if (query.trim().isNotEmpty) 'q': query.trim(),
      'category': ?_categories[categoryId]?.$1,
    };
    final skip = (page - 1) * perPage;

    // Pas d'offset : on redemande une liste plus longue à chaque page.
    if (!ascending && _siteSorts.containsKey(sort)) {
      final limit = math.min(page * perPage, maxLimit);
      final items = await _list(
          {...filter, 'sort': ?_siteSorts[sort], 'limit': limit});
      final more = items.length == limit && limit < maxLimit;
      return ReleasePage(
          items.skip(skip).toList(), page, more ? page + 1 : page, 0);
    }

    final key = '$filter|${sort.name}|$ascending';
    var sorted = _sorted;
    if (page == 1 || sorted == null || sorted.key != key) {
      final items = await _list({...filter, 'limit': maxLimit})
        ..sort((a, b) => ascending ? sort.compare(a, b) : sort.compare(b, a));
      _sorted = sorted = (key: key, items: items);
    }
    final items = sorted.items;
    return ReleasePage(items.skip(skip).take(perPage).toList(), page,
        (items.length / perPage).ceil(), items.length);
  }

  Future<List<Release>> _list(Map<String, Object> query) async {
    final res = await trackerGet<Object>(_dio, tracker, '/api/torrents.php',
        query: query);
    return parseTorrents(res.data, passkey);
  }

  @override
  Future<List<Category>> categories() async => [
        for (final MapEntry(key: id, value: (_, name)) in _categories.entries)
          Category(id, name, const []),
      ];

  /// Réponse de `torrents.php`.
  static List<Release> parseTorrents(Object? data, String passkey) {
    final torrents = _json(data)['torrents'];
    if (torrents is! List) {
      throw const TrackerException('AstraTorrent : réponse inattendue');
    }
    return [
      for (final t in torrents.whereType<Map>()) _fromList(t, passkey),
    ];
  }

  static Release _fromList(Map t, String passkey) {
    final name = t['name'] as String? ?? '';
    final parsed = ReleaseName.parse(name);
    int integer(String k) => (t[k] as num?)?.toInt() ?? 0;
    String? text(String k) {
      final v = (t[k] as String?)?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    return Release(
      tracker: Tracker.astra,
      id: '${t['id']}',
      infoHash: text('info_hash')?.toLowerCase(),
      downloadUrl: '/api/download.php?id=${t['id']}&passkey=$passkey',
      name: name,
      title: text('clean_title') ?? parsed.title,
      year: parsed.year,
      subcategory: text('sub_category') ?? parsed.kind,
      categories: [
        for (final (slug, label) in _categories.values)
          if (slug == text('category')) label,
      ],
      size: integer('size_bytes'),
      seeders: integer('seeders'),
      leechers: integer('leechers'),
      completions: integer('completed_count'),
      uploader: text('uploader_name') ?? '',
      createdAt: parseParisTime(text('created_at') ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isFreeleech: integer('is_freeleech') == 1,
      posterUrl: text('poster_url'),
      overview: text('synopsis'),
      resolution: parsed.resolution,
      source: parsed.source,
      videoCodec: parsed.videoCodec,
      languages: parsed.languages,
    );
  }

  /// Pseudo du compte de la passkey ; null si le site ne la reconnaît pas.
  Future<String?> username() async =>
      ((_json((await _scan(const [])).data)['user'] as Map?)?['username'])
          as String?;

  /// Correspondances par infohash local (en minuscules) ; les torrents sans
  /// correspondance sont absents. Un appel par lot de [batchSize].
  Future<Map<String, Release>> bulkScan(List<AstraQuery> items) async {
    final matches = <String, Release>{};
    for (var start = 0; start < items.length; start += batchSize) {
      final res = await _scan(items.skip(start).take(batchSize));
      matches.addAll(parseScan(res.data));
    }
    return matches;
  }

  Future<Response<Object>> _scan(Iterable<AstraQuery> batch) =>
      trackerPost<Object>(_dio, tracker, '/api/cross_seed.php',
          query: {'action': 'bulk_scan', 'passkey': passkey},
          data: {
            'items': [
              for (final i in batch)
                {'name': i.name, 'size': i.size, 'info_hash': i.hash},
            ],
          });

  /// Réponse de `bulk_scan` : correspondances par infohash local.
  static Map<String, Release> parseScan(Object? data) {
    final body = _json(data);
    // Passkey inconnue : réponse « success », sans résultat ni utilisateur.
    if (body.containsKey('user') && body['user'] == null) {
      throw const TrackerException('Passkey AstraTorrent refusée');
    }
    final results = body['results'];
    if (results is! List) {
      final error = body['error'] ?? body['message'];
      throw TrackerException(error != null
          ? 'AstraTorrent : $error'
          : 'AstraTorrent : réponse inattendue');
    }
    return {
      for (final r in results.whereType<Map>())
        if ((r['query'] as Map?)?['info_hash'] case final String hash
            when r['matched'] == true && r['torrent'] is Map)
          hash.toLowerCase(): _fromScan(r['torrent'] as Map),
    };
  }

  static Release _fromScan(Map torrent) => Release(
        tracker: Tracker.astra,
        id: '${torrent['id']}',
        name: torrent['name'] as String? ?? '',
        size: (torrent['size_bytes'] as num?)?.toInt() ?? 0,
        infoHash: (torrent['info_hash'] as String?)?.toLowerCase(),
        downloadUrl: torrent['download_url'] as String?,
        seeders: (torrent['seeders'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  @override
  Future<Uint8List> downloadTorrent(Release release) async {
    final url = release.downloadUrl;
    if (url == null) {
      throw const TrackerException('AstraTorrent : pas de lien de téléchargement');
    }
    final res = await trackerRequest(
        tracker,
        () => _dio.get<List<int>>(url,
            options: Options(
              responseType: ResponseType.bytes,
              headers: {'Accept': 'application/x-bittorrent, */*'},
            )),
        download: true);
    if (res.statusCode != 200) {
      throw TrackerException(
          'AstraTorrent : téléchargement refusé (HTTP ${res.statusCode})');
    }
    return checkTorrent(tracker, res.data);
  }

  /// Le serveur PHP ne renvoie pas toujours un type JSON : on décode au besoin.
  static Map<String, dynamic> _json(Object? data) {
    try {
      final value = data is String ? jsonDecode(data) : data;
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // Traité ci-dessous.
    }
    throw const TrackerException('AstraTorrent : réponse illisible');
  }

  @override
  void close() => _dio.close();
}

/// `2026-10-17 15:17:38`, heure de Paris (le flux RSS du site l'annonce en
/// +0200 l'été) → DateTime UTC.
DateTime? parseParisTime(String input) {
  final local = DateTime.tryParse(input.replaceFirst(' ', 'T'));
  if (local == null) return null;
  final asUtc = DateTime.utc(local.year, local.month, local.day, local.hour,
      local.minute, local.second);
  // Heure d'été : du dernier dimanche de mars au dernier dimanche d'octobre,
  // à 1 h UTC.
  DateTime lastSunday(int month) {
    final last = DateTime.utc(local.year, month + 1, 0, 1);
    return last.subtract(Duration(days: last.weekday % 7));
  }

  final summer = asUtc.subtract(const Duration(hours: 2));
  final isSummer =
      !summer.isBefore(lastSunday(3)) && summer.isBefore(lastSunday(10));
  return isSummer ? summer : asUtc.subtract(const Duration(hours: 1));
}
