import 'dart:convert';
import 'dart:io';

import 'package:c411_core/book_name.dart';
import 'package:c411_core/music_name.dart' show extensionOf;
import 'package:c411_core/titles.dart';

import 'inspect.dart';
import 'online.dart';

/// Un livre numérique du serveur, chemin FTP.
class BookFile {
  BookFile({required this.path, required this.size, this.hash, this.added});

  factory BookFile.fromJson(Map<String, dynamic> json) => BookFile(
        path: json['path'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
        hash: json['hash'] as String?,
        added: DateTime.tryParse(json['added'] as String? ?? ''),
      );

  final String path;
  final int size;
  final String? hash;
  final DateTime? added;

  late final String id = fileId(path);
  late final BookGuess guess = BookGuess.parse(path);
  String get name => path.split('/').last;
  String get format => extensionOf(path);

  /// Archive ZIP lisible à distance (métadonnées, couverture, pages).
  bool get isZip => const {'epub', 'cbz'}.contains(format);

  /// Comment le lire dans le navigateur ; null : à télécharger.
  String? get reader => switch (format) {
        'epub' => 'epub',
        'pdf' => 'pdf',
        'cbz' || 'cbr' || 'cb7' || 'cbt' => 'comic',
        _ => null,
      };
}

/// Ce qu'on sait d'un fichier en plus de son nom : ses métadonnées (lues
/// une fois), sa fiche en ligne (cherchée une fois, refaite au bout d'une
/// semaine si rien).
class BookInfo {
  const BookInfo({this.embedded, this.inspected, this.online, this.searched});

  factory BookInfo.fromJson(Map<String, dynamic> j) => BookInfo(
        embedded: j['embedded'] == null
            ? null
            : Embedded.fromJson((j['embedded'] as Map).cast<String, dynamic>()),
        inspected: DateTime.tryParse(j['inspected'] as String? ?? ''),
        online: j['online'] == null ? null : OnlineBook.fromJson((j['online'] as Map).cast<String, dynamic>()),
        searched: DateTime.tryParse(j['searched'] as String? ?? ''),
      );

  final Embedded? embedded;

  /// Lu (avec ou sans succès) : on ne relit pas.
  final DateTime? inspected;
  final OnlineBook? online;
  final DateTime? searched;

  bool get searchStale =>
      searched == null || (online == null && DateTime.now().difference(searched!).inDays >= 7);

  BookInfo copyWith({Embedded? embedded, DateTime? inspected, OnlineBook? Function()? online, DateTime? Function()? searched}) =>
      BookInfo(
        embedded: embedded ?? this.embedded,
        inspected: inspected ?? this.inspected,
        online: online != null ? online() : this.online,
        searched: searched != null ? searched() : this.searched,
      );

  Map<String, dynamic> toJson() => {
        'embedded': ?embedded?.toJson(),
        'inspected': ?inspected?.toIso8601String(),
        'online': ?online?.toJson(),
        'searched': ?searched?.toIso8601String(),
      };
}

/// Un livre de la bibliothèque : le fichier, et tout ce qu'on en sait, du
/// plus sûr au moins sûr (le fichier lui-même, la fiche en ligne, le nom).
class Book {
  Book(this.file, this.info);
  final BookFile file;
  final BookInfo info;

  BookGuess get guess => file.guess;
  Embedded? get _e => info.embedded;
  OnlineBook? get _o => info.online;

  String get id => file.id;
  BookKind get kind => guess.kind;

  String get title {
    final e = _e?.title;
    if (e != null && e.trim().isNotEmpty) return e.trim();
    // Une BD sans ComicInfo : le nom (« Astérix T1 ») dit mieux qu'Open Library.
    if (kind == BookKind.book && _o != null) return _o!.title;
    return guess.title;
  }

  List<String> get authors {
    if (_e != null && _e!.authors.isNotEmpty) return _e!.authors;
    if (_o != null && _o!.authors.isNotEmpty) return _o!.authors;
    return [?guess.author];
  }

  String? get series => _e?.series ?? guess.series;
  double? get volume => _e?.volume ?? guess.volume;
  String? get description => _e?.description ?? _o?.description;
  String? get publisher => _e?.publisher ?? _o?.publisher;
  List<String> get subjects => _e != null && _e!.subjects.isNotEmpty ? _e!.subjects : (_o?.subjects ?? const []);

  /// Date de parution : celle d'un magazine vient de son nom (le fichier ne
  /// la dit pas), celle d'un livre de ses métadonnées.
  String? get date {
    if (kind == BookKind.magazine && guess.year != null) {
      return [
        '${guess.year}',
        if (guess.month != null) guess.month.toString().padLeft(2, '0'),
        if (guess.month != null && guess.day != null) guess.day.toString().padLeft(2, '0'),
      ].join('-');
    }
    return _e?.date ?? (_o?.year ?? guess.year)?.toString();
  }

  int? get year => date == null || date!.length < 4 ? null : int.tryParse(date!.substring(0, 4));

  /// Regroupement : série d'une BD, d'un manga, d'un livre, titre d'un magazine.
  String? get groupKey {
    final s = series;
    if (s == null || s.trim().isEmpty) return null;
    return '${kind.name}:${titleKey(s)}';
  }

  Map<String, Object?> toJson({required bool cover}) => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'authors': authors,
        'series': series,
        'volume': volume,
        'issue': guess.issue,
        'date': date,
        'year': year,
        'publisher': publisher,
        'description': description,
        'subjects': subjects,
        'language': _e?.language,
        'pages': _e?.pages,
        // Sens de lecture proposé : de droite à gauche pour un manga.
        'rtl': _e?.rightToLeft == true || kind == BookKind.manga,
        'format': file.format,
        'size': file.size,
        'reader': file.reader,
        'cover': cover,
        'added': file.added?.toIso8601String(),
        'link': _o?.url,
        'source': _o?.source,
      };
}

/// Ce que le serveur garde de son côté : les infos par chemin.
class BookState {
  BookState([Map<String, BookInfo>? info]) : info = info ?? {};
  final Map<String, BookInfo> info;

  static BookState read(String path) {
    final file = File(path);
    if (!file.existsSync()) return BookState();
    try {
      final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return BookState({
        for (final MapEntry(:key, :value) in ((j['books'] as Map?) ?? const {}).entries)
          if (value is Map) '$key': BookInfo.fromJson(value.cast<String, dynamic>()),
      });
    } on Object {
      return BookState(); // Illisible : tout sera relu.
    }
  }

  void write(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(jsonEncode({
      'books': {for (final MapEntry(:key, :value) in info.entries) key: value.toJson()},
    }));
    tmp.renameSync(path);
  }

  /// Les livres de la base de l'application : son fichier de préférences
  /// (clé `mediaLibrary`, une chaîne JSON), ou un export de la base seule.
  static ({List<BookFile> files, DateTime? scannedAt}) parseApp(String source) {
    final json = jsonDecode(source);
    if (json is! Map) throw const FormatException('Base de l’application illisible');
    final raw = json['flutter.mediaLibrary'] ?? json['mediaLibrary'];
    final library = raw == null
        ? json
        : raw is String
            ? jsonDecode(raw) as Map
            : raw as Map;
    return (
      files: [
        for (final f in (library['books'] as List? ?? const []).whereType<Map>())
          if (f['path'] is String) BookFile.fromJson(f.cast<String, dynamic>()),
      ],
      scannedAt: DateTime.tryParse(library['scannedAt'] as String? ?? ''),
    );
  }
}

/// La bibliothèque vue par l'interface : livres et séries.
class Catalog {
  Catalog(this.books) : _byId = {for (final b in books) b.id: b};

  final List<Book> books;
  final Map<String, Book> _byId;

  Book? book(String id) => _byId[id];

  static Catalog of(List<BookFile> files, BookState state) => Catalog([
        for (final f in files) Book(f, state.info[f.path] ?? const BookInfo()),
      ]..sort((a, b) => naturalCompare(a.title, b.title)));

  /// [cover] : une couverture est-elle disponible pour ce livre.
  Map<String, Object?> toJson({required bool Function(Book) cover}) {
    final groups = <String, List<Book>>{};
    for (final b in books) {
      if (b.groupKey case final k?) (groups[k] ??= []).add(b);
    }
    int order(Book a, Book b) {
      final v = (a.volume ?? a.guess.issue?.toDouble() ?? 1e9).compareTo(b.volume ?? b.guess.issue?.toDouble() ?? 1e9);
      if (v != 0) return v;
      final d = (a.date ?? '').compareTo(b.date ?? '');
      return d != 0 ? d : naturalCompare(a.title, b.title);
    }

    final series = [
      for (final MapEntry(key: key, value: list) in groups.entries)
        // Un livre seul n'est pas une série ; une BD ou un magazine, si.
        if (list.length > 1 || list.first.kind != BookKind.book)
          {
            'id': fileId('series:$key'),
            'kind': list.first.kind.name,
            'name': list.first.series,
            'books': [for (final b in list..sort(order)) b.id],
          },
    ];
    return {
      'books': [for (final b in books) b.toJson(cover: cover(b))],
      'series': series,
    };
  }
}

/// Identifiant court et stable (FNV-1a 64 bits, en hexadécimal).
String fileId(String text) {
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in utf8.encode(text)) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
