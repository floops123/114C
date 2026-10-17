import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/release_name.dart';
import '../core/settings.dart';
import '../core/titles.dart';
import 'tmdb.dart';
import 'tracker.dart';

class JellyfinException implements Exception {
  const JellyfinException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Film ou série de la bibliothèque Jellyfin.
class JellyfinItem {
  const JellyfinItem({
    required this.id,
    required this.name,
    required this.type,
    this.originalTitle,
    this.year,
    this.serverId,
    this.tmdbId,
    this.played = false,
    this.progress,
    this.resume,
    this.season,
    this.episode,
    this.overview,
  });

  final String id;
  final String name;

  /// `Movie` ou `Series`.
  final String type;
  final String? originalTitle;
  final int? year;
  final String? serverId;
  final String? tmdbId;
  final bool played;

  /// Lecture entamée (0 à 1).
  final double? progress;

  /// Position de reprise enregistrée par Jellyfin.
  final Duration? resume;

  /// Saison et numéro d'un épisode (`Episode`).
  final int? season;
  final int? episode;
  final String? overview;

  bool get isSeries => type == 'Series';

  factory JellyfinItem.fromApi(Map<String, dynamic> j) {
    final user = j['UserData'] as Map<String, dynamic>? ?? const {};
    final percent = (user['PlayedPercentage'] as num?)?.toDouble();
    // Jellyfin compte en « ticks » de 100 ns.
    final ticks = (user['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
    return JellyfinItem(
      id: j['Id'] as String,
      name: j['Name'] as String? ?? '',
      type: j['Type'] as String? ?? '',
      originalTitle: j['OriginalTitle'] as String?,
      year: (j['ProductionYear'] as num?)?.toInt(),
      serverId: j['ServerId'] as String?,
      tmdbId: ((j['ProviderIds'] as Map?)?['Tmdb'] as String?)?.trim(),
      played: user['Played'] == true,
      progress: percent == null || percent <= 0 ? null : percent / 100,
      resume: ticks > 0 ? Duration(microseconds: ticks ~/ 10) : null,
      season: (j['ParentIndexNumber'] as num?)?.toInt(),
      episode: (j['IndexNumber'] as num?)?.toInt(),
      overview: j['Overview'] as String?,
    );
  }
}

/// API Jellyfin : clé d'API créée dans Tableau de bord → Clés API.
class JellyfinClient {
  JellyfinClient({required String url, required this.apiKey})
      : base = url.trim().replaceAll(RegExp(r'/+$'), ''),
        _dio = Dio(BaseOptions(
          baseUrl: url.trim().replaceAll(RegExp(r'/+$'), ''),
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: (_) => true,
          headers: {
            'Authorization': 'MediaBrowser Token="$apiKey"',
            'X-Emby-Token': apiKey,
          },
        ));

  /// Adresse du serveur, sans « / » final.
  final String base;
  final String apiKey;
  final Dio _dio;

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, dynamic>? query]) async {
    final Response<Object> res;
    try {
      res = await _dio.get(path, queryParameters: query);
    } on DioException catch (e) {
      throw JellyfinException('Jellyfin injoignable : ${e.message ?? e.type.name}');
    }
    final data = res.data;
    return switch (res.statusCode) {
      200 when data is Map<String, dynamic> => data,
      200 => throw const JellyfinException('Réponse Jellyfin illisible'),
      401 || 403 => throw const JellyfinException('Clé d’API Jellyfin refusée'),
      _ => throw JellyfinException(
          'Réponse Jellyfin inattendue (HTTP ${res.statusCode})'),
    };
  }

  /// Nom et version du serveur (teste aussi la clé).
  Future<String> check() async {
    final info = await _get('/System/Info');
    return '${info['ServerName'] ?? 'Jellyfin'} ${info['Version'] ?? ''}'.trim();
  }

  /// Tous les films et séries de la bibliothèque, en une requête (champs
  /// réduits : nom, titre original, année, identifiants).
  Future<JellyfinLibrary> library() async {
    final body = await _get('/Items', {
      'IncludeItemTypes': 'Movie,Series',
      'Recursive': true,
      'Fields': 'ProviderIds,ProductionYear,OriginalTitle',
      'EnableImages': false,
    });
    return JellyfinLibrary([
      for (final i in (body['Items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>())
        JellyfinItem.fromApi(i),
    ]);
  }

  /// Épisodes d'une série, dans l'ordre (saison, numéro).
  Future<List<JellyfinItem>> episodes(String seriesId) async {
    final body = await _get('/Shows/$seriesId/Episodes', {
      'Fields': 'Overview',
      'EnableImages': false,
    });
    return [
      for (final i in (body['Items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>())
        JellyfinItem.fromApi(i),
    ]..sort((a, b) {
        final s = (a.season ?? 0).compareTo(b.season ?? 0);
        return s != 0 ? s : (a.episode ?? 0).compareTo(b.episode ?? 0);
      });
  }

  /// Flux du fichier d'origine (`static=true`) : aucun transcodage, le
  /// lecteur décode tout lui-même (MKV, HEVC, AV1, HDR, TrueHD, DTS-HD, sous-
  /// titres intégrés…). La clé passe aussi dans l'adresse : mpv la garde pour
  /// les requêtes de déplacement dans le fichier.
  Uri streamUrl(String itemId) =>
      Uri.parse('$base/Videos/$itemId/stream?static=true&api_key=$apiKey');

  /// En-têtes d'authentification pour le lecteur.
  Map<String, String> get headers => {'X-Emby-Token': apiKey};
}

final jellyfinProvider = Provider<JellyfinClient?>((ref) {
  final s = ref.watch(settingsProvider).value;
  if (s == null || s.jellyfinUrl.isEmpty || s.jellyfinKey.isEmpty) return null;
  return JellyfinClient(url: s.jellyfinUrl, apiKey: s.jellyfinKey);
});

/// Index des films et séries de Jellyfin, pour savoir sans requête si un
/// titre ou une sortie est déjà sur le disque. Relu toutes les 15 minutes ;
/// null si Jellyfin n'est pas configuré.
class JellyfinLibrary {
  JellyfinLibrary(this.items) {
    for (final i in items) {
      if (i.tmdbId case final id? when id.isNotEmpty) _byTmdb['${i.type}:$id'] = i;
      for (final name in {i.name, ?i.originalTitle}) {
        (_byKey[titleKey(name)] ??= []).add(i);
      }
    }
  }

  final List<JellyfinItem> items;
  final _byTmdb = <String, JellyfinItem>{};
  final _byKey = <String, List<JellyfinItem>>{};

  static String _type(TmdbType t) => t == TmdbType.movie ? 'Movie' : 'Series';

  /// Premier élément du bon type portant l'un de ces titres ; pour un film,
  /// à un an près si les deux années sont connues.
  JellyfinItem? _byTitle(Iterable<String> titles, String? type, int? year) {
    for (final title in titles) {
      for (final i in _byKey[titleKey(title)] ?? const <JellyfinItem>[]) {
        if (type != null && i.type != type) continue;
        if (i.type == 'Movie' &&
            year != null &&
            i.year != null &&
            (i.year! - year).abs() > 1) {
          continue;
        }
        return i;
      }
    }
    return null;
  }

  /// Un film ou une série TMDB : par identifiant TMDB, sinon par titre.
  JellyfinItem? find(TmdbTitle t) =>
      _byTmdb['${_type(t.type)}:${t.id}'] ??
      _byTitle({t.title, ?t.originalTitle}, _type(t.type), t.year);

  /// Une sortie de tracker : titres de sa fiche (C411, AstraTorrent), sinon
  /// celui lu dans son nom ; série si sa fiche ou son nom l'indique.
  JellyfinItem? forRelease(Release r) {
    final parsed = ReleaseName.parse(r.name);
    final type = switch (r.mediaKind) {
      'movie' => 'Movie',
      'tv' => 'Series',
      null => parsed.kind == 'Série' ? 'Series' : null,
      _ => '',
    };
    if (type == '') return null; // musique, jeu…
    return _byTitle(
        {?r.title, ?r.originalTitle, parsed.title}, type, r.year ?? parsed.year);
  }
}

final jellyfinLibraryProvider = FutureProvider<JellyfinLibrary?>((ref) async {
  final client = ref.watch(jellyfinProvider);
  if (client == null) return null;
  final timer = Timer(const Duration(minutes: 15), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return client.library();
});

/// Le titre dans Jellyfin, ou null (absent, ou Jellyfin non configuré).
final jellyfinItemProvider = Provider.autoDispose
    .family<AsyncValue<JellyfinItem?>, TmdbTitle>((ref, t) =>
        ref.watch(jellyfinLibraryProvider).whenData((l) => l?.find(t)));
