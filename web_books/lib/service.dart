import 'dart:async';
import 'dart:io';

import 'package:c411_core/book_name.dart';

import 'content.dart';
import 'inspect.dart';
import 'library.dart';
import 'online.dart';

/// La bibliothèque vivante : les livres que l'application a relevés pendant
/// son parcours (relus quand sa base change), lus un par un (métadonnées
/// des EPUB et des BD), puis complétés par une fiche en ligne.
class BooksService {
  BooksService({
    required this.appLibrary,
    required this.statePath,
    required this.content,
    required this.online,
    this.checkEvery = const Duration(seconds: 30),
    this.busyPause = const Duration(minutes: 1),
  })  : _state = BookState.read(statePath),
        covers = Covers(content) {
    _catalog = Catalog.of(const [], _state);
  }

  final String appLibrary;
  final String statePath;
  final Content content;
  final OnlineBooks online;
  final Covers covers;
  final Duration checkEvery;

  /// Pause quand un service en ligne reste saturé.
  final Duration busyPause;

  final BookState _state;
  List<BookFile> _files = const [];
  DateTime? _scannedAt;
  late Catalog _catalog;
  DateTime? _modified;
  Timer? _timer;

  bool working = false;

  /// Étape en cours (« Lecture 3/40 : … », « Open Library 2/12 : … »).
  String? step;
  String? error;

  Catalog get catalog => _catalog;
  BookState get state => _state;

  void start() {
    refresh();
    _timer = Timer.periodic(checkEvery, (_) => refresh());
  }

  /// Relit la base de l'application si elle a changé, puis complète les
  /// nouveaux livres. Vrai si elle a changé.
  bool refresh() {
    final file = File(appLibrary);
    final modified = file.existsSync() ? file.lastModifiedSync() : null;
    if (modified == null || modified == _modified) return false;
    try {
      final app = BookState.parseApp(file.readAsStringSync());
      _modified = modified;
      _files = app.files;
      _scannedAt = app.scannedAt;
      _catalog = Catalog.of(_files, _state);
      error = null;
    } on Object catch (e) {
      // Fichier en cours d'écriture : relu à la prochaine vérification.
      error = 'Base de l’application illisible : $e';
      return false;
    }
    unawaited(work());
    return true;
  }

  Map<String, Object?> status() => {
        'working': working,
        'step': step,
        'error': error,
        'scannedAt': _scannedAt?.toIso8601String(),
        'books': _catalog.books.length,
        'online': _catalog.books.where((b) => b.info.online != null).length,
        'google': online.googleKey.isNotEmpty,
      };

  void _save() {
    _catalog = Catalog.of(_files, _state);
    try {
      _state.write(statePath);
    } on FileSystemException catch (e) {
      error = 'Bibliothèque non enregistrée : ${e.message}';
    }
  }

  /// Lit les métadonnées des EPUB et des CBZ pas encore lus, puis cherche
  /// en ligne les livres qui n'ont pas de fiche.
  Future<void> work() async {
    if (working) return;
    working = true;
    try {
      await _inspect();
      await _identify();
    } finally {
      working = false;
      step = null;
    }
  }

  Future<void> _inspect() async {
    final pending = [for (final f in _files) if (f.isZip && _state.info[f.path]?.inspected == null) f];
    for (final (i, f) in pending.indexed) {
      step = 'Lecture ${i + 1}/${pending.length} : ${f.name}';
      Embedded? embedded;
      try {
        final zip = await content.zip(f);
        embedded = f.format == 'epub' ? await inspectEpub(zip) : await inspectComic(zip);
      } on SocketException catch (e) {
        error = 'FTP injoignable : ${e.message}';
        return; // Repris à la prochaine relecture.
      } on HttpException catch (e) {
        error = 'Lecture impossible : ${e.message}';
        return;
      } on Object {
        embedded = null; // Fichier abîmé : lu, sans métadonnées.
      }
      _state.info[f.path] = (_state.info[f.path] ?? const BookInfo())
          .copyWith(embedded: embedded, inspected: DateTime.now());
      if (i % 10 == 9) _save();
    }
    if (pending.isNotEmpty) _save();
  }

  /// Les livres (pas les BD ni les magazines, absents de ces services)
  /// sans fiche en ligne.
  Future<void> _identify() async {
    final pending = [
      for (final b in _catalog.books)
        if (b.kind == BookKind.book && (_state.info[b.file.path] ?? const BookInfo()).searchStale) b,
    ];
    for (final (i, b) in pending.indexed) {
      step = 'Recherche en ligne ${i + 1}/${pending.length} : ${b.title}';
      final e = b.info.embedded;
      final query = (
        title: e?.title ?? b.guess.title,
        author: (e != null && e.authors.isNotEmpty) ? e.authors.first : b.guess.author,
        isbn: e?.isbn,
        year: e?.year ?? b.guess.year,
      );
      OnlineBook? found;
      Object? failure;
      for (var tries = 0; tries < 3; tries++) {
        try {
          found = await online.find(query);
          failure = null;
          break;
        } on OnlineBusy catch (err) {
          failure = err;
          step = '${err.service} saturé, nouvel essai dans une minute…';
          await Future<void>.delayed(busyPause);
        } on Object catch (err) {
          failure = err;
          break;
        }
      }
      if (failure != null) {
        error = 'Recherche en ligne impossible : $failure';
        break;
      }
      _state.info[b.file.path] = (_state.info[b.file.path] ?? const BookInfo())
          .copyWith(online: () => found, searched: () => DateTime.now());
      if (found != null || i % 10 == 9) _save();
    }
    if (pending.isNotEmpty) _save();
  }

  /// Oublie la fiche en ligne d'un livre et la cherche à nouveau.
  Future<void> reidentify(String id) async {
    final b = _catalog.book(id);
    if (b == null) return;
    _state.info[b.file.path] =
        (_state.info[b.file.path] ?? const BookInfo()).copyWith(online: () => null, searched: () => null);
    _save();
    await work();
  }

  void close() {
    _timer?.cancel();
    online.close();
    content.close();
  }
}
