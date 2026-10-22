import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Serveur WebDAV en mémoire, sur 127.0.0.1 : PROPFIND (profondeur 0 ou
/// 1), GET avec Range, MKCOL, PUT, authentification Basic. [prefix] : le
/// partage n'est pas à la racine du site.
class FakeWebDav {
  FakeWebDav._(this._server, this.files, this.prefix, this.user, this.password);

  static Future<FakeWebDav> start(Map<String, List<int>> files,
      {String prefix = '/dav', String user = 'moi', String password = 'secret'}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dav = FakeWebDav._(server, {...files}, prefix, user, password);
    server.listen((r) => unawaited(dav._serve(r)));
    return dav;
  }

  final HttpServer _server;
  final Map<String, List<int>> files;
  final dirs = <String>{};
  final String prefix;
  final String user;
  final String password;

  /// Requêtes reçues (méthode et chemin) ; ports clients vus (connexions).
  final requests = <String>[];
  final clientPorts = <int>{};

  int get port => _server.port;
  String get url => 'http://127.0.0.1:$port$prefix/';

  Future<void> close() => _server.close(force: true);

  bool _isDir(String p) =>
      p == '/' || dirs.contains(p) || files.keys.any((f) => f.startsWith('$p/'));

  Future<void> _serve(HttpRequest r) async {
    clientPorts.add(r.connectionInfo!.remotePort);
    final res = r.response;
    final auth = 'Basic ${base64.encode(utf8.encode('$user:$password'))}';
    if (r.headers.value(HttpHeaders.authorizationHeader) != auth) {
      res.statusCode = 401;
      return res.close();
    }
    var path = Uri.decodeFull(r.uri.path);
    if (!path.startsWith(prefix)) {
      res.statusCode = 404;
      return res.close();
    }
    path = path.substring(prefix.length);
    if (path.length > 1 && path.endsWith('/')) path = path.substring(0, path.length - 1);
    if (path.isEmpty) path = '/';
    requests.add('${r.method} $path');
    switch (r.method) {
      case 'PROPFIND':
        await r.drain<void>();
        if (!files.containsKey(path) && !_isDir(path)) {
          res.statusCode = 404;
          return res.close();
        }
        final depth = r.headers.value('Depth') ?? '1';
        final entries = <String>[path];
        if (depth != '0' && _isDir(path)) {
          final base = path == '/' ? '' : path;
          final children = <String>{
            for (final p in [...files.keys, ...dirs])
              if (p.startsWith('$base/') && p != path)
                '$base/${p.substring(base.length + 1).split('/').first}',
          };
          entries.addAll(children);
        }
        String href(String p) => Uri.encodeFull('$prefix$p${_isDir(p) && p != '/' ? '/' : ''}');
        res
          ..statusCode = 207
          ..headers.contentType = ContentType('application', 'xml', charset: 'utf-8')
          ..write('<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">');
        for (final p in entries) {
          final dir = _isDir(p);
          res.write('<D:response><D:href>${href(p)}</D:href><D:propstat><D:prop>'
              '<D:resourcetype>${dir ? '<D:collection/>' : ''}</D:resourcetype>'
              '${dir ? '' : '<D:getcontentlength>${files[p]!.length}</D:getcontentlength>'}'
              '</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>');
        }
        res.write('</D:multistatus>');
        return res.close();
      case 'GET':
        final data = files[path];
        if (data == null) {
          res.statusCode = 404;
          return res.close();
        }
        final m = RegExp(r'bytes=(\d+)-').firstMatch(r.headers.value('Range') ?? '');
        final start = m == null ? 0 : int.parse(m[1]!);
        res
          ..statusCode = m == null ? 200 : 206
          ..contentLength = data.length - start;
        if (m != null) {
          res.headers.set('Content-Range', 'bytes $start-${data.length - 1}/${data.length}');
        }
        res.add(data.sublist(start));
        return res.close();
      case 'MKCOL':
        res.statusCode = _isDir(path) ? 405 : 201;
        dirs.add(path);
        return res.close();
      case 'PUT':
        final bytes = <int>[];
        await for (final chunk in r) {
          bytes.addAll(chunk);
        }
        files[path] = bytes;
        res.statusCode = 201;
        return res.close();
    }
    res.statusCode = 405;
    return res.close();
  }
}
