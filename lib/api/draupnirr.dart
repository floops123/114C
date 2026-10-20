import 'package:dio/dio.dart';

import 'tracker.dart';

/// Client JSON de Draupnirr (draupnirr.xyz). Authentification par clé API
/// (passkey) en paramètre `apikey` **et** en-tête `X-Api-Key` — le tracker
/// accepte les deux, on envoie les deux par sécurité. Limite : 120/min
/// par clé, 300/min par IP.
///
/// Endpoints consommés par l'application :
/// - `/api/me` : compte de l'utilisateur (ratio, crédits, seedtime, H&R)
/// - `/api/me/missions` : missions en cours, progression, récompenses
/// - `/api/me/badges` : tous les badges (obtenus ou non)
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

  Future<Response<Map<String, dynamic>>> _get(String path) async {
    try {
      return await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {'apikey': apiKey},
      );
    } on DioException catch (e) {
      throw TrackerException(
          'Draupnirr injoignable : ${e.message ?? e.type.name}');
    }
  }

  Map<String, dynamic> _expectJson(Response<Map<String, dynamic>> res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const TrackerException('Clé API Draupnirr refusée');
    }
    if (res.statusCode != 200 || res.data == null) {
      throw TrackerException(
          'Réponse Draupnirr inattendue (HTTP ${res.statusCode})');
    }
    return res.data!;
  }

  /// Compte de l'utilisateur connecté.
  Future<DraupnirrAccount> me() async {
    final res = await _get('/api/me');
    return DraupnirrAccount.fromJson(_expectJson(res));
  }

  /// Missions en cours.
  Future<List<DraupnirrMission>> missions() async {
    final res = await _get('/api/me/missions');
    return DraupnirrMissions.parse(_expectJson(res));
  }

  /// Tous les badges.
  Future<List<DraupnirrBadge>> badges() async {
    final res = await _get('/api/me/badges');
    final data = _expectJson(res);
    final entries = data['data'] ?? data['badges'] ?? data;
    if (entries is! List) return const [];
    return entries
        .whereType<Map>()
        .map((e) => DraupnirrBadge.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  void close() => _dio.close();
}

/// Compte de l'utilisateur. Les champs sont tous facultatifs : la réponse
/// JSON peut varier et on ne veut pas crasher si une clé manque.
class DraupnirrAccount {
  const DraupnirrAccount({
    this.username,
    this.ratio,
    this.uploaded,
    this.downloaded,
    this.credits,
    this.seedtimeHours,
    this.hnrCount,
    this.badges = const [],
    this.raw = const {},
  });

  factory DraupnirrAccount.fromJson(Map<String, dynamic> json) {
    num? numOrNull(Object? v) => (v is num) ? v : num.tryParse('$v');
    int? intOrNull(Object? v) {
      final n = numOrNull(v);
      return n?.toInt();
    }
    String? strOrNull(Object? v) => v?.toString();
    final badges = <String>[];
    final raw = json['badges'];
    if (raw is List) {
      for (final b in raw) {
        if (b is String) badges.add(b);
        if (b is Map) badges.add(b['id']?.toString() ?? b['name']?.toString() ?? '');
      }
    }
    return DraupnirrAccount(
      username: strOrNull(json['username'] ?? json['name'] ?? json['user']),
      ratio: numOrNull(json['ratio']),
      uploaded: intOrNull(json['uploaded'] ?? json['uploaded_bytes']),
      downloaded: intOrNull(json['downloaded'] ?? json['downloaded_bytes']),
      credits: intOrNull(json['credits'] ?? json['credit'] ?? json['buffer']),
      seedtimeHours: intOrNull(json['seedtime'] ?? json['seedtime_hours']),
      hnrCount: intOrNull(json['hnr_count'] ?? json['hit_and_runs'] ?? json['warnings']),
      badges: badges.where((b) => b.isNotEmpty).toList(),
      raw: json,
    );
  }

  final String? username;
  final num? ratio;
  final int? uploaded;
  final int? downloaded;
  final int? credits;
  final int? seedtimeHours;
  final int? hnrCount;
  final List<String> badges;
  final Map<String, dynamic> raw;
}

/// Mission en cours.
class DraupnirrMission {
  const DraupnirrMission({
    required this.id,
    this.title = '',
    this.description,
    this.progress,
    this.current,
    this.target,
    this.reward,
  });

  factory DraupnirrMission.fromJson(Map<String, dynamic> json) {
    num? numOrNull(Object? v) => (v is num) ? v : num.tryParse('$v');
    final progress = numOrNull(json['progress']);
    final current = numOrNull(json['current'])?.toInt();
    final target = numOrNull(json['target'])?.toInt();
    return DraupnirrMission(
      id: (json['id'] ?? json['slug'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      progress: progress,
      current: current,
      target: target,
      reward: (json['reward'] is Map)
          ? Map<String, dynamic>.from(json['reward'] as Map).toString()
          : json['reward']?.toString(),
    );
  }

  final String id;
  final String title;
  final String? description;
  final num? progress;

  /// Progression normalisée entre 0 et 1.
  double get fraction {
    if (progress != null) {
      final p = progress!.toDouble();
      return p > 1 ? p / 100 : p.clamp(0, 1);
    }
    if (current != null && target != null && target! > 0) {
      return (current! / target!).clamp(0, 1);
    }
    return 0;
  }

  final int? current;
  final int? target;
  final String? reward;
}

/// Parser de la réponse missions : plusieurs formats selon le tracker.
class DraupnirrMissions {
  static List<DraupnirrMission> parse(Map<String, dynamic> json) {
    final list = json['data'] ?? json['missions'] ?? json;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => DraupnirrMission.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

/// Badge (obtenu ou non).
class DraupnirrBadge {
  const DraupnirrBadge({
    required this.id,
    this.name = '',
    this.description,
    this.imageUrl,
    this.earned = false,
  });

  factory DraupnirrBadge.fromJson(Map<String, dynamic> json) => DraupnirrBadge(
        id: (json['id'] ?? json['slug'] ?? '').toString(),
        name: (json['name'] ?? json['title'] ?? '').toString(),
        description: json['description']?.toString(),
        imageUrl: (json['image'] ?? json['imageUrl'] ?? json['icon'])?.toString(),
        earned: json['earned'] == true ||
            json['obtained'] == true ||
            json['unlocked'] == true ||
            json['has'] == true,
      );

  final String id;
  final String name;
  final String? description;
  final String? imageUrl;
  final bool earned;
}