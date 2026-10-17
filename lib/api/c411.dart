import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';

class C411Exception implements Exception {
  const C411Exception(this.message);
  final String message;
  @override
  String toString() => message;
}

class Release {
  Release(this.json);
  final Map<String, dynamic> json;

  Map<String, dynamic> get _media =>
      json['media'] as Map<String, dynamic>? ?? const {};
  Map<String, dynamic> get _tech =>
      json['tech'] as Map<String, dynamic>? ?? const {};

  int get id => (json['id'] as num).toInt();
  String get infoHash => (json['infoHash'] as String).toLowerCase();
  String get name => json['name'] as String? ?? '';
  String get subcategory =>
      (json['subcategory'] as Map?)?['name'] as String? ?? '';
  String get language => json['language'] as String? ?? '';
  int get size => (json['size'] as num?)?.toInt() ?? 0;
  int get seeders => (json['seeders'] as num?)?.toInt() ?? 0;
  int get leechers => (json['leechers'] as num?)?.toInt() ?? 0;
  int get completions => (json['completions'] as num?)?.toInt() ?? 0;
  String get uploader => json['uploader'] as String? ?? '';
  DateTime get createdAt => DateTime.parse(json['createdAt'] as String);
  bool get isFreeleech => json['isFreeleech'] == true;
  bool get isExclusive => json['isExclusive'] == true;
  String? get posterUrl => json['posterUrl'] as String?;

  String? get title => _media['title'] as String?;
  String? get originalTitle => _media['originalTitle'] as String?;
  int? get year => (_media['year'] as num?)?.toInt();
  double? get rating => (_media['rating'] as num?)?.toDouble();
  String? get overview => _media['overview'] as String?;
  String? get backdropUrl => _media['backdropUrl'] as String?;
  int? get runtime => (_media['runtime'] as num?)?.toInt();
  List<String> get genres => _strings(_media['genres']);
  List<String> get directors => _strings(_media['directors']);
  List<String> get cast => _strings(_media['cast']);

  String? get resolution => _tech['resolution'] as String?;
  String? get source => _tech['source'] as String?;
  String? get videoCodec => _tech['videoCodec'] as String?;
  String? get hdrFormat => _tech['hdrFormat'] as String?;
  String? get audioCodec => _tech['audioCodec'] as String?;
  String? get audioChannels => _tech['audioChannels'] as String?;
  List<String> get languages => _strings(_tech['languages']);

  static List<String> _strings(Object? v) =>
      (v as List? ?? const []).whereType<String>().toList();
}

class ReleasePage {
  const ReleasePage(this.items, this.page, this.totalPages, this.total);
  final List<Release> items;
  final int page;
  final int totalPages;
  final int total;
}

class Subcategory {
  const Subcategory(this.id, this.name);
  final int id;
  final String name;
}

class Category {
  const Category(this.id, this.name, this.subcategories);
  final int id;
  final String name;
  final List<Subcategory> subcategories;
}

class C411Api {
  C411Api(this.apiKey)
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (_) => true,
          headers: {'Authorization': 'Bearer $apiKey'},
        ));

  static const baseUrl = 'https://c411.org';
  final String apiKey;
  final Dio _dio;

  Future<Response<T>> _get<T>(String path,
      {Map<String, dynamic>? query, ResponseType? type}) async {
    final Response<T> res;
    try {
      res = await _dio.get<T>(path,
          queryParameters: query, options: Options(responseType: type));
    } on DioException catch (e) {
      throw C411Exception('C411 injoignable : ${e.message ?? e.type.name}');
    }
    switch (res.statusCode) {
      case 200:
        return res;
      case 401:
      case 403:
        throw const C411Exception('Clé API C411 refusée');
      case 429:
        throw const C411Exception(
            'Limite de requêtes C411 atteinte, réessaie dans une minute');
      default:
        throw C411Exception('Réponse C411 inattendue (HTTP ${res.statusCode})');
    }
  }

  Future<ReleasePage> releases({
    int page = 1,
    int perPage = 50,
    int? categoryId,
    int? subcategoryId,
    String query = '',
    String? sortBy,
  }) async {
    final res = await _get<Map<String, dynamic>>('/api/torrents', query: {
      'page': page,
      'perPage': perPage,
      'cat': ?categoryId,
      'subcat': ?subcategoryId,
      if (query.isNotEmpty) 'name': query,
      'sortBy': ?sortBy,
    });
    final body = res.data!;
    final meta = body['meta'] as Map<String, dynamic>? ?? const {};
    return ReleasePage(
      (body['data'] as List).cast<Map<String, dynamic>>().map(Release.new).toList(),
      (meta['page'] as num?)?.toInt() ?? page,
      (meta['totalPages'] as num?)?.toInt() ?? page,
      (meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<Category>> categories() async {
    final res = await _get<Map<String, dynamic>>('/api/categories');
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
  Future<Uint8List> downloadTorrent(String infoHash) async {
    final res = await _get<List<int>>('/api',
        query: {'t': 'get', 'id': infoHash, 'apikey': apiKey},
        type: ResponseType.bytes);
    final bytes = Uint8List.fromList(res.data ?? const []);
    // Un fichier .torrent est un dictionnaire bencodé : il commence par 'd'.
    if (bytes.isEmpty || bytes.first != 0x64) {
      final text = utf8.decode(bytes.take(200).toList(), allowMalformed: true);
      throw C411Exception('Le tracker n’a pas renvoyé de .torrent : $text');
    }
    return bytes;
  }
}

final c411Provider = Provider<C411Api?>((ref) {
  final s = ref.watch(settingsProvider).value;
  if (s == null || !s.hasTracker) return null;
  return C411Api(s.apiKey);
});

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final api = ref.watch(c411Provider);
  if (api == null) return const [];
  return api.categories();
});
