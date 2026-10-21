import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:c411_core/media_relay.dart';

import 'config.dart';
import 'library.dart';
import 'service.dart';

/// Type MIME qu'un navigateur peut lire tel quel, par extension ; null : à
/// convertir (WMA, APE, WavPack, AIFF, DSD…).
const browserTypes = {
  'mp3': 'audio/mpeg',
  'flac': 'audio/flac',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'ogg': 'audio/ogg',
  'oga': 'audio/ogg',
  'opus': 'audio/ogg; codecs=opus',
  'wav': 'audio/wav',
};

/// Le serveur : l'interface (dossier `public/`), la discothèque, et les
/// fichiers lus sur le FTP par le relais HTTP, tels quels ou convertis à
/// la volée en AAC par ffmpeg.
///
/// - `GET /api/library` : albums, artistes, état de l'identification ;
/// - `GET /api/status` : l'état de l'identification seul ;
/// - `POST /api/identify/<album>` : cherche à nouveau sa fiche MusicBrainz ;
/// - `GET /api/cover/<album>` : sa pochette (Cover Art Archive), gardée sur
///   le disque à côté de la discothèque ;
/// - `GET /api/play/<piste>` : comment la lire (directement ou convertie) ;
/// - `GET /media/<piste>` : le fichier tel quel, avec `Range` ;
/// - `GET /stream/<piste>?t=<secondes>` : AAC converti à la volée.
class MusicServer {
  MusicServer(
    this.config, {
    required this.service,
    required this.relay,
    required this.publicDir,
    this.fontsDir,
    this.ffmpeg = 'ffmpeg',
    this.ffprobe = 'ffprobe',
    this.canTranscode = true,
    HttpClient? http,
  }) : _http = http ?? HttpClient();

  final MusicConfig config;
  final MusicService service;
  final MediaRelay relay;
  final String publicDir;

  /// Polices de l'application (`assets/fonts`), servies sous `/fonts/`.
  final String? fontsDir;
  final String ffmpeg;
  final String ffprobe;

  /// ffmpeg et ffprobe sont installés.
  final bool canTranscode;
  final HttpClient _http;
  final _durations = <String, Future<double?>>{};
  final _covers = <String, Future<File?>>{};
  HttpServer? _server;

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
              'Basic realm="C411 Music", charset="UTF-8"');
        await response.close();
        return;
      }
      final segments = request.uri.pathSegments;
      final post = request.method == 'POST';
      switch ((segments.firstOrNull ?? '', segments.length, post)) {
        case ('api', 2, false) when segments[1] == 'library':
          service.refresh();
          await _json(response, {...service.catalog.toJson(), 'status': service.status()});
        case ('api', 2, false) when segments[1] == 'status':
          await _json(response, service.status());
        case ('api', 3, true) when segments[1] == 'identify':
          unawaited(service.reidentify(segments[2]));
          await _json(response, service.status(), status: HttpStatus.accepted);
        case ('api', 3, false) when segments[1] == 'cover':
          await _cover(response, segments[2]);
        case ('api', 3, false) when segments[1] == 'play':
          await _play(response, segments[2]);
        case ('media', >= 2, false):
          await _media(request, segments[1]);
        case ('stream', >= 2, false):
          await _stream(request, segments[1]);
        case ('fonts', 2, false) when fontsDir != null:
          await _file(response, fontsDir!, segments[1]);
        case (_, _, false):
          await _static(response, request.uri.path);
        default:
          response.statusCode = HttpStatus.methodNotAllowed;
          await response.close();
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
      _file(response, publicDir, path == '/' || path.isEmpty ? 'index.html' : path.substring(1));

  Future<void> _file(HttpResponse response, String dir, String name) async {
    // Pas de remontée hors du dossier.
    if (name.contains('..') || name.contains('/')) return _notFound(response);
    final file = File('$dir/$name');
    if (!file.existsSync()) return _notFound(response);
    final ext = name.split('.').last;
    response.headers.set(HttpHeaders.contentTypeHeader, _types[ext] ?? 'application/octet-stream');
    if (ext == 'ttf') {
      response.headers.set(HttpHeaders.cacheControlHeader, 'max-age=604800');
    }
    await response.addStream(file.openRead());
    await response.close();
  }

  /// Fichier de la pochette [url] dans le cache, à côté de [statePath].
  static String coverPath(String statePath, String url) =>
      '${File(statePath).parent.path}/covers/${fileId(url)}.jpg';

  /// Pochette : lue une fois sur la Cover Art Archive, puis servie depuis le
  /// disque ; 404 sans fiche ou sans pochette.
  Future<void> _cover(HttpResponse response, String id) async {
    final url = service.catalog.album(id)?.release?.coverUrl;
    if (url == null) return _notFound(response);
    final file = await (_covers[url] ??= _fetchCover(url, coverPath(service.statePath, url)));
    if (file == null) return _notFound(response);
    response.headers
      ..contentType = ContentType('image', 'jpeg')
      ..set(HttpHeaders.cacheControlHeader, 'max-age=604800');
    await response.addStream(file.openRead());
    await response.close();
  }

  Future<File?> _fetchCover(String url, String path) async {
    final file = File(path);
    if (file.existsSync()) return file;
    try {
      // La Cover Art Archive redirige vers archive.org : suivi par HttpClient.
      final request = await _http.getUrl(Uri.parse(url));
      final reply = await request.close();
      if (reply.statusCode != 200) {
        await reply.drain<void>();
        return null; // Pas de pochette : on ne redemande pas avant redémarrage.
      }
      final bytes = await reply.fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d));
      file.parent.createSync(recursive: true);
      final tmp = File('$path.tmp')..writeAsBytesSync(bytes.takeBytes());
      tmp.renameSync(path);
      return file;
    } on Object {
      _covers.remove(url); // Réseau : réessayé la fois suivante.
      return null;
    }
  }

  Future<void> _play(HttpResponse response, String id) async {
    final catalog = service.catalog;
    final file = catalog.file(id);
    if (file == null) return _notFound(response);
    final type = browserTypes[file.format];
    // Durée : celle de MusicBrainz, sinon ffprobe (utile pour la conversion,
    // où le navigateur ne la connaît pas).
    double? duration;
    for (final a in catalog.albums) {
      for (final t in a.tracks) {
        if (t.file.id == id && t.mb?.length != null) duration = t.mb!.length! / 1000;
      }
    }
    if (duration == null && canTranscode) duration = await _duration(id, file.path);
    await _json(response, {
      'type': type,
      'directUrl': '/media/$id',
      'streamUrl': canTranscode ? '/stream/$id' : null,
      'duration': duration,
    });
  }

  Future<double?> _duration(String id, String path) => _durations[id] ??= () async {
        try {
          final url = await relay.urlFor(path);
          final r = await Process.run(ffprobe, [
            '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=nw=1:nk=1',
            url.toString(),
          ]).timeout(const Duration(seconds: 30));
          return double.tryParse('${r.stdout}'.trim());
        } on Object {
          _durations.remove(id);
          return null;
        }
      }();

  /// Le fichier tel quel, par le relais (plages `Range` transmises).
  Future<void> _media(HttpRequest request, String id) async {
    final response = request.response;
    final file = service.catalog.file(id);
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
    response.headers.set(HttpHeaders.cacheControlHeader, 'max-age=3600');
    try {
      await response.addStream(reply);
    } finally {
      await response.close();
    }
  }

  /// Arguments ffmpeg : de [start] secondes, en AAC (ADTS), que tous les
  /// navigateurs lisent.
  static List<String> ffmpegArgs(String url, {double start = 0}) => [
        '-hide_banner', '-loglevel', 'error',
        if (start > 0) ...['-ss', start.toStringAsFixed(2)],
        '-i', url,
        '-vn', '-map', '0:a:0',
        '-c:a', 'aac', '-b:a', '256k', '-ac', '2',
        '-f', 'adts', 'pipe:1',
      ];

  Future<void> _stream(HttpRequest request, String id) async {
    final response = request.response;
    final file = service.catalog.file(id);
    if (file == null || !canTranscode) return _notFound(response);
    final start = double.tryParse(request.uri.queryParameters['t'] ?? '') ?? 0;
    final url = await relay.urlFor(file.path);
    final process = await Process.start(ffmpeg, ffmpegArgs(url.toString(), start: start));
    unawaited(process.stderr.drain<void>());
    response.headers
      ..contentType = ContentType('audio', 'aac')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    try {
      await response.addStream(process.stdout);
    } on Object {
      // Le navigateur a coupé (avance rapide, piste suivante).
    } finally {
      process.kill();
      try {
        await response.close();
      } on Object {
        // Déjà fermée.
      }
    }
  }
}
