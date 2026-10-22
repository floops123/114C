import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import 'remote_files.dart';

/// Fichiers du serveur en WebDAV (HTTPS) : `rclone serve webdav`, nginx,
/// Caddy, Nextcloud… [url] est la racine du partage ; les chemins demandés
/// (`/Films/x.mkv`) lui sont ajoutés.
class WebDavConfig implements FilesConfig {
  const WebDavConfig({required this.url, this.user = '', this.password = ''});

  final String url;
  final String user;
  final String password;

  @override
  bool get isEmpty => url.isEmpty;
}

class WebDavException extends RemoteFilesException {
  const WebDavException(super.message);
}

/// Client WebDAV : une seule connexion HTTP gardée ouverte (keep-alive) et
/// réutilisée, plusieurs requêtes à la fois. Lecture par `Range`, listes par
/// `PROPFIND`, envoi par `PUT`, dossiers par `MKCOL`.
class WebDavClient implements RemoteFiles {
  WebDavClient(this.config, {HttpClient? http})
      : _http = http ?? HttpClient() {
    _http
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30)
      // Appbox et autres : certificats souvent auto-signés, comme en FTP.
      ..badCertificateCallback = (_, _, _) => true;
  }

  final WebDavConfig config;
  final HttpClient _http;

  @override
  bool get concurrent => true;

  late final Uri _base = () {
    final u = Uri.parse(config.url.trim());
    return u.path.endsWith('/') ? u : u.replace(path: '${u.path}/');
  }();

  String? get _auth => config.user.isEmpty
      ? null
      : 'Basic ${base64.encode(utf8.encode('${config.user}:${config.password}'))}';

  /// Adresse de [path] (segments encodés) ; [dir] : barre finale.
  Uri uriOf(String path, {bool dir = false}) {
    final segments = [
      ..._base.pathSegments.where((s) => s.isNotEmpty),
      ...path.split('/').where((s) => s.isNotEmpty),
    ];
    final encoded = segments.map(Uri.encodeComponent).join('/');
    return _base.replace(
        path: '/$encoded${dir && segments.isNotEmpty ? '/' : ''}');
  }

  Future<HttpClientResponse> _request(String method, Uri uri,
      {Map<String, String> headers = const {},
      String? body,
      Stream<List<int>>? stream,
      void Function(int sent)? onProgress}) async {
    try {
      final req = await _http.openUrl(method, uri);
      req.followRedirects = method == 'GET';
      if (_auth case final auth?) {
        req.headers.set(HttpHeaders.authorizationHeader, auth);
      }
      headers.forEach(req.headers.set);
      if (body != null) {
        final bytes = utf8.encode(body);
        req.headers.contentType =
            ContentType('application', 'xml', charset: 'utf-8');
        req.contentLength = bytes.length;
        req.add(bytes);
      } else if (stream != null) {
        req.bufferOutput = false;
        var sent = 0;
        await for (final chunk in stream) {
          req.add(chunk);
          sent += chunk.length;
          onProgress?.call(sent);
          await req.flush();
        }
      } else {
        req.contentLength = 0;
      }
      final res = await req.close();
      if (res.statusCode == 401 || res.statusCode == 403) {
        await res.drain<void>();
        throw const WebDavException(
            'Identifiants WebDAV refusés (401/403)');
      }
      return res;
    } on SocketException catch (e) {
      throw WebDavException('Serveur WebDAV injoignable : ${e.message}');
    } on HandshakeException catch (e) {
      throw WebDavException('TLS refusé par le serveur WebDAV : ${e.message}');
    } on TimeoutException {
      throw const WebDavException('Le serveur WebDAV ne répond pas');
    } on HttpException catch (e) {
      throw WebDavException('WebDAV : ${e.message}');
    }
  }

  static const _propfind = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:resourcetype/><d:getcontentlength/>'
      '</d:prop></d:propfind>';

  /// `PROPFIND` : (chemin décodé, dossier, taille) de chaque réponse ; null
  /// si [path] n'existe pas.
  Future<List<(String, bool, int)>?> _propfindAt(String path,
      {required int depth, bool dir = false}) async {
    final res = await _request('PROPFIND', uriOf(path, dir: dir),
        headers: {'Depth': '$depth'}, body: _propfind);
    final text = await utf8.decodeStream(res);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 207) {
      throw WebDavException(
          'PROPFIND refusé : ${res.statusCode} ${res.reasonPhrase}');
    }
    return parseMultistatus(text);
  }

  /// Réponse `207 Multi-Status` → (chemin décodé, dossier, taille). Les
  /// préfixes d'espace de noms varient (`d:`, `D:`, aucun) : on compare les
  /// noms locaux.
  static List<(String, bool, int)> parseMultistatus(String xml) {
    Iterable<XmlElement> all(XmlNode n, String local) =>
        n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);
    return [
      for (final r in all(XmlDocument.parse(xml), 'response'))
        if (all(r, 'href').firstOrNull case final href?)
          (
            Uri.decodeFull(Uri.parse(href.innerText.trim()).path),
            all(r, 'collection').isNotEmpty,
            int.tryParse(all(r, 'getcontentlength').firstOrNull?.innerText.trim() ?? '') ?? 0,
          ),
    ];
  }

  /// Vérifie l'accès à la racine du partage.
  @override
  Future<void> connect() async {
    if (await _propfindAt('/', depth: 0, dir: true) == null) {
      throw WebDavException('Partage WebDAV introuvable : ${config.url}');
    }
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final rows = await _propfindAt(path, depth: 1, dir: true);
    if (rows == null) {
      throw WebDavException('Dossier introuvable : $path');
    }
    String trim(String p) => p.endsWith('/') ? p.substring(0, p.length - 1) : p;
    final self = trim(Uri.decodeFull(uriOf(path, dir: true).path));
    return [
      for (final (href, isDir, size) in rows)
        if (trim(href) != self && trim(href).isNotEmpty)
          RemoteEntry(trim(href).split('/').last, isDir: isDir, size: size),
    ];
  }

  @override
  Future<int?> size(String path) async {
    final rows = await _propfindAt(path, depth: 0);
    if (rows == null || rows.isEmpty || rows.first.$2) return null;
    return rows.first.$3;
  }

  @override
  Future<Stream<List<int>>> read(String path, {int offset = 0}) async {
    final res = await _request('GET', uriOf(path),
        headers: {if (offset > 0) 'Range': 'bytes=$offset-'});
    if (res.statusCode == 404) {
      await res.drain<void>();
      throw WebDavException('Fichier introuvable : $path');
    }
    if (res.statusCode == 206 || (res.statusCode == 200 && offset == 0)) {
      return res;
    }
    if (res.statusCode == 200) return _skip(res, offset); // Range ignoré.
    await res.drain<void>();
    throw WebDavException(
        'Lecture refusée : ${res.statusCode} ${res.reasonPhrase}');
  }

  /// Serveur sans `Range` : on saute les [count] premiers octets.
  static Stream<List<int>> _skip(Stream<List<int>> data, int count) async* {
    var left = count;
    await for (final chunk in data) {
      if (left == 0) {
        yield chunk;
      } else if (chunk.length <= left) {
        left -= chunk.length;
      } else {
        yield chunk.sublist(left);
        left = 0;
      }
    }
  }

  @override
  Future<void> makeDirs(String path) async {
    var current = '';
    for (final part in path.split('/').where((p) => p.isNotEmpty)) {
      current = '$current/$part';
      final res = await _request('MKCOL', uriOf(current, dir: true));
      await res.drain<void>();
      // 201 : créé ; 405 : existe déjà ; 301 : redirigé vers le dossier.
      if (res.statusCode != 201 &&
          res.statusCode != 405 &&
          res.statusCode != 301) {
        throw WebDavException(
            'Création du dossier refusée : ${res.statusCode} ${res.reasonPhrase}');
      }
    }
  }

  @override
  Future<void> write(String path, Stream<List<int>> data,
      {void Function(int sent)? onProgress}) async {
    final res = await _request('PUT', uriOf(path),
        stream: data, onProgress: onProgress);
    await res.drain<void>();
    if (res.statusCode != 200 &&
        res.statusCode != 201 &&
        res.statusCode != 204) {
      throw WebDavException(
          'Envoi refusé : ${res.statusCode} ${res.reasonPhrase}');
    }
  }

  @override
  Future<void> close() async => _http.close(force: true);
}
