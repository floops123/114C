import 'package:dio/dio.dart';

import 'tracker.dart';

/// Client JSON de Draupnirr (draupnirr.xyz). Authentification par clé API
/// (passkey) en paramètre `apikey` **et** en-tête `X-Api-Key` — le tracker
/// accepte les deux, on envoie les deux par sécurité. Limite : 120/min
/// par clé, 300/min par IP.
///
/// Endpoints consommés par l'application :
/// - `/api/me` : compte de l'utilisateur (objet JSON)
/// - `/api/me/missions` : missions en cours (tableau JSON direct)
/// - `/api/me/badges` : tous les badges (tableau JSON direct)
///
/// Le catalogue JSON (`/api/torrents`) et l'endpoint Torznab
/// (`/torznab/api`) ne sont pas utilisés ici : la recherche et le
/// téléchargement passent par `TorznabApi` (voir `lib/api/torznab.dart`).
class DraupnirrApi {
  DraupnirrApi(this.apiKey, {Uri? baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: (baseUrl ?? Uri.parse('https://draupnirr.xyz')).toString(),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (_) => true,
          headers: {
            'X-Api-Key': apiKey,
            'Accept': 'application/json',
          },
        ));

  final String apiKey;
  final Dio _dio;

  Future<Response<dynamic>> _get(String path) async {
    try {
      return await _dio.get<dynamic>(
        path,
        queryParameters: {'apikey': apiKey},
      );
    } on DioException catch (e) {
      throw TrackerException(
          'Draupnirr injoignable : ${e.message ?? e.type.name}');
    }
  }

  dynamic _expectBody(Response<dynamic> res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const TrackerException('Clé API Draupnirr refusée');
    }
    if (res.statusCode != 200 || res.data == null) {
      throw TrackerException(
          'Réponse Draupnirr inattendue (HTTP ${res.statusCode})');
    }
    return res.data;
  }

  /// Compte de l'utilisateur connecté (objet JSON).
  Future<DraupnirrAccount> me() async {
    final body = _expectBody(await _get('/api/me'));
    if (body is! Map<String, dynamic>) {
      throw TrackerException('Réponse /api/me : objet attendu');
    }
    return DraupnirrAccount.fromJson(body);
  }

  /// Missions en cours. La réponse est un tableau JSON direct (`[...]`).
  Future<List<DraupnirrMission>> missions() async {
    final body = _expectBody(await _get('/api/me/missions'));
    return DraupnirrMissions.parse(body);
  }

  /// Tous les badges. La réponse est un tableau JSON direct (`[...]`).
  Future<List<DraupnirrBadge>> badges() async {
    final body = _expectBody(await _get('/api/me/badges'));
    return DraupnirrBadges.parse(body);
  }

  void close() => _dio.close();
}

/// Compte de l'utilisateur. Tous les champs sont facultatifs : on accepte
/// plusieurs alias (par exemple `name` ou `username`) pour absorber les
/// évolutions du site.
class DraupnirrAccount {
  const DraupnirrAccount({
    this.username,
    this.userClass,
    this.ratio,
    this.uploaded,
    this.downloaded,
    this.credits,
    this.buffer,
    this.seedtimeHours,
    this.seedtimeCumulativeHours,
    this.uploadsCount,
    this.hnrCount,
    this.invites,
    this.freeleechGlobal,
    this.sourceTag,
    this.siteUrl,
    this.badges = const [],
    this.raw = const {},
  });

  factory DraupnirrAccount.fromJson(Map<String, dynamic> json) {
    num? numOrNull(Object? v) => (v is num) ? v : num.tryParse('$v');
    int? intOrNull(Object? v) {
      final n = numOrNull(v);
      return n?.toInt();
    }

    bool? boolOrNull(Object? v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v?.toString().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
      return null;
    }

    String? strOrNull(Object? v) => v?.toString();
    final badges = <String>[];
    final raw = json['badges'];
    if (raw is List) {
      for (final b in raw) {
        if (b is String) badges.add(b);
        if (b is Map) {
          badges.add(b['slug']?.toString() ??
              b['id']?.toString() ??
              b['name']?.toString() ??
              '');
        }
      }
    }

    // seedtime : `seedtime_seconds` est en secondes ; on expose des heures.
    final seedtimeSeconds = intOrNull(json['seedtime_seconds'] ?? json['seedtime']);
    final seedtimeCumSeconds = intOrNull(json['seedtime_cumulative_seconds']);

    return DraupnirrAccount(
      username: strOrNull(json['name'] ?? json['username'] ?? json['user']),
      userClass: strOrNull(json['class']),
      ratio: numOrNull(json['ratio'])?.toDouble(),
      uploaded: intOrNull(json['uploaded'] ?? json['uploaded_bytes']),
      downloaded: intOrNull(json['downloaded'] ?? json['downloaded_bytes']),
      // Crédits : le tracker expose `credits` (ce que tu as) et `buffer`
      // (ce que tu peux gagner via les freeleech). On garde les deux.
      credits: intOrNull(json['credits'] ?? json['credit']),
      buffer: intOrNull(
          json['buffer'] ?? json['bonus_upload'] ?? json['bonus']),
      seedtimeHours: seedtimeSeconds == null ? null : seedtimeSeconds ~/ 3600,
      seedtimeCumulativeHours:
          seedtimeCumSeconds == null ? null : seedtimeCumSeconds ~/ 3600,
      uploadsCount: intOrNull(json['uploads_count']),
      hnrCount: intOrNull(json['hnr_count'] ?? json['hit_and_runs'] ?? json['warnings']),
      invites: intOrNull(json['invites']),
      freeleechGlobal: boolOrNull(json['freeleech_global']),
      sourceTag: strOrNull(json['source_tag']),
      siteUrl: strOrNull(json['site_url']),
      badges: badges.where((b) => b.isNotEmpty).toList(),
      raw: json,
    );
  }

  final String? username;

  /// Classe / niveau affiché à côté du pseudo (« nouveau », « veteran »…).
  final String? userClass;
  final double? ratio;
  final int? uploaded;
  final int? downloaded;
  final int? credits;
  final int? buffer;

  /// Seedtime de la session courante, en heures.
  final int? seedtimeHours;

  /// Seedtime cumulé depuis l'inscription, en heures.
  final int? seedtimeCumulativeHours;
  final int? uploadsCount;
  final int? hnrCount;
  final int? invites;
  final bool? freeleechGlobal;
  final String? sourceTag;
  final String? siteUrl;
  final List<String> badges;
  final Map<String, dynamic> raw;
}

/// Période d'une mission (« daily », « weekly », « monthly »).
enum DraupnirrMissionPeriod {
  daily('Quotidien'),
  weekly('Hebdomadaire'),
  monthly('Mensuel'),
  other('Autre');

  const DraupnirrMissionPeriod(this.label);
  final String label;

  static DraupnirrMissionPeriod fromString(String? s) {
    switch (s) {
      case 'daily':
        return daily;
      case 'weekly':
        return weekly;
      case 'monthly':
        return monthly;
      default:
        return other;
    }
  }
}

/// Mission en cours. `progress` est un **compte** (entier) : la fraction
/// vaut `progress / goalValue` clampée à 1. Si `progress` est ≤ 1 sans
/// cible, c'est une fraction directe.
class DraupnirrMission {
  const DraupnirrMission({
    required this.id,
    this.title = '',
    this.description,
    this.progress,
    this.goalValue,
    this.period = DraupnirrMissionPeriod.other,
    this.rewardCredits,
    this.completed = false,
  });

  factory DraupnirrMission.fromJson(Map<String, dynamic> json) {
    num? numOrNull(Object? v) => (v is num) ? v : num.tryParse('$v');
    final progress = numOrNull(json['progress']);
    final goalValue = numOrNull(json['goal_value'])?.toInt();
    final period = DraupnirrMissionPeriod.fromString(
        json['period']?.toString());
    return DraupnirrMission(
      id: (json['code'] ?? json['id'] ?? json['slug'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      progress: progress,
      goalValue: goalValue,
      period: period,
      rewardCredits: numOrNull(json['reward_credits'])?.toInt(),
      completed: json['completed'] == true,
    );
  }

  final String id;
  final String title;
  final String? description;
  final num? progress;
  final int? goalValue;
  final DraupnirrMissionPeriod period;
  final int? rewardCredits;
  final bool completed;

  /// Progression entre 0 et 1. Si on a une cible, `progress` est un
  /// compte (souvent > 1). Sinon, c'est une fraction directe.
  double get fraction {
    if (progress == null) return 0;
    final p = progress!.toDouble();
    if (goalValue != null && goalValue! > 0) {
      return (p / goalValue!).clamp(0, 1);
    }
    // Pas de cible : `progress` est déjà une fraction.
    return p > 1 ? p / 100 : p.clamp(0, 1);
  }
}

/// Parser de la réponse missions : tableau direct, ou `{data[]}`/
/// `{missions[]}` si jamais l'API change.
class DraupnirrMissions {
  static List<DraupnirrMission> parse(Object? body) {
    final List<dynamic> list;
    if (body is List) {
      list = body;
    } else if (body is Map<String, dynamic>) {
      final inner = body['data'] ?? body['missions'] ?? const [];
      list = inner is List ? inner : const [];
    } else {
      return const [];
    }
    return list
        .whereType<Map>()
        .map((e) => DraupnirrMission.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

/// Badge (obtenu ou non).
class DraupnirrBadge {
  const DraupnirrBadge({
    required this.slug,
    this.name = '',
    this.description,
    this.imageUrl,
    this.earned = false,
    this.awardedAt,
  });

  factory DraupnirrBadge.fromJson(Map<String, dynamic> json) => DraupnirrBadge(
        slug: (json['slug'] ?? json['id'] ?? '').toString(),
        name: (json['name'] ?? json['title'] ?? '').toString(),
        description: json['description']?.toString(),
        imageUrl: (json['image'] ?? json['imageUrl'] ?? json['icon'])?.toString(),
        earned: json['earned'] == true ||
            json['obtained'] == true ||
            json['unlocked'] == true ||
            json['has'] == true,
        awardedAt: json['awarded_at'] == null
            ? null
            : DateTime.tryParse(json['awarded_at'].toString()),
      );

  final String slug;
  final String name;
  final String? description;
  final String? imageUrl;
  final bool earned;
  final DateTime? awardedAt;
}

/// Parser de la réponse badges.
class DraupnirrBadges {
  static List<DraupnirrBadge> parse(Object? body) {
    final List<dynamic> list;
    if (body is List) {
      list = body;
    } else if (body is Map<String, dynamic>) {
      final inner = body['data'] ?? body['badges'] ?? const [];
      list = inner is List ? inner : const [];
    } else {
      return const [];
    }
    return list
        .whereType<Map>()
        .map((e) => DraupnirrBadge.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}