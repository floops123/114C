import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import 'c411.dart';
import 'torznab.dart';

/// Trackers pris en charge. Ajouter un tracker Torznab = une ligne ici.
enum Tracker {
  c411('C411', 'https://c411.org'),
  tr4ker('tr4ker', 'https://tr4ker.net/api/', apiKeyHeader: 'X-Api-Key');

  const Tracker(this.label, this.baseUrl, {this.apiKeyHeader});
  final String label;
  final String baseUrl;

  /// En-tête d'authentification attendu par le tracker, en plus du paramètre
  /// Torznab standard `apikey`.
  final String? apiKeyHeader;

  TrackerApi client(String apiKey) => switch (this) {
        c411 => C411Api(apiKey),
        tr4ker => TorznabApi(this, apiKey),
      };
}

class TrackerException implements Exception {
  const TrackerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Une sortie, quel que soit le tracker. Les champs de métadonnées (TMDB,
/// technique) sont optionnels : Torznab n'en fournit que peu.
class Release {
  const Release({
    required this.tracker,
    required this.id,
    required this.name,
    required this.createdAt,
    this.infoHash,
    this.downloadUrl,
    this.title,
    this.originalTitle,
    this.year,
    this.subcategory = '',
    this.size = 0,
    this.seeders = 0,
    this.leechers = 0,
    this.completions = 0,
    this.uploader = '',
    this.isFreeleech = false,
    this.isExclusive = false,
    this.posterUrl,
    this.backdropUrl,
    this.overview,
    this.rating,
    this.runtime,
    this.genres = const [],
    this.directors = const [],
    this.cast = const [],
    this.resolution,
    this.source,
    this.videoCodec,
    this.hdrFormat,
    this.audioCodec,
    this.audioChannels,
    this.languages = const [],
  });

  final Tracker tracker;
  final String id;

  /// En minuscules ; null si le tracker ne le fournit pas.
  final String? infoHash;

  /// Lien direct vers le .torrent (ou un magnet), si le tracker le donne.
  final String? downloadUrl;

  final String name;
  final String? title;
  final String? originalTitle;
  final int? year;
  final String subcategory;
  final int size;
  final int seeders;
  final int leechers;
  final int completions;
  final String uploader;
  final DateTime createdAt;
  final bool isFreeleech;
  final bool isExclusive;
  final String? posterUrl;
  final String? backdropUrl;
  final String? overview;
  final double? rating;
  final int? runtime;
  final List<String> genres;
  final List<String> directors;
  final List<String> cast;
  final String? resolution;
  final String? source;
  final String? videoCodec;
  final String? hdrFormat;
  final String? audioCodec;
  final String? audioChannels;
  final List<String> languages;
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

abstract class TrackerApi {
  Tracker get tracker;

  /// Tri par seeders disponible côté serveur.
  bool get supportsSort;

  Future<ReleasePage> releases({
    int page = 1,
    int perPage = 50,
    int? categoryId,
    int? subcategoryId,
    String query = '',
    String? sortBy,
  });

  Future<List<Category>> categories();

  /// Le .torrent brut de la sortie.
  Future<Uint8List> downloadTorrent(Release release);
}

/// Client HTTP commun : délais, traduction des erreurs HTTP en messages.
Dio trackerDio({String? baseUrl, Map<String, Object>? headers}) => Dio(
      BaseOptions(
        baseUrl: baseUrl ?? '',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (_) => true,
        headers: headers,
      ),
    );

Future<Response<T>> trackerGet<T>(
  Dio dio,
  Tracker tracker,
  String path, {
  Map<String, dynamic>? query,
  ResponseType? type,
}) async {
  final Response<T> res;
  try {
    res = await dio.get<T>(path,
        queryParameters: query, options: Options(responseType: type));
  } on DioException catch (e) {
    throw TrackerException(
        '${tracker.label} injoignable : ${e.message ?? e.type.name}');
  }
  return switch (res.statusCode) {
    200 => res,
    401 || 403 => throw TrackerException('Clé API ${tracker.label} refusée'),
    429 => throw TrackerException(
        'Limite de requêtes ${tracker.label} atteinte, réessaie dans une minute'),
    _ => throw TrackerException(
        'Réponse ${tracker.label} inattendue (HTTP ${res.statusCode})'),
  };
}

/// Vérifie qu'on a bien reçu un .torrent (dictionnaire bencodé, commence par 'd').
Uint8List checkTorrent(Tracker tracker, List<int>? data) {
  final bytes = Uint8List.fromList(data ?? const []);
  if (bytes.isEmpty || bytes.first != 0x64) {
    final text = utf8.decode(bytes.take(200).toList(), allowMalformed: true);
    throw TrackerException(
        '${tracker.label} n’a pas renvoyé de .torrent : $text');
  }
  return bytes;
}

/// Clients des trackers configurés (clé API renseignée), dans l'ordre de l'enum.
final trackersProvider = Provider<Map<Tracker, TrackerApi>>((ref) {
  final s = ref.watch(settingsProvider).value;
  if (s == null) return const {};
  return {
    for (final t in Tracker.values)
      if ((s.apiKeys[t.name] ?? '').isNotEmpty) t: t.client(s.apiKeys[t.name]!),
  };
});
