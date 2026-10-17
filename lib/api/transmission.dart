import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';

class TransmissionException implements Exception {
  const TransmissionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Vue typée sur un objet torrent renvoyé par `torrent-get`.
/// On garde la map brute pour pouvoir fusionner les mises à jour partielles.
class Torrent {
  const Torrent(this.json);
  final Map<String, dynamic> json;

  int _i(String k) => (json[k] as num?)?.toInt() ?? 0;
  double _d(String k) => (json[k] as num?)?.toDouble() ?? 0;

  int get id => _i('id');
  String get name => json['name'] as String? ?? '';
  String get hash => (json['hashString'] as String? ?? '').toLowerCase();
  int get status => _i('status');
  double get percentDone => _d('percentDone');
  double get recheckProgress => _d('recheckProgress');
  int get rateDownload => _i('rateDownload');
  int get rateUpload => _i('rateUpload');
  int get eta => _i('eta');
  int get totalSize => _i('totalSize');
  int get sizeWhenDone => _i('sizeWhenDone');
  int get leftUntilDone => _i('leftUntilDone');
  double get ratio => _d('uploadRatio');
  int get error => _i('error');
  String get errorString => json['errorString'] as String? ?? '';
  int get addedDate => _i('addedDate');
  int get peersConnected => _i('peersConnected');
  int get peersSendingToUs => _i('peersSendingToUs');
  int get peersGettingFromUs => _i('peersGettingFromUs');

  bool get hasError => error != 0;
  bool get isStopped => status == 0;
  bool get isChecking => status == 1 || status == 2;
  bool get isDownloading => status == 3 || status == 4;
  bool get isSeeding => status == 5 || status == 6;
  bool get isActive => rateDownload > 0 || rateUpload > 0;

  String get statusLabel => switch (status) {
        0 => percentDone >= 1 ? 'Terminé' : 'Arrêté',
        1 => 'Vérification en attente',
        2 => 'Vérification',
        3 => 'En file',
        4 => 'Téléchargement',
        5 => 'En file (partage)',
        6 => 'Partage',
        _ => 'Inconnu',
      };

  Torrent merge(Map<String, dynamic> patch) => Torrent({...json, ...patch});
}

typedef TorrentGetResult = ({
  List<Map<String, dynamic>> torrents,
  List<int> removed,
});

class TransmissionClient {
  TransmissionClient({
    required String url,
    String user = '',
    String password = '',
  })  : url = normalizeUrl(url),
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
          contentType: 'application/json',
          headers: {
            if (user.isNotEmpty)
              'Authorization':
                  'Basic ${base64Encode(utf8.encode('$user:$password'))}',
          },
        ));

  final String url;
  final Dio _dio;
  String? _sessionId;

  /// Champs nécessaires à la liste : on n'en demande pas plus pour rester léger.
  static const listFields = [
    'id', 'name', 'hashString', 'status', 'percentDone', 'recheckProgress',
    'rateDownload', 'rateUpload', 'eta', 'totalSize', 'sizeWhenDone',
    'leftUntilDone', 'uploadRatio', 'error', 'errorString', 'addedDate',
    'peersConnected', 'peersSendingToUs', 'peersGettingFromUs',
  ];

  static const detailFields = [
    ...listFields,
    'downloadDir', 'comment', 'creator', 'dateCreated', 'doneDate',
    'activityDate', 'pieceCount', 'pieceSize', 'haveValid', 'corruptEver',
    'downloadedEver', 'uploadedEver', 'secondsDownloading', 'secondsSeeding',
    'isPrivate', 'files', 'fileStats', 'peers', 'trackerStats',
  ];

  /// `https://hote:9091` → `https://hote:9091/transmission/rpc`
  static String normalizeUrl(String raw) {
    var u = raw.trim();
    if (!u.contains('://')) u = 'http://$u';
    final uri = Uri.parse(u);
    if (uri.path.isEmpty || uri.path == '/') {
      return uri.replace(path: '/transmission/rpc').toString();
    }
    return u;
  }

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    // Transmission répond 409 avec un nouveau jeton anti-CSRF : on rejoue une fois.
    for (var attempt = 0; attempt < 2; attempt++) {
      final Response<String> res;
      try {
        res = await _dio.post<String>(
          url,
          data: jsonEncode({'method': method, 'arguments': arguments}),
          options: Options(headers: {
            if (_sessionId != null) 'X-Transmission-Session-Id': _sessionId,
          }),
        );
      } on DioException catch (e) {
        throw TransmissionException(
            'Serveur injoignable : ${e.message ?? e.type.name}');
      }

      final code = res.statusCode;
      if (code == 409) {
        _sessionId = res.headers.value('X-Transmission-Session-Id');
        continue;
      }
      if (code == 401) {
        throw const TransmissionException('Identifiants refusés (401)');
      }
      if (code == 403) {
        throw const TransmissionException(
            'Accès refusé (403) : vérifie la whitelist RPC du serveur');
      }
      if (code != 200) {
        throw TransmissionException('Réponse inattendue (HTTP $code)');
      }

      final body = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
      if (body['result'] != 'success') {
        throw TransmissionException('Transmission : ${body['result']}');
      }
      return (body['arguments'] as Map?)?.cast<String, dynamic>() ?? {};
    }
    throw const TransmissionException('Jeton de session refusé');
  }

  /// [ids] : null (tous), une liste d'ids, ou `'recently-active'`.
  Future<TorrentGetResult> torrentGet(List<String> fields,
      {Object? ids}) async {
    final args = await call('torrent-get', {
      'fields': fields,
      'ids': ?ids,
    });
    return (
      torrents: (args['torrents'] as List? ?? const [])
          .cast<Map<String, dynamic>>(),
      removed: (args['removed'] as List? ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
    );
  }

  /// Retourne `true` si le torrent a été ajouté, `false` s'il existait déjà.
  Future<bool> addTorrent({Uint8List? metainfo, String? filename}) async {
    final args = await call('torrent-add', {
      if (metainfo != null) 'metainfo': base64Encode(metainfo),
      'filename': ?filename,
    });
    return args.containsKey('torrent-added');
  }

  Future<void> action(String method, List<int> ids) =>
      call(method, {'ids': ids});

  Future<void> remove(List<int> ids, {bool deleteData = false}) =>
      call('torrent-remove', {'ids': ids, 'delete-local-data': deleteData});

  Future<void> setFilesWanted(int id, List<int> files, bool wanted) =>
      call('torrent-set', {
        'ids': [id],
        wanted ? 'files-wanted' : 'files-unwanted': files,
      });

  Future<Map<String, dynamic>> sessionGet() => call('session-get');

  Future<void> sessionSet(Map<String, dynamic> args) =>
      call('session-set', args);

  Future<int?> freeSpace(String path) async {
    final args = await call('free-space', {'path': path});
    return (args['size-bytes'] as num?)?.toInt();
  }
}

final transmissionProvider = Provider<TransmissionClient?>((ref) {
  final s = ref.watch(settingsProvider).value;
  if (s == null || !s.hasTransmission) return null;
  return TransmissionClient(
      url: s.rpcUrl, user: s.rpcUser, password: s.rpcPassword);
});
