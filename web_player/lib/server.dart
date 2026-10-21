import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:c411_core/media_relay.dart';
import 'config.dart';
import 'library.dart';
import 'transcode.dart';

/// Le serveur : l'interface (dossier `public/`), le catalogue, et les
/// vidéos lues sur le FTP par le relais HTTP de l'application, directement
/// ou converties à la volée par ffmpeg.
///
/// - `GET /api/library` : le catalogue ;
/// - `GET /api/play/<fichier>` : comment le lire (direct ou converti,
///   durée, pistes audio) ;
/// - `GET /media/<fichier>` : le fichier tel quel, avec `Range` ;
/// - `GET /stream/<fichier>?t=<secondes>&audio=<piste>` : MP4 fragmenté ;
/// - `GET /api/art/<movie|tv>/<id TMDB>` : image de fond (clé TMDB requise).
class WebPlayerServer {
  WebPlayerServer(
    this.config, {
    required this.catalog,
    required this.relay,
    required this.publicDir,
    this.fontsDir,
    this.ffmpeg = 'ffmpeg',
    this.ffprobe = 'ffprobe',
    this.canTranscode = true,
    Future<MediaInfo> Function(String url)? probe,
    HttpClient? http,
  })  : _probe = probe ?? ((url) => _ffprobe(url, ffprobe)),
        _http = http ?? HttpClient();

  final WebConfig config;
  final CatalogSource catalog;
  final MediaRelay relay;
  final String publicDir;

  /// Police Inter de l'application (`assets/fonts`), servie sous `/fonts/`.
  final String? fontsDir;
  final String ffmpeg;
  final String ffprobe;

  /// ffmpeg et ffprobe sont installés.
  final bool canTranscode;

  final Future<MediaInfo> Function(String url) _probe;
  final HttpClient _http;
  final _infos = <String, Future<MediaInfo>>{};
  final _backdrops = <String, Future<String?>>{};
  HttpServer? _server;

  static Future<MediaInfo> _ffprobe(String url, String command) =>
      probe(url, ffprobe: command);

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'ico': 'image/x-icon',
    'ttf': 'font/ttf',
  };

  Future<HttpServer> start() async {
    final server = await HttpServer.bind(config.host, config.port);
    _server = server;
    server.listen((request) => unawaited(_handle(request)));
    return server;
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _http.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (!_authorized(request)) {
        response
          ..statusCode = HttpStatus.unauthorized
          ..headers.set(HttpHeaders.wwwAuthenticateHeader,
              'Basic realm="C411", charset="UTF-8"');
        await response.close();
        return;
      }
      final segments = request.uri.pathSegments;
      final route = segments.firstOrNull ?? '';
      switch ((route, segments.length)) {
        case ('api', >= 2) when segments[1] == 'library':
          await _json(response, {
            ...catalog.current.toJson(),
            // Images de fond disponibles (clé TMDB renseignée).
            'art': config.tmdbKey.isNotEmpty,
          });
        case ('api', 3) when segments[1] == 'play':
          await _play(response, segments[2]);
        case ('api', 4) when segments[1] == 'art':
          await _art(response, segments[2], segments[3]);
        case ('media', >= 2):
          await _media(request, segments[1]);
        case ('stream', >= 2):
          await _stream(request, segments[1]);
        case ('fonts', 2) when fontsDir != null:
          await _file(response, fontsDir!, segments[1]);
        default:
          await _static(response, request.uri.path);
      }
    } on Object catch (e) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.write('$e');
      } on StateError {
        // En-têtes déjà partis.
      }
      try {
        await response.close();
      } on Object {
        // Client parti.
      }
    }
  }

  /// Authentification HTTP Basic, quel que soit le nom d'utilisateur.
  bool _authorized(HttpRequest request) {
    if (config.password.isEmpty) return true;
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (!header.startsWith('Basic ')) return false;
    try {
      final decoded = utf8.decode(base64.decode(header.substring(6).trim()));
      final colon = decoded.indexOf(':');
      return colon >= 0 && decoded.substring(colon + 1) == config.password;
    } on FormatException {
      return false;
    }
  }

  Future<void> _json(HttpResponse response, Object? data, {int status = 200}) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..write(jsonEncode(data));
    await response.close();
  }

  Future<void> _notFound(HttpResponse response) async {
    response.statusCode = HttpStatus.notFound;
    await response.close();
  }

  Future<void> _static(HttpResponse response, String path) =>
      _file(response, publicDir,
          path == '/' || path.isEmpty ? 'index.html' : path.substring(1));

  Future<void> _file(HttpResponse response, String dir, String name) async {
    // Pas de remontée hors du dossier.
    if (name.contains('..') || name.contains('/')) return _notFound(response);
    final file = File('$dir/$name');
    if (!file.existsSync()) return _notFound(response);
    final ext = name.split('.').last;
    response.headers.set(HttpHeaders.contentTypeHeader,
        _types[ext] ?? 'application/octet-stream');
    if (ext == 'ttf') {
      response.headers.set(HttpHeaders.cacheControlHeader, 'max-age=604800');
    }
    await response.addStream(file.openRead());
    await response.close();
  }

  Future<MediaInfo> _info(CatalogFile file) async =>
      _infos[file.id] ??= () async {
        final url = await relay.urlFor(file.path);
        return _probe(url.toString());
      }()
        ..catchError((Object _) {
          _infos.remove(file.id); // Réessayé la fois suivante.
          return const MediaInfo(container: '', duration: 0);
        });

  Future<void> _play(HttpResponse response, String id) async {
    final file = catalog.current.file(id);
    if (file == null) return _notFound(response);
    if (!canTranscode) {
      // Sans ffmpeg : lecture directe, le navigateur fera ce qu'il peut.
      return _json(response, {'mode': 'direct', 'url': '/media/$id', 'duration': 0});
    }
    final MediaInfo info;
    try {
      info = await _info(file);
    } on Object catch (e) {
      return _json(response, {'error': 'Fichier illisible : $e'}, status: 502);
    }
    // Le navigateur tranche (il sait ce qu'il lit) : `mode` n'est que l'avis
    // prudent du serveur, pour un client qui ne teste rien.
    await _json(response, {
      'mode': info.direct ? 'direct' : 'stream',
      'url': info.direct ? '/media/$id' : '/stream/$id',
      'directUrl': '/media/$id',
      'streamUrl': '/stream/$id',
      ...info.toJson(),
    });
  }

  /// Le fichier tel quel, par le relais (plages `Range` transmises).
  Future<void> _media(HttpRequest request, String id) async {
    final response = request.response;
    final file = catalog.current.file(id);
    if (file == null) return _notFound(response);
    final upstream = await _http.openUrl(request.method, await relay.urlFor(file.path));
    if (request.headers.value(HttpHeaders.rangeHeader) case final range?) {
      upstream.headers.set(HttpHeaders.rangeHeader, range);
    }
    final reply = await upstream.close();
    response.statusCode = reply.statusCode;
    for (final name in [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
    ]) {
      if (reply.headers.value(name) case final v?) response.headers.set(name, v);
    }
    if (reply.contentLength >= 0) response.contentLength = reply.contentLength;
    try {
      await response.addStream(reply);
    } finally {
      await response.close();
    }
  }

  /// Converti à la volée en MP4 fragmenté, à partir de `t` secondes.
  Future<void> _stream(HttpRequest request, String id) async {
    final response = request.response;
    final file = catalog.current.file(id);
    if (file == null || !canTranscode) return _notFound(response);
    final info = await _info(file);
    final start = double.tryParse(request.uri.queryParameters['t'] ?? '') ?? 0;
    final audio = int.tryParse(request.uri.queryParameters['audio'] ?? '');
    // Le navigateur sait décoder la vidéo : copiée, seul l'audio est converti.
    final copy = request.uri.queryParameters['copy'] == '1';
    final url = await relay.urlFor(file.path);
    final process = await Process.start(
        ffmpeg,
        info.ffmpegArgs(url.toString(),
            start: start, audioIndex: audio, copyVideo: copy));
    unawaited(process.stderr.drain<void>());
    response.headers
      ..contentType = ContentType('video', 'mp4')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    try {
      await response.addStream(process.stdout);
    } on Object {
      // Le navigateur a coupé (avance rapide, fermeture).
    } finally {
      process.kill();
      try {
        await response.close();
      } on Object {
        // Déjà fermée.
      }
    }
  }

  /// Image de fond TMDB (fiche en français), redirigée ; 404 sans clé.
  Future<void> _art(HttpResponse response, String type, String id) async {
    if (config.tmdbKey.isEmpty || !const {'movie', 'tv'}.contains(type) ||
        int.tryParse(id) == null) {
      return _notFound(response);
    }
    final url = await (_backdrops['$type/$id'] ??= _backdrop(type, id));
    if (url == null) return _notFound(response);
    response
      ..statusCode = HttpStatus.found
      ..headers.set(HttpHeaders.locationHeader, url)
      ..headers.set(HttpHeaders.cacheControlHeader, 'max-age=86400');
    await response.close();
  }

  Future<String?> _backdrop(String type, String id) async {
    final key = config.tmdbKey;
    final jwt = key.startsWith('eyJ');
    final uri = Uri.https('api.themoviedb.org', '/3/$type/$id', {
      'language': 'fr-FR',
      'include_image_language': 'fr,null,en',
      if (!jwt) 'api_key': key,
    });
    try {
      final request = await _http.getUrl(uri);
      if (jwt) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      final reply = await request.close();
      final body = await reply.transform(utf8.decoder).join();
      if (reply.statusCode != 200) return null;
      final path = (jsonDecode(body) as Map)['backdrop_path'] as String?;
      return path == null ? null : 'https://image.tmdb.org/t/p/w1280$path';
    } on Object {
      _backdrops.remove('$type/$id');
      return null;
    }
  }
}
