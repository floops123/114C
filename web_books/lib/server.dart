import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'config.dart';
import 'content.dart';
import 'service.dart';

/// Le serveur : l'interface (dossier `public/`), la bibliothèque, et les
/// fichiers lus sur le FTP par le relais HTTP.
///
/// - `GET /api/library` : livres, séries, état ;
/// - `GET /api/status` : l'état seul ;
/// - `POST /api/identify/<livre>` : cherche à nouveau sa fiche en ligne ;
/// - `GET /api/cover/<livre>` : sa couverture (gardée sur le disque) ;
/// - `GET /api/pages/<livre>` : nombre de pages d'une BD ;
/// - `GET /page/<livre>/<n>` : la page n (de 0) ;
/// - `GET /media/<livre>` : le fichier tel quel, avec `Range` (liseuses
///   EPUB et PDF) ; `?download=1` pour l'enregistrer.
class BooksServer {
  BooksServer(
    this.config, {
    required this.service,
    required this.publicDir,
    this.fontsDir,
  });

  final BooksConfig config;
  final BooksService service;
  final String publicDir;

  /// Polices de l'application (`assets/fonts`), servies sous `/fonts/`.
  final String? fontsDir;
  HttpServer? _server;

  Content get _content => service.content;

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'ico': 'image/x-icon',
    'ttf': 'font/ttf',
    'txt': 'text/plain; charset=utf-8',
  };

  static const _bookTypes = {
    'epub': 'application/epub+zip',
    'pdf': 'application/pdf',
    'cbz': 'application/vnd.comicbook+zip',
    'cbr': 'application/vnd.comicbook-rar',
    'mobi': 'application/x-mobipocket-ebook',
    'azw3': 'application/vnd.amazon.ebook',
    'fb2': 'application/x-fictionbook+xml',
    'djvu': 'image/vnd.djvu',
  };

  Future<HttpServer> start() async {
    final server = await HttpServer.bind(config.host, config.port);
    _server = server;
    server.listen((request) => unawaited(_handle(request)));
    return server;
  }

  Future<void> close() async {
    await _server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (!_authorized(request)) {
        response
          ..statusCode = HttpStatus.unauthorized
          ..headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="C411 Books", charset="UTF-8"');
        await response.close();
        return;
      }
      final segments = request.uri.pathSegments;
      final post = request.method == 'POST';
      switch ((segments.firstOrNull ?? '', segments.length, post)) {
        case ('api', 2, false) when segments[1] == 'library':
          service.refresh();
          await _json(response, {
            ...service.catalog.toJson(cover: service.covers.available),
            'status': service.status(),
          });
        case ('api', 2, false) when segments[1] == 'status':
          await _json(response, service.status());
        case ('api', 3, true) when segments[1] == 'identify':
          unawaited(service.reidentify(segments[2]));
          await _json(response, service.status(), status: HttpStatus.accepted);
        case ('api', 3, false) when segments[1] == 'cover':
          await _cover(response, segments[2]);
        case ('api', 3, false) when segments[1] == 'pages':
          await _pages(response, segments[2]);
        case ('page', 3, false):
          await _page(response, segments[1], int.tryParse(segments[2]) ?? -1);
        case ('media', 2, false):
          await _media(request, segments[1]);
        case ('fonts', 2, false) when fontsDir != null:
          await _file(response, fontsDir!, segments[1]);
        case ('vendor', 2, false):
          await _file(response, '$publicDir/vendor', segments[1], cache: true);
        case (_, _, false):
          await _static(response, request.uri.path);
        default:
          response.statusCode = HttpStatus.methodNotAllowed;
          await response.close();
      }
    } on Object catch (e) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.headers.contentType = ContentType.text;
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

  Future<void> _file(HttpResponse response, String dir, String name, {bool cache = false}) async {
    // Pas de remontée hors du dossier.
    if (name.contains('..') || name.contains('/')) return _notFound(response);
    final file = File('$dir/$name');
    if (!file.existsSync()) return _notFound(response);
    final ext = name.split('.').last;
    response.headers.set(HttpHeaders.contentTypeHeader, _types[ext] ?? 'application/octet-stream');
    if (ext == 'ttf' || cache) {
      response.headers.set(HttpHeaders.cacheControlHeader, 'max-age=604800');
    }
    await response.addStream(file.openRead());
    await response.close();
  }

  Future<void> _cover(HttpResponse response, String id) async {
    final book = service.catalog.book(id);
    if (book == null) return _notFound(response);
    final file = await service.covers.get(book);
    if (file == null) return _notFound(response);
    final head = await file.openRead(0, 16).fold<List<int>>([], (a, b) => a..addAll(b));
    response.headers
      ..set(HttpHeaders.contentTypeHeader, imageType(head))
      ..set(HttpHeaders.cacheControlHeader, 'max-age=604800');
    await response.addStream(file.openRead());
    await response.close();
  }

  Future<void> _pages(HttpResponse response, String id) async {
    final book = service.catalog.book(id);
    if (book == null || book.file.reader != 'comic') return _notFound(response);
    try {
      final pages = await _content.pages(book.file);
      await _json(response, {'count': pages.length});
    } on Object catch (e) {
      await _json(response, {'error': 'BD illisible : $e'}, status: HttpStatus.badGateway);
    }
  }

  Future<void> _page(HttpResponse response, String id, int n) async {
    final book = service.catalog.book(id);
    if (book == null || book.file.reader != 'comic') return _notFound(response);
    final Uint8List bytes;
    final String type;
    try {
      (bytes, type) = await _content.page(book.file, n);
    } on RangeError {
      return _notFound(response);
    }
    response.headers
      ..set(HttpHeaders.contentTypeHeader, type)
      ..set(HttpHeaders.cacheControlHeader, 'max-age=604800');
    response.contentLength = bytes.length;
    response.add(bytes);
    await response.close();
  }

  /// Le fichier tel quel : depuis sa copie locale s'il en a une, sinon par
  /// le relais (plages `Range` transmises).
  Future<void> _media(HttpRequest request, String id) async {
    final response = request.response;
    final book = service.catalog.book(id);
    if (book == null) return _notFound(response);
    final f = book.file;
    response.headers.set(HttpHeaders.contentTypeHeader, _bookTypes[f.format] ?? 'application/octet-stream');
    if (request.uri.queryParameters['download'] == '1') {
      final name = f.name.replaceAll('"', "'");
      // Nom ASCII de secours, puis le vrai nom (RFC 6266).
      response.headers.set('content-disposition',
          'attachment; filename="${name.replaceAll(RegExp(r'[^\x20-\x7e]'), '_')}"; '
          "filename*=UTF-8''${Uri.encodeComponent(f.name)}");
    }
    final upstream = await _content.http.openUrl(request.method, await _content.urlFor(f.path));
    if (request.headers.value(HttpHeaders.rangeHeader) case final range?) {
      upstream.headers.set(HttpHeaders.rangeHeader, range);
    }
    final reply = await upstream.close();
    response.statusCode = reply.statusCode;
    for (final name in [HttpHeaders.contentRangeHeader, HttpHeaders.acceptRangesHeader]) {
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
}
