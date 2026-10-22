import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'inspect.dart';
import 'library.dart';
import 'online.dart' show OnlineBook;
import 'remote_zip.dart';

/// Outils facultatifs : ffmpeg (couvertures réduites), pdftoppm (couverture
/// d'un PDF), 7z (BD en CBR, CB7, CBT).
class Tools {
  const Tools({this.ffmpeg = false, this.pdftoppm = false, this.sevenZip = false});
  final bool ffmpeg;
  final bool pdftoppm;
  final bool sevenZip;

  static Future<Tools> detect() async {
    Future<bool> has(String command, List<String> args) async {
      try {
        await Process.run(command, args);
        return true;
      } on ProcessException {
        return false;
      }
    }

    return Tools(
      ffmpeg: await has('ffmpeg', ['-version']),
      pdftoppm: await has('pdftoppm', ['-v']),
      sevenZip: await has('7z', ['i']),
    );
  }
}

/// Type d'une image d'après ses premiers octets.
String imageType(List<int> b) {
  bool at(int i, List<int> sig) => b.length >= i + sig.length && List.generate(sig.length, (k) => b[i + k]).join(',') == sig.join(',');
  if (at(0, [0xff, 0xd8])) return 'image/jpeg';
  if (at(0, [0x89, 0x50, 0x4e, 0x47])) return 'image/png';
  if (at(0, [0x47, 0x49, 0x46])) return 'image/gif';
  if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) return 'image/webp';
  if (at(4, [0x66, 0x74, 0x79, 0x70])) return 'image/avif';
  if (at(0, [0x42, 0x4d])) return 'image/bmp';
  return 'application/octet-stream';
}

/// Le contenu des fichiers : archives ZIP lues à distance, copies locales
/// pour ce qui demande le fichier entier (PDF, CBR), pages et couvertures.
class Content {
  Content({
    required this.urlFor,
    required this.cacheDir,
    required this.tools,
    this.cacheBytes = 2 << 30,
    HttpClient? http,
  }) : _http = http ?? HttpClient();

  /// Adresse HTTP (relais FTP, avec `Range`) d'un fichier du FTP.
  final Future<Uri> Function(String path) urlFor;

  /// Dossier des copies locales et des couvertures.
  final String cacheDir;
  final Tools tools;

  /// Place maximale des copies locales (les plus anciennes partent).
  final int cacheBytes;
  final HttpClient _http;
  final _zips = <String, Future<RemoteZip>>{};
  final _downloads = <String, Future<File>>{};
  final _sevenZipPages = <String, Future<List<String>>>{};

  HttpClient get http => _http;

  /// L'archive ZIP (EPUB, CBZ), ouverte une fois.
  Future<RemoteZip> zip(BookFile f) {
    if (_zips.length > 64) _zips.remove(_zips.keys.first);
    return _zips[f.id] ??= _forgetOnError(_zips, f.id, () async {
      final url = await urlFor(f.path);
      return RemoteZip.open(httpRanges(_http, url), f.size);
    }());
  }

  /// [future], retiré de [cache] s'il échoue (réessayé la fois suivante).
  static Future<T> _forgetOnError<T>(Map<String, Future<T>> cache, String key, Future<T> future) {
    // Écoute qui ne laisse aucune erreur sans destinataire.
    unawaited(future.then((_) {}, onError: (Object _) {
      cache.remove(key);
    }));
    return future;
  }

  // ---- Copies locales -------------------------------------------------------

  String _localPath(BookFile f) => '$cacheDir/files/${f.id}.${f.format}';

  /// Copie locale du fichier entier (téléchargée une fois, gardée tant que
  /// la place le permet).
  Future<File> local(BookFile f) {
    final file = File(_localPath(f));
    if (file.existsSync() && file.lengthSync() == f.size) {
      file.setLastAccessedSync(DateTime.now());
      return Future.value(file);
    }
    return _downloads[f.id] ??= () async {
      try {
        file.parent.createSync(recursive: true);
        _evict(f.size);
        final request = await _http.getUrl(await urlFor(f.path));
        final reply = await request.close();
        if (reply.statusCode != 200) {
          await reply.drain<void>();
          throw HttpException('Téléchargement impossible (HTTP ${reply.statusCode})');
        }
        final tmp = File('${file.path}.part');
        await reply.pipe(tmp.openWrite());
        tmp.renameSync(file.path);
        return file;
      } finally {
        unawaited(Future(() => _downloads.remove(f.id)));
      }
    }();
  }

  /// Fait de la place pour [incoming] octets : les copies les moins
  /// récemment lues partent.
  void _evict(int incoming) {
    final dir = Directory('$cacheDir/files');
    if (!dir.existsSync()) return;
    final files = dir.listSync().whereType<File>().where((f) => !f.path.endsWith('.part')).toList()
      ..sort((a, b) => a.lastAccessedSync().compareTo(b.lastAccessedSync()));
    var total = files.fold(0, (n, f) => n + f.lengthSync()) + incoming;
    for (final f in files) {
      if (total <= cacheBytes) break;
      total -= f.lengthSync();
      try {
        f.deleteSync();
      } on FileSystemException {
        // En cours de lecture : partira la prochaine fois.
      }
    }
  }

  // ---- Pages ---------------------------------------------------------------

  /// Pages d'une BD (noms d'entrées, dans l'ordre).
  Future<List<String>> pages(BookFile f) async {
    if (f.format == 'cbz') return comicPages([for (final e in (await zip(f)).entries) e.name]);
    if (!tools.sevenZip) throw const ZipException('7z absent : BD en CBR, CB7 ou CBT illisibles');
    return _sevenZipPages[f.id] ??= _forgetOnError(_sevenZipPages, f.id, () async {
      final file = await local(f);
      final r = await Process.run('7z', ['l', '-slt', '-ba', '--', file.path], stdoutEncoding: utf8);
      if (r.exitCode != 0) throw ZipException('Archive illisible : ${r.stderr}');
      final names = [
        for (final line in const LineSplitter().convert('${r.stdout}'))
          if (line.startsWith('Path = ')) line.substring(7),
      ];
      return comicPages(names);
    }());
  }

  /// La page [n] (de 0) : ses octets et son type.
  Future<(Uint8List, String)> page(BookFile f, int n) async {
    final names = await pages(f);
    if (n < 0 || n >= names.length) throw RangeError.index(n, names);
    final bytes = await entry(f, names[n]);
    return (bytes, imageType(bytes));
  }

  /// Une entrée de l'archive (ZIP à distance, sinon copie locale et 7z).
  Future<Uint8List> entry(BookFile f, String name) async {
    if (f.isZip) {
      final z = await zip(f);
      final e = z.entry(name);
      if (e == null) throw ZipException('Entrée absente : $name');
      return z.read(e);
    }
    final file = await local(f);
    final process = await Process.start('7z', ['e', '-so', '-y', '--', file.path, name]);
    unawaited(process.stderr.drain<void>());
    final b = BytesBuilder(copy: false);
    await for (final chunk in process.stdout) {
      b.add(chunk);
    }
    await process.exitCode;
    final bytes = b.takeBytes();
    if (bytes.isEmpty) throw ZipException('Entrée illisible : $name');
    return bytes;
  }

  // ---- Couvertures ---------------------------------------------------------

  /// Réduite à 600 pixels de large (ffmpeg), si elle est plus grosse.
  Future<Uint8List> thumbnail(Uint8List image) async {
    if (!tools.ffmpeg || image.length < 150 * 1024) return image;
    try {
      final process = await Process.start('ffmpeg', [
        '-hide_banner', '-loglevel', 'error', '-i', 'pipe:0',
        '-vf', "scale='min(600,iw)':-2", '-frames:v', '1',
        '-f', 'image2', '-c:v', 'mjpeg', '-q:v', '4', 'pipe:1',
      ]);
      unawaited(process.stderr.drain<void>());
      final out = BytesBuilder(copy: false);
      final reading = process.stdout.forEach(out.add);
      process.stdin.add(image);
      await process.stdin.close();
      await reading;
      final bytes = out.takeBytes();
      return await process.exitCode == 0 && bytes.isNotEmpty ? bytes : image;
    } on Object {
      return image;
    }
  }

  /// Première page d'un PDF, en JPEG (pdftoppm, sur la copie locale).
  Future<Uint8List?> pdfCover(BookFile f) async {
    if (!tools.pdftoppm) return null;
    final file = await local(f);
    final tmp = Directory.systemTemp.createTempSync('c411_books');
    try {
      final r = await Process.run('pdftoppm',
          ['-f', '1', '-l', '1', '-scale-to', '600', '-jpeg', '-singlefile', file.path, '${tmp.path}/cover']);
      final out = File('${tmp.path}/cover.jpg');
      return r.exitCode == 0 && out.existsSync() ? out.readAsBytesSync() : null;
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  /// Image téléchargée (couverture en ligne) ; null si absente.
  Future<Uint8List?> download(String url) async {
    final request = await _http.getUrl(Uri.parse(url));
    final reply = await request.close();
    if (reply.statusCode != 200) {
      await reply.drain<void>();
      return null;
    }
    final b = BytesBuilder(copy: false);
    await for (final chunk in reply) {
      b.add(chunk);
    }
    final bytes = b.takeBytes();
    // Open Library renvoie une image de 1 pixel quand il n'a rien.
    return bytes.length < 1000 ? null : bytes;
  }

  void close() => _http.close(force: true);
}

/// Couvertures : lues ou fabriquées une fois, gardées sur le disque.
class Covers {
  Covers(this.content);
  final Content content;
  final _pending = <String, Future<File?>>{};

  /// Les fabrications lourdes (PDF, CBR : fichier entier à télécharger)
  /// passent une par une.
  Future<void> _heavy = Future.value();

  String _path(String id) => '${content.cacheDir}/covers/$id.img';

  bool cached(Book b) => File(_path(b.id)).existsSync();

  /// Une couverture peut-elle être obtenue pour [b] ?
  bool available(Book b) {
    if (cached(b)) return true;
    if (b.info.embedded?.cover != null || b.info.online?.coverUrl != null) return true;
    final t = content.tools;
    return switch (b.file.format) {
      'pdf' => t.pdftoppm,
      'cbr' || 'cb7' || 'cbt' => t.sevenZip,
      _ => false,
    };
  }

  /// Le fichier de la couverture, ou null.
  Future<File?> get(Book b) {
    final file = File(_path(b.id));
    if (file.existsSync()) return Future.value(file);
    return _pending[b.id] ??= () async {
      try {
        final bytes = await _make(b);
        if (bytes == null) return null;
        file.parent.createSync(recursive: true);
        File('${file.path}.tmp')
          ..writeAsBytesSync(bytes)
          ..renameSync(file.path);
        return file;
      } on Object {
        return null;
      } finally {
        unawaited(Future.delayed(const Duration(minutes: 5), () => _pending.remove(b.id)));
      }
    }();
  }

  Future<Uint8List?> _make(Book b) async {
    final f = b.file;
    final e = b.info.embedded;
    if (e?.cover != null && f.isZip) {
      return content.thumbnail(await content.entry(f, e!.cover!));
    }
    final OnlineBook? online = b.info.online;
    if (online?.coverUrl != null) {
      final bytes = await content.download(online!.coverUrl!);
      if (bytes != null) return content.thumbnail(bytes);
    }
    // Il faut le fichier entier : à son tour.
    final done = Completer<Uint8List?>();
    _heavy = _heavy.then((_) async {
      try {
        done.complete(switch (f.format) {
          'pdf' => await content.pdfCover(f),
          'cbr' || 'cb7' || 'cbt' when content.tools.sevenZip =>
            await content.thumbnail((await content.page(f, 0)).$1),
          _ => null,
        });
      } on Object catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }
}
