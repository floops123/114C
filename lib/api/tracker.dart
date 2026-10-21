import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import 'astra.dart';
import 'c411.dart';
import 'quota.dart';
import 'torznab.dart';

/// Trackers pris en charge. Ajouter un tracker Torznab = une ligne ici.
enum Tracker {
  // Refuse déjà sous ses 120 / min annoncées, surtout sur les .torrent :
  // budget et espacement plus prudents.
  c411('C411', 'https://c411.org',
      announceHint: 'c411',
      requestBudget: 80,
      downloadSpacing: Duration(seconds: 3)),
  tr4ker('tr4ker', 'https://tr4ker.net/api/',
      apiKeyHeader: 'X-Api-Key', announceHint: 'tr4ker'),
  nostradamus('Nostradamus', 'https://nostradamus.foo/api',
      announceHint: 'nostradamus'),
  draupnirr('Draupnirr', 'https://draupnirr.xyz/torznab/api',
      apiKeyHeader: 'X-Api-Key', announceHint: 'draupnirr'),

  // Limite non publiée : prudence.
  astra('AstraTorrent', 'https://astratorrent.la',
      announceHint: 'astratorrent', keyLabel: 'Passkey', requestsPerMinute: 60);

  const Tracker(this.label, this.baseUrl,
      {this.apiKeyHeader,
      required this.announceHint,
      this.keyLabel = 'Clé API',
      this.requestsPerMinute = 120,
      this._requestBudget,
      this.downloadSpacing = const Duration(seconds: 2)});
  final String label;
  final String baseUrl;

  /// Requêtes permises par minute (voir docs/dev/api.md).
  final int requestsPerMinute;
  final int? _requestBudget;

  /// Requêtes que l'application s'autorise par minute : 90 % de
  /// [requestsPerMinute] (marge pour l'horloge du serveur, un autre appareil
  /// avec la même clé), sauf budget plus prudent. Voir [trackerQuotas].
  int get requestBudget => _requestBudget ?? (requestsPerMinute * 0.9).floor();

  /// Écart minimal entre deux téléchargements de .torrent : un envoi en
  /// masse ne les enchaîne pas en rafale.
  final Duration downloadSpacing;

  /// Nom de l'identifiant dans les réglages.
  final String keyLabel;

  /// Fragment de nom d'hôte des URL d'annonce : sert à reconnaître le tracker
  /// d'origine d'un torrent de Transmission (cross-seed).
  final String announceHint;

  /// Tracker d'origine d'après les URL d'annonce, ou null (autre tracker).
  static Tracker? fromAnnounces(Iterable<String> announces) {
    for (final url in announces) {
      final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
      for (final t in values) {
        if (host.contains(t.announceHint)) return t;
      }
    }
    return null;
  }

  /// En-tête d'authentification attendu par le tracker, en plus du paramètre
  /// Torznab standard `apikey`.
  final String? apiKeyHeader;

  TrackerApi client(String apiKey) => switch (this) {
        c411 => C411Api(apiKey),
        tr4ker || nostradamus || draupnirr => TorznabApi(this, apiKey),
        astra => AstraApi(apiKey),
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
    this.categories = const [],
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
    this.mediaKind,
    this.qualityProfile,
    this.bountyZen = 0,
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

  /// Catégories et sous-catégories du tracker auxquelles la sortie est
  /// rattachée, dans le vocabulaire de [TrackerApi.categories] (noms du
  /// `caps` pour Torznab). Sert au filtre par catégorie de l'import en masse.
  final List<String> categories;
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

  /// Prime en Zen offerte à qui réanime la sortie (C411, liste palliative).
  final int bountyZen;

  /// Profil de qualité annoncé par le tracker (C411 : `pure`,
  /// `hc_optimized`, `optimization`, `compatibility`), s'il le fait.
  final String? qualityProfile;

  /// Fiche rattachée par le tracker (C411) : `movie`, `tv`, `music`, `game`…
  /// [title], [originalTitle] et [year] viennent alors de TMDB, ce qui
  /// permet de reconnaître un film sans se fier au nom de la release.
  final String? mediaKind;
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

/// Critères de tri des sorties. [compare] trie par ordre croissant ; il sert
/// quand le tracker ne sait pas trier lui-même (Torznab).
enum ReleaseSort {
  date('Date de publication', 'createdAt'),
  seeders('Seeders', 'seeders'),
  leechers('Leechers', 'leechers'),
  completions('Téléchargements', 'completions'),
  size('Taille', 'size'),
  name('Nom', 'name', ascendingByDefault: true),
  comments('Commentaires', 'comments');

  const ReleaseSort(this.label, this.apiField,
      {this.ascendingByDefault = false});
  final String label;

  /// Valeur du paramètre `sortBy` de l'API C411.
  final String apiField;
  final bool ascendingByDefault;

  int compare(Release a, Release b) => switch (this) {
        date => a.createdAt.compareTo(b.createdAt),
        seeders => a.seeders.compareTo(b.seeders),
        leechers => a.leechers.compareTo(b.leechers),
        completions => a.completions.compareTo(b.completions),
        size => a.size.compareTo(b.size),
        name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        comments => 0,
      };
}

abstract class TrackerApi {
  Tracker get tracker;

  /// Tris proposés pour ce tracker.
  List<ReleaseSort> get sorts;

  /// Tris faits par le serveur ; les autres sont appliqués localement aux
  /// résultats déjà chargés.
  Set<ReleaseSort> get serverSorts;

  Future<ReleasePage> releases({
    int page = 1,
    int perPage = 50,
    int? categoryId,
    int? subcategoryId,
    String query = '',
    ReleaseSort sort = ReleaseSort.date,
    bool ascending = false,
  });

  Future<List<Category>> categories();

  /// Le .torrent brut de la sortie.
  Future<Uint8List> downloadTorrent(Release release);

  /// Ferme le client HTTP (réglages changés : un nouveau client le remplace).
  void close();
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

/// GET vers un tracker ; [download] : téléchargement d'un .torrent, espacé
/// des précédents (voir [Tracker.downloadSpacing]).
Future<Response<T>> trackerGet<T>(
  Dio dio,
  Tracker tracker,
  String path, {
  Map<String, dynamic>? query,
  ResponseType? type,
  bool download = false,
}) =>
    _trackerSend(
        tracker,
        () => dio.get<T>(path,
            queryParameters: query, options: Options(responseType: type)),
        download: download);

/// POST d'un corps JSON, mêmes erreurs que [trackerGet].
Future<Response<T>> trackerPost<T>(
  Dio dio,
  Tracker tracker,
  String path, {
  Map<String, dynamic>? query,
  Object? data,
}) =>
    _trackerSend(
        tracker, () => dio.post<T>(path, queryParameters: query, data: data));

Future<Response<T>> _trackerSend<T>(
    Tracker tracker, Future<Response<T>> Function() send,
    {bool download = false}) async {
  final Response<T> res;
  try {
    res = await trackerRequest(tracker, send, download: download);
  } on DioException catch (e) {
    throw TrackerException(
        '${tracker.label} injoignable : ${e.message ?? e.type.name}');
  }
  return switch (res.statusCode) {
    200 => res,
    401 || 403 => throw TrackerException('Clé API ${tracker.label} refusée'),
    429 => throw TrackerException('Limite de requêtes ${tracker.label} '
        'atteinte malgré l’attente, réessaie dans une minute'),
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
  final clients = {
    for (final t in Tracker.values)
      if ((s.apiKeys[t.name] ?? '').isNotEmpty) t: t.client(s.apiKeys[t.name]!),
  };
  // Réglages changés : les anciens clients libèrent leurs connexions.
  ref.onDispose(() {
    for (final c in clients.values) {
      c.close();
    }
  });
  return clients;
});
