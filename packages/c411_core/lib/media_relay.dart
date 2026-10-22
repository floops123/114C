import 'dart:async';
import 'dart:io';

import 'remote_files.dart';

/// Relais HTTP local (`http://127.0.0.1:<port>/…`) vers les fichiers du
/// serveur : le lecteur (mpv) ne sait pas lire en FTPS ni s'authentifier en
/// WebDAV, mais lit très bien en HTTP avec des requêtes `Range`. En FTP,
/// chaque requête ouvre sa propre connexion et lit à partir de la position
/// demandée (`REST`) ; en WebDAV, un seul client garde sa connexion ouverte
/// et chaque saut n'est qu'une requête `Range`.
class MediaRelay {
  MediaRelay(this.config, {this.connect});
  final FilesConfig config;

  /// Remplace la connexion (tests).
  final Future<RemoteFiles> Function()? connect;

  /// Client partagé, quand le protocole le permet ([RemoteFiles.concurrent]).
  Future<RemoteFiles>? _shared;

  HttpServer? _server;
  Future<HttpServer>? _starting;
  final _paths = <String>[];
  final _sizes = <String, int>{};

  Future<RemoteFiles> _open() async {
    if (connect != null) return connect!();
    final files = openRemoteFiles(config);
    await files.connect();
    return files;
  }

  /// Client pour une requête ; à rendre par [_done].
  Future<RemoteFiles> _client() async {
    if (_shared != null) return _shared!;
    final files = await _open();
    if (files.concurrent) {
      _shared = Future.value(files);
    }
    return files;
  }

  void _done(RemoteFiles? files) {
    if (files == null || files.concurrent) return;
    unawaited(files.close());
  }

  /// Adresse locale du fichier [path] du FTP (le nom du fichier est gardé à
  /// la fin, mpv en déduit le format).
  Future<Uri> urlFor(String path) async {
    final server = await (_starting ??= _start());
    var index = _paths.indexOf(path);
    if (index < 0) {
      _paths.add(path);
      index = _paths.length - 1;
    }
    final name = path.split('/').last;
    return Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        pathSegments: ['$index', name]);
  }

  Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) => unawaited(_serve(request)));
    return server;
  }

  static const _types = {
    'mkv': 'video/x-matroska', 'mp4': 'video/mp4', 'm4v': 'video/mp4',
    'avi': 'video/x-msvideo', 'webm': 'video/webm', 'mov': 'video/quicktime',
    'ts': 'video/mp2t', 'm2ts': 'video/mp2t', 'wmv': 'video/x-ms-wmv',
    'mp3': 'audio/mpeg', 'flac': 'audio/flac', 'm4a': 'audio/mp4',
    'aac': 'audio/aac', 'ogg': 'audio/ogg', 'oga': 'audio/ogg',
    'opus': 'audio/ogg', 'wav': 'audio/wav', 'mka': 'audio/x-matroska',
  };

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    final segments = request.uri.pathSegments;
    final index = segments.isEmpty ? null : int.tryParse(segments.first);
    if (index == null || index >= _paths.length) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final path = _paths[index];
    RemoteFiles? ftp;
    try {
      ftp = await _client();
      final size = _sizes[path] ??= await ftp.size(path) ?? -1;
      if (size < 0) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final range = parseRange(request.headers.value(HttpHeaders.rangeHeader), size);
      final ext = path.split('.').last.toLowerCase();
      response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentType = ContentType.parse(_types[ext] ?? 'application/octet-stream');
      if (range == null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        await response.close();
        return;
      }
      final (start, end) = range;
      final partial = request.headers.value(HttpHeaders.rangeHeader) != null;
      response
        ..statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok
        ..contentLength = end - start + 1;
      if (partial) {
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$size');
      }
      if (request.method == 'HEAD' || start > end) {
        await response.close();
        return;
      }
      final data = await ftp.read(path, offset: start);
      await response.addStream(_take(data, end - start + 1));
      await response.close();
    } on Object {
      // Lecteur parti (avance rapide, fermeture) ou FTP en échec.
      try {
        response.statusCode = HttpStatus.badGateway;
      } on StateError {
        // En-têtes déjà envoyés.
      }
      try {
        await response.close();
      } on Object {
        // Connexion déjà coupée.
      }
    } finally {
      // Connexion propre à cette requête (FTP) : fermée quoi qu'il arrive.
      _done(ftp);
    }
  }

  /// Les [count] premiers octets de [data] ; la lecture est ensuite annulée.
  static Stream<List<int>> _take(Stream<List<int>> data, int count) async* {
    var left = count;
    await for (final chunk in data) {
      if (chunk.length >= left) {
        yield chunk.sublist(0, left);
        return;
      }
      left -= chunk.length;
      yield chunk;
    }
  }

  /// `bytes=a-b`, `bytes=a-`, `bytes=-n` → (début, fin) inclus ; sans en-tête,
  /// tout le fichier ; null si la plage est hors du fichier.
  static (int, int)? parseRange(String? header, int size) {
    if (header == null) return (0, size - 1);
    final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(header);
    if (m == null) return (0, size - 1);
    final a = int.tryParse(m[1]!), b = int.tryParse(m[2]!);
    if (a == null) {
      if (b == null) return (0, size - 1);
      return (size - b < 0 ? 0 : size - b, size - 1);
    }
    if (a >= size) return null;
    return (a, b == null || b >= size ? size - 1 : b);
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    final shared = _shared;
    _shared = null;
    if (shared != null) await (await shared).close();
    _starting = null;
  }
}
