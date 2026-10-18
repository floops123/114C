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
    this.runtime,
    this.premiere,
    this.rating,
    this.imageTag,
    this.backdropTag,
    this.genres = const [],
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

  /// Durée, première diffusion, note de la communauté.
  final Duration? runtime;
  final DateTime? premiere;
  final double? rating;

  /// Étiquettes des images (affiche ou vignette ; image de fond), pour
  /// [JellyfinClient.imageUrl] : changent quand l'image change.
  final String? imageTag;
  final String? backdropTag;
  final List<String> genres;

  /// Série : fiche « Series », ou dossier d'une bibliothèque mixte
  /// films/séries (Jellyfin n'y crée pas de fiche, voir
  /// [JellyfinClient.findSeriesFolder]).
  bool get isSeries => type == 'Series' || type == 'Folder';

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
      runtime: switch ((j['RunTimeTicks'] as num?)?.toInt()) {
        final t? when t > 0 => Duration(microseconds: t ~/ 10),
        _ => null,
      },
      premiere: DateTime.tryParse(j['PremiereDate'] as String? ?? ''),
      rating: (j['CommunityRating'] as num?)?.toDouble(),
      imageTag: (j['ImageTags'] as Map?)?['Primary'] as String?,
      backdropTag: switch (j['BackdropImageTags']) {
        final List l when l.isNotEmpty => l.first as String?,
        _ => null,
      },
      genres: (j['Genres'] as List? ?? const []).whereType<String>().toList(),
    );
  }
}

/// Saison d'une série (`/Shows/{id}/Seasons`).
class JellyfinSeason {
  const JellyfinSeason({required this.id, required this.number, required this.name});
  final String id;

  /// 0 : épisodes spéciaux (hors saison).
  final int number;
  final String name;
}

/// Une version (fichier) d'un film ou d'un épisode : Jellyfin regroupe les
/// fichiers d'un même dossier (« Film - 1080p », « Film - 2160p ») en
/// « sources » d'un seul élément.
class JellyfinVersion {
  const JellyfinVersion({
    required this.item,
    required this.sourceId,
    this.name,
    this.path,
    this.container,
    this.size,
    this.width,
    this.height,
    this.videoCodec,
    this.hdr,
    this.audio,
  });

  final JellyfinItem item;
  final String sourceId;
  final String? name;
  final String? path;
  final String? container;
  final int? size;
  final int? width;
  final int? height;
  final String? videoCodec;

  /// « HDR10 », « Dolby Vision »… ; null en SDR.
  final String? hdr;

  /// Piste audio par défaut (« TrueHD Atmos 7.1 · Français »).
  final String? audio;

  /// Résolution d'après la largeur (les films en 2.39:1 font moins de 2160
  /// lignes en « 4K »).
  String? get resolution {
    final w = width;
    if (w == null) return null;
    if (w >= 3200) return '2160p';
    if (w >= 1700) return '1080p';
    if (w >= 1100) return '720p';
    return '${height ?? w}p';
  }

  /// Nom du fichier, sans le dossier.
  String? get fileName => path?.split(RegExp(r'[/\\]')).last;

  factory JellyfinVersion.fromApi(JellyfinItem item, Map<String, dynamic> j) {
    final streams =
        (j['MediaStreams'] as List? ?? const []).whereType<Map<String, dynamic>>();
    final video = streams.where((s) => s['Type'] == 'Video').firstOrNull;
    final audios = streams.where((s) => s['Type'] == 'Audio').toList();
    final audio = audios.where((s) => s['IsDefault'] == true).firstOrNull ??
        audios.firstOrNull;
    final range = video?['VideoRangeType'] as String? ?? video?['VideoRange'] as String?;
    return JellyfinVersion(
      item: item,
      sourceId: j['Id'] as String? ?? item.id,
      name: j['Name'] as String?,
      path: j['Path'] as String?,
      container: j['Container'] as String?,
      size: (j['Size'] as num?)?.toInt(),
      width: (video?['Width'] as num?)?.toInt(),
      height: (video?['Height'] as num?)?.toInt(),
      videoCodec: (video?['Codec'] as String?)?.toUpperCase(),
      hdr: switch (range?.toUpperCase()) {
        null || 'SDR' || 'UNKNOWN' => null,
        final r when r.startsWith('DOVI') => 'Dolby Vision',
        final r => r,
      },
      audio: audio == null
          ? null
          : (audio['DisplayTitle'] as String?) ??
              [audio['Codec'], audio['Language']].nonNulls.join(' · '),
    );
  }
}

/// API Jellyfin : clé d'API créée dans Tableau de bord → Clés API.
class JellyfinClient {
  /// [adapter] : couche réseau de remplacement (tests).
  JellyfinClient(
      {required String url, required this.apiKey, HttpClientAdapter? adapter})
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
        )) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  /// Adresse du serveur, sans « / » final.
  final String base;
  final String apiKey;
  final Dio _dio;

  /// Utilisateur au nom duquel interroger la bibliothèque. Une clé d'API
  /// n'est liée à personne : sans utilisateur, Jellyfin peut renvoyer des
  /// listes vides (épisodes d'une série) et sans état de lecture (vu, reprise).
  /// Premier administrateur actif, sinon premier utilisateur ; null si
  /// `/Users` ne répond pas (on fait alors sans).
  Future<String?> userId() => _user ??= _findUser();
  Future<String?>? _user;
  String? _userName;
  int? _userCount;

  Future<String?> _findUser() async {
    try {
      final res = await _dio.get<Object>('/Users');
      final users = res.statusCode == 200 && res.data is List
          ? (res.data as List).whereType<Map<String, dynamic>>().toList()
          : const <Map<String, dynamic>>[];
      bool active(Map<String, dynamic> u) =>
          (u['Policy'] as Map?)?['IsDisabled'] != true;
      final admin = users.where((u) =>
          active(u) && (u['Policy'] as Map?)?['IsAdministrator'] == true);
      final user = admin.firstOrNull ?? users.where(active).firstOrNull;
      _userName = user?['Name'] as String?;
      _userCount = users.length;
      return user?['Id'] as String?;
    } on DioException {
      return null;
    }
  }

  /// `/Items`, au nom de [userId] quand il est connu.
  Future<List<Map<String, dynamic>>> _items(Map<String, dynamic> query) async {
    final user = await userId();
    final body = await _get('/Items', {...query, 'userId': ?user});
    return (body['Items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

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
  Future<JellyfinLibrary> library() async => JellyfinLibrary([
        for (final i in await _items({
          'IncludeItemTypes': 'Movie,Series',
          'Recursive': true,
          'Fields': 'ProviderIds,ProductionYear,OriginalTitle',
          'EnableImages': false,
        }))
          JellyfinItem.fromApi(i),
      ]);

  /// Épisodes d'une série, dans l'ordre (saison, numéro).
  static const _episodeFields = 'Overview,PremiereDate';

  /// Façons de demander les épisodes d'une série, dans l'ordre d'essai :
  /// selon la version de Jellyfin et le compte, l'une peut revenir vide.
  List<(String, Future<List<Map<String, dynamic>>> Function())> _episodeQueries(
      String seriesId) {
    final common = {
      'Fields': _episodeFields,
      'EnableImageTypes': 'Primary',
      'ImageTypeLimit': 1,
    };
    return [
      // Fichiers sur le disque seulement (IsMissing=false).
      ('/Items, épisodes présents', () => _items({
            ...common,
            'ParentId': seriesId,
            'Recursive': true,
            'IncludeItemTypes': 'Episode',
            'IsMissing': false,
          })),
      ('/Shows/Episodes', () async {
        final user = await userId();
        final body = await _get('/Shows/$seriesId/Episodes',
            {...common, 'userId': ?user, 'IsMissing': false});
        return (body['Items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
      }),
      // Sans le filtre (parfois mal renseigné) : épisodes virtuels écartés ici.
      ('/Items, sans filtre', () async => [
            for (final e in await _items({
              ...common,
              'ParentId': seriesId,
              'Recursive': true,
              'IncludeItemTypes': 'Episode',
            }))
              if (e['LocationType'] != 'Virtual' && e['IsMissing'] != true) e,
          ]),
      // Bibliothèque mixte : simples vidéos rangées dans le dossier de la
      // série (saison et numéro lus dans le nom du fichier).
      ('/Items, vidéos du dossier', () async => [
            for (final e in await _items({
              ...common,
              'Fields': '$_episodeFields,Path',
              'ParentId': seriesId,
              'Recursive': true,
              'IncludeItemTypes': 'Episode,Video,Movie',
            }))
              if (e['LocationType'] != 'Virtual') e,
          ]),
    ];
  }

  static final _sxe = RegExp(r'[Ss](\d{1,2})[ ._-]?[Ee](\d{1,3})|\b(\d{1,2})x(\d{2,3})\b');

  /// Saison et numéro d'une vidéo d'après son nom ou son chemin
  /// (« MobLand.S01E02… », « 1x02 »), pour les vidéos sans fiche d'épisode.
  static Map<String, dynamic> withEpisodeNumbers(Map<String, dynamic> j) {
    if (j['ParentIndexNumber'] != null && j['IndexNumber'] != null) return j;
    final m = _sxe.firstMatch('${j['Name'] ?? ''} ${j['Path'] ?? ''}');
    if (m == null) return j;
    // Titre de l'épisode dans le nom du fichier (« MobLand (2025) - S01E01 -
    // Stick or Twist [MULTi]….mkv ») : la vidéo porte souvent le nom de la série.
    final file = '${j['Path'] ?? ''}'.split('/').last;
    final title = RegExp(r'[Ss]\d{1,2}[Ee]\d{1,3}\s+-\s+([^\[\]]+?)\s*(?:\[|\.[A-Za-z0-9]{2,4}$)')
        .firstMatch(file)?[1];
    return {
      ...j,
      'ParentIndexNumber': int.parse(m[1] ?? m[3]!),
      'IndexNumber': int.parse(m[2] ?? m[4]!),
      'Name': ?title,
    };
  }

  /// Dossier d'une série dans une bibliothèque mixte films/séries : dossier
  /// au nom de la série (« MobLand », « MobLand (2025) ») ou au nom de la
  /// sortie (« MobLand.2025.S01.MULTI.1080p-GRP »), titre français ou
  /// original. null si rien ne correspond. Les autres dossiers de la même
  /// série (une sortie par saison) sont retenus dans [folderSiblings].
  Future<JellyfinItem?> findSeriesFolder(TmdbTitle t) async {
    final wanted = {titleKey(t.title), if (t.originalTitle != null) titleKey(t.originalTitle!)};
    final matches = <JellyfinItem>[];
    final seen = <String>{};
    for (final term in {t.originalTitle ?? t.title, t.title}) {
      final found = await _items({
        'searchTerm': term,
        'Recursive': true,
        'IncludeItemTypes': 'Folder,Series',
        'Fields': 'ProviderIds,ProductionYear,Path',
        'Limit': 50,
      });
      for (final j in found) {
        if (seriesFolderMatches(j['Name'] as String? ?? '', wanted) &&
            seen.add(j['Id'] as String? ?? '')) {
          matches.add(JellyfinItem.fromApi(j));
        }
      }
      if (matches.isNotEmpty) break;
    }
    if (matches.isEmpty) return null;
    for (final m in matches) {
      folderSiblings[m.id] = matches;
    }
    return matches.first;
  }

  /// Dossiers d'une même série trouvés par [findSeriesFolder], par id.
  final folderSiblings = <String, List<JellyfinItem>>{};

  /// Un nom de dossier est-il celui de la série ? « MobLand », « MobLand
  /// (2025) », ou un nom de sortie de série (marqueur S01, S01E01).
  static bool seriesFolderMatches(String name, Set<String> wanted) {
    if (wanted.contains(titleKey(
        name.replaceAll(RegExp(r'\s*[\(\[]\d{4}[\)\]]\s*$'), '')))) {
      return true;
    }
    final release = ReleaseName.parse(name);
    final seriesMark = release.kind == 'Série' ||
        RegExp(r'(^|[ ._-])(S\d{1,2}|Saison[ ._-]?\d{1,2}|Season[ ._-]?\d{1,2}|Integrale|COMPLETE)([ ._-]|$)',
                caseSensitive: false)
            .hasMatch(name);
    return seriesMark && wanted.contains(titleKey(release.title));
  }

  /// Épisodes d'une série présents sur le disque, dans l'ordre (saison,
  /// numéro) : première façon de demander qui en renvoie.
  /// Une erreur n'est remontée que si aucune façon de demander n'a répondu.
  Future<List<JellyfinItem>> episodes(String seriesId) async {
    JellyfinException? failure;
    var answered = false;
    for (final (_, query) in _episodeQueries(seriesId)) {
      try {
        final items = await query();
        answered = true;
        if (items.isEmpty) continue;
        return [for (final i in items) JellyfinItem.fromApi(withEpisodeNumbers(i))]
          ..sort((a, b) {
            final s = (a.season ?? 0).compareTo(b.season ?? 0);
            return s != 0 ? s : (a.episode ?? 0).compareTo(b.episode ?? 0);
          });
      } on JellyfinException catch (e) {
        failure ??= e;
      }
    }
    if (!answered && failure != null) throw failure;
    return const [];
  }

  /// Diagnostic d'une série que la bibliothèque ne reconnaît pas : fiches
  /// trouvées en cherchant [title] dans Jellyfin, puis [diagnoseSeries].
  Future<String> diagnoseTitle(String title) async {
    final out = StringBuffer(
        'Diagnostic Jellyfin — ${DateTime.now().toIso8601String()}\n'
        'Serveur : $base\n');
    final List<Map<String, dynamic>> found;
    try {
      // Tous types confondus : une bibliothèque mixte n'a pas de « Series ».
      found = await _items({
        'searchTerm': title,
        'Recursive': true,
        'Fields': 'ProviderIds,ProductionYear,Path',
        'Limit': 30,
      });
    } on Object catch (e) {
      out.writeln('Recherche « $title » : erreur — $e');
      return out.toString();
    }
    out.writeln('Recherche « $title », tous types : ${found.length} résultat(s)');
    for (final j in found.take(15)) {
      out.writeln('  ${j['Type']} « ${j['Name']} » — Id ${j['Id']}'
          '${j['Path'] == null ? '' : ' — ${j['Path']}'}');
    }
    final folders = [
      for (final j in found)
        if (j['Type'] == 'Series' || j['Type'] == 'Folder') JellyfinItem.fromApi(j),
    ];
    if (folders.isEmpty) {
      out.writeln('Aucune série ni dossier à ce nom : la série n’est pas dans '
          'une bibliothèque Jellyfin (peut-être seulement dans Plex ?).');
      return out.toString();
    }
    out.write((await diagnoseSeries(folders.take(3).toList()))
        .split('\n')
        .skip(2) // en-tête déjà écrit
        .join('\n'));
    return out.toString();
  }

  /// Rapport lisible (sans clé) pour comprendre une série sans épisodes :
  /// utilisateur, fiches de la série, résultat de chaque façon de demander.
  Future<String> diagnoseSeries(List<JellyfinItem> series) async {
    final out = StringBuffer('Diagnostic Jellyfin — ${DateTime.now().toIso8601String()}\n');
    out.writeln('Serveur : $base');
    final user = await userId();
    out.writeln(user == null
        ? 'Utilisateur : aucun (/Users refusé ou vide)'
        : 'Utilisateur : $_userName ($user) parmi $_userCount');
    for (final s in series) {
      out.writeln('\nFiche « ${s.name} » ${s.year ?? ''} — Id ${s.id}, '
          'Type ${s.type}, TMDB ${s.tmdbId ?? '—'}');
      for (final (name, query) in _episodeQueries(s.id)) {
        try {
          final items = await query();
          out.writeln('  $name : ${items.length} épisode(s)');
        } on Object catch (e) {
          out.writeln('  $name : erreur — $e');
        }
      }
      try {
        final children = await _items({'ParentId': s.id});
        final types = <String, int>{};
        for (final c in children) {
          final t = c['Type'] as String? ?? '?';
          types[t] = (types[t] ?? 0) + 1;
        }
        out.writeln('  Contenu direct : ${types.isEmpty ? 'rien' : types.entries.map((e) => '${e.value} ${e.key}').join(', ')}');
      } on Object catch (e) {
        out.writeln('  Contenu direct : erreur — $e');
      }
    }
    return out.toString();
  }

  /// Saisons d'une série, dans l'ordre.
  Future<List<JellyfinSeason>> seasons(String seriesId) async {
    final items = await _items({
      'ParentId': seriesId,
      'IncludeItemTypes': 'Season',
      'EnableImages': false,
    });
    return [
      for (final j in items)
        JellyfinSeason(
          id: j['Id'] as String,
          number: (j['IndexNumber'] as num?)?.toInt() ?? 0,
          name: j['Name'] as String? ?? '',
        ),
    ]..sort((a, b) => a.number.compareTo(b.number));
  }

  /// Fiche d'un élément (résumé, genres, images).
  Future<JellyfinItem?> details(String itemId) async {
    final items = await _items({
      'Ids': itemId,
      'Fields': 'Overview,Genres,PremiereDate',
    });
    return items.isEmpty ? null : JellyfinItem.fromApi(items.first);
  }

  /// Image d'un élément (`Primary` : affiche ou vignette d'épisode ;
  /// `Backdrop` : image de fond), réduite à [maxWidth] par le serveur.
  Uri imageUrl(String itemId,
          {String type = 'Primary', String? tag, int maxWidth = 640}) =>
      Uri.parse('$base/Items/$itemId/Images/$type?maxWidth=$maxWidth'
          '${tag == null ? '' : '&tag=$tag'}&quality=85&api_key=$apiKey');

  /// Flux du fichier d'origine (`static=true`) : aucun transcodage, le
  /// lecteur décode tout lui-même (MKV, HEVC, AV1, HDR, TrueHD, DTS-HD, sous-
  /// titres intégrés…). La clé passe aussi dans l'adresse : mpv la garde pour
  /// les requêtes de déplacement dans le fichier.
  ///
  /// [sourceId] choisit une version précise (plusieurs fichiers pour un même
  /// film) ; sans elle, Jellyfin sert la version par défaut.
  Uri streamUrl(String itemId, {String? sourceId}) =>
      Uri.parse('$base/Videos/$itemId/stream?static=true'
          '${sourceId == null ? '' : '&mediaSourceId=$sourceId'}'
          '&api_key=$apiKey');

  /// Toutes les versions (fichiers) de ces éléments, en une requête.
  Future<List<JellyfinVersion>> versions(List<JellyfinItem> items) async {
    if (items.isEmpty) return const [];
    final found = await _items({
      'Ids': items.map((i) => i.id).join(','),
      'Fields': 'MediaSources,Path',
      'EnableImages': false,
    });
    final byId = {for (final i in items) i.id: i};
    return [
      for (final j in found)
        if (byId[j['Id']] case final item?)
          for (final src in (j['MediaSources'] as List? ?? const [])
              .whereType<Map<String, dynamic>>())
            JellyfinVersion.fromApi(item, src),
    ];
  }

  /// En-têtes d'authentification pour le lecteur.
  Map<String, String> get headers => {'X-Emby-Token': apiKey};

  /// Libère les connexions (réglages changés : un nouveau client le remplace).
  void close() => _dio.close();
}

final jellyfinProvider = Provider<JellyfinClient?>((ref) {
  final s = ref.watch(settingsProvider).value;
  if (s == null || s.jellyfinUrl.isEmpty || s.jellyfinKey.isEmpty) return null;
  final client = JellyfinClient(url: s.jellyfinUrl, apiKey: s.jellyfinKey);
  ref.onDispose(client.close);
  return client;
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

  /// L'élément et ses doublons (même identifiant TMDB, ou même type, titre et
  /// année) : le même film rangé dans plusieurs bibliothèques.
  List<JellyfinItem> versionsOf(JellyfinItem item) {
    final tmdb = item.tmdbId;
    return [
      // Lui-même, même s'il n'est pas dans l'index (dossier de série).
      if (!items.any((i) => i.id == item.id)) item,
      for (final i in items)
        if (i.id == item.id ||
            (i.type == item.type &&
                (tmdb != null && tmdb.isNotEmpty
                    ? i.tmdbId == tmdb
                    : titleKey(i.name) == titleKey(item.name) &&
                        i.year == item.year)))
          i,
    ];
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
final jellyfinItemProvider = FutureProvider.autoDispose
    .family<JellyfinItem?, TmdbTitle>((ref, t) async {
  final library = await ref.watch(jellyfinLibraryProvider.future);
  final found = library?.find(t);
  if (found != null || t.type != TmdbType.tv) return found;
  // Bibliothèque mixte : pas de fiche « Series », on cherche le dossier.
  final client = ref.watch(jellyfinProvider);
  try {
    return await client?.findSeriesFolder(t);
  } on JellyfinException {
    return null;
  }
});

/// Une série : fiche, saisons et épisodes sur le disque.
typedef JellyfinShow = ({
  JellyfinItem series,
  List<JellyfinSeason> seasons,
  List<JellyfinItem> episodes,
});

/// Fiches Jellyfin d'une série : elle-même et ses doublons (même série
/// rangée deux fois, ou fiche vide à côté de celle qui a les fichiers).
List<JellyfinItem> seriesEntries(Ref ref, JellyfinItem series) {
  final entries =
      ref.read(jellyfinLibraryProvider).value?.versionsOf(series) ?? [series];
  // Bibliothèque mixte : un dossier de sortie par saison.
  final siblings = ref.read(jellyfinProvider)?.folderSiblings[series.id] ?? const [];
  final ids = {for (final e in entries) e.id};
  return [...entries, for (final s in siblings) if (ids.add(s.id)) s];
}

final jellyfinShowProvider = FutureProvider.autoDispose
    .family<JellyfinShow, JellyfinItem>((ref, series) async {
  final client = ref.watch(jellyfinProvider);
  if (client == null) throw const JellyfinException('Jellyfin n’est pas configuré');
  final entries = seriesEntries(ref, series);
  final (details, seasons, lists) = await (
    client.details(series.id).then<JellyfinItem?>((d) => d, onError: (_) => null),
    // Les saisons ne servent qu'aux noms : sans elles, on numérote.
    client.seasons(series.id)
        .then<List<JellyfinSeason>>((s) => s, onError: (_) => const <JellyfinSeason>[]),
    // Une fiche en double qui ne répond pas ne masque pas les autres.
    Future.wait([
      for (final e in entries)
        e.id == series.id
            ? client.episodes(e.id)
            : client.episodes(e.id).then<List<JellyfinItem>>((l) => l,
                onError: (_) => const <JellyfinItem>[]),
    ]),
  ).wait;
  // Épisodes de toutes les fiches, sans doublon, dans l'ordre.
  final seen = <String>{};
  final episodes = [
    for (final list in lists)
      for (final e in list)
        if (seen.add(e.id)) e,
  ]..sort((a, b) {
      final s = (a.season ?? 0).compareTo(b.season ?? 0);
      return s != 0 ? s : (a.episode ?? 0).compareTo(b.episode ?? 0);
    });
  return (series: details ?? series, seasons: seasons, episodes: episodes);
});
