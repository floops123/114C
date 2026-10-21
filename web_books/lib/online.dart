import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:c411_core/titles.dart';

import 'inspect.dart' show plainText;

/// Une fiche trouvée en ligne.
class OnlineBook {
  const OnlineBook({
    required this.source,
    required this.id,
    required this.title,
    this.authors = const [],
    this.year,
    this.description,
    this.subjects = const [],
    this.publisher,
    this.coverUrl,
  });

  factory OnlineBook.fromJson(Map<String, dynamic> j) => OnlineBook(
        source: j['source'] as String? ?? '',
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        authors: (j['authors'] as List? ?? const []).cast<String>(),
        year: (j['year'] as num?)?.toInt(),
        description: j['description'] as String?,
        subjects: (j['subjects'] as List? ?? const []).cast<String>(),
        publisher: j['publisher'] as String?,
        coverUrl: j['coverUrl'] as String?,
      );

  /// `openlibrary` ou `google`.
  final String source;

  /// Œuvre Open Library (`/works/OL…W`) ou volume Google Books.
  final String id;
  final String title;
  final List<String> authors;
  final int? year;
  final String? description;
  final List<String> subjects;
  final String? publisher;
  final String? coverUrl;

  /// Lien vers la fiche, pour l'interface.
  String get url => source == 'google'
      ? 'https://books.google.com/books?id=$id'
      : 'https://openlibrary.org$id';

  Map<String, dynamic> toJson() => {
        'source': source,
        'id': id,
        'title': title,
        if (authors.isNotEmpty) 'authors': authors,
        'year': ?year,
        'description': ?description,
        if (subjects.isNotEmpty) 'subjects': subjects,
        'publisher': ?publisher,
        'coverUrl': ?coverUrl,
      };
}

/// Ce qu'on cherche : titre, auteur s'il est connu, ISBN s'il est connu.
typedef BookQuery = ({String title, String? author, String? isbn, int? year});

/// Le service a refusé (quota, saturation) malgré les nouvelles tentatives.
class OnlineBusy implements Exception {
  const OnlineBusy(this.service);
  final String service;
  @override
  String toString() => '$service saturé, réessaie plus tard';
}

/// File d'appels au rythme d'un service (une requête par [interval]).
class _Paced {
  _Paced(this.interval);
  final Duration interval;
  Future<void> _queue = Future.value();
  DateTime _last = DateTime(2000);

  Future<T> run<T>(Future<T> Function() call) {
    final done = Completer<T>();
    _queue = _queue.then((_) async {
      final wait = interval - DateTime.now().difference(_last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _last = DateTime.now();
      try {
        done.complete(await call());
      } on Object catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }
}

/// Recherche des fiches : Google Books d'abord si une clé est donnée
/// (meilleurs résumés en français), sinon Open Library, sans clé.
class OnlineBooks {
  OnlineBooks({
    required String contact,
    this.googleKey = '',
    HttpClient? http,
    this.openLibrary = 'https://openlibrary.org',
    this.google = 'https://www.googleapis.com/books/v1',
    Duration interval = const Duration(milliseconds: 1100),
  })  : userAgent = 'C411Books/1.0 ( $contact )',
        _http = http ?? HttpClient(),
        _pace = _Paced(interval);

  final String userAgent;
  final String googleKey;
  final String openLibrary;
  final String google;
  final HttpClient _http;
  final _Paced _pace;

  Future<Map<String, dynamic>?> _get(Uri uri) => _pace.run(() async {
        for (var attempt = 0; attempt < 4; attempt++) {
          final request = await _http.getUrl(uri);
          request.headers
            ..set(HttpHeaders.userAgentHeader, userAgent)
            ..set(HttpHeaders.acceptHeader, 'application/json');
          final reply = await request.close();
          final body = await reply.transform(utf8.decoder).join();
          switch (reply.statusCode) {
            case 200:
              return jsonDecode(body) as Map<String, dynamic>;
            case 404:
              return null;
            case 429 || 503:
              await Future<void>.delayed(Duration(seconds: 2 << attempt));
            default:
              throw HttpException('${uri.host} : HTTP ${reply.statusCode}');
          }
        }
        throw OnlineBusy(uri.host);
      });

  /// La fiche qui correspond à [q], ou null.
  Future<OnlineBook?> find(BookQuery q) async {
    if (googleKey.isNotEmpty) {
      final g = await _google(q);
      if (g != null) return g;
    }
    return _openLibrary(q);
  }

  // ---- Open Library --------------------------------------------------------

  Future<OnlineBook?> _openLibrary(BookQuery q) async {
    // ISBN : l'édition exacte, puis son œuvre.
    if (q.isbn != null) {
      final edition = await _get(Uri.parse('$openLibrary/isbn/${q.isbn}.json'));
      final work = ((edition?['works'] as List?)?.firstOrNull as Map?)?['key'] as String?;
      if (edition != null && work != null) {
        final covers = (edition['covers'] as List?)?.whereType<num>().where((c) => c > 0);
        return _work(work,
            title: edition['title'] as String? ?? q.title,
            authors: q.author == null ? const [] : [q.author!],
            year: int.tryParse(RegExp(r'\d{4}').stringMatch('${edition['publish_date'] ?? ''}') ?? ''),
            cover: covers == null || covers.isEmpty ? null : covers.first.toInt(),
            publisher: ((edition['publishers'] as List?)?.firstOrNull) as String?);
      }
    }
    // L'édition française de chaque œuvre (titre et couverture), s'il y en a.
    const fields = 'key,title,author_name,first_publish_year,cover_i,language,subject,publisher,'
        'editions,editions.key,editions.title,editions.cover_i,editions.language';
    Future<List<Map<String, dynamic>>> search(Map<String, String> params) async {
      final json = await _get(Uri.parse('$openLibrary/search.json')
          .replace(queryParameters: {...params, 'limit': '10', 'lang': 'fre', 'fields': fields}));
      return [
        for (final d in (json?['docs'] as List? ?? const []).whereType<Map>()) d.cast<String, dynamic>(),
      ];
    }

    var docs = await search({'title': q.title, 'author': ?q.author});
    var best = pickOpenLibrary(docs, q);
    // Auteur et titre inversés dans le nom du fichier, ou auteur inconnu :
    // recherche libre.
    if (best == null) {
      docs = await search({'q': [q.title, ?q.author].join(' ')});
      best = pickOpenLibrary(docs, q);
    }
    if (best == null) return null;
    final edition = (((best['editions'] as Map?)?['docs'] as List?)?.firstOrNull as Map?)?.cast<String, dynamic>();
    final french = (edition?['language'] as List? ?? const []).contains('fre');
    return _work(best['key'] as String,
        title: (french ? edition!['title'] as String? : null) ?? best['title'] as String? ?? q.title,
        authors: (best['author_name'] as List? ?? const []).cast<String>(),
        year: (best['first_publish_year'] as num?)?.toInt(),
        cover: ((french ? edition!['cover_i'] : null) as num? ?? best['cover_i'] as num?)?.toInt(),
        publisher: null,
        subjects: (best['subject'] as List? ?? const []).cast<String>());
  }

  /// L'œuvre : son résumé et ses sujets.
  Future<OnlineBook> _work(String key,
      {required String title,
      required List<String> authors,
      int? year,
      int? cover,
      String? publisher,
      List<String> subjects = const []}) async {
    final work = await _get(Uri.parse('$openLibrary$key.json'));
    final rawDescription = work?['description'];
    final description = switch (rawDescription) {
      final String s => s,
      final Map m => m['value'] as String?,
      _ => null,
    };
    cover ??= ((work?['covers'] as List?)?.whereType<num>().where((c) => c > 0).firstOrNull)?.toInt();
    return OnlineBook(
      source: 'openlibrary',
      id: key,
      title: title,
      authors: authors,
      year: year,
      description: description == null ? null : plainText(description),
      subjects: _subjects(subjects.isNotEmpty ? subjects : (work?['subjects'] as List? ?? const []).cast<String>()),
      publisher: publisher,
      coverUrl: cover == null ? null : 'https://covers.openlibrary.org/b/id/$cover-L.jpg',
    );
  }

  static List<String> _subjects(List<String> all) => [
        for (final s in all)
          // Pas les sujets techniques (« series:… », « France -- History »).
          if (!s.contains(':') && !s.contains('--') && s.length < 30) s,
      ].take(6).toList();

  /// Le meilleur résultat de recherche, ou null si aucun n'est assez sûr :
  /// titre qui correspond, auteur en commun s'il est connu ; à égalité, une
  /// édition française et une couverture.
  static Map<String, dynamic>? pickOpenLibrary(List<Map<String, dynamic>> docs, BookQuery q) {
    Map<String, dynamic>? best;
    var bestScore = 0;
    final wanted = titleKey(q.title);
    final authorWords = q.author == null ? <String>{} : titleWords(q.author!).map((w) => w.toLowerCase()).toSet();
    for (final d in docs) {
      final title = titleKey(d['title'] as String? ?? '');
      var score = 0;
      if (title == wanted) {
        score += 50;
      } else if (title.isNotEmpty && (wanted.startsWith(title) || title.startsWith(wanted))) {
        score += 30;
      } else if (wanted.contains(title) && title.length > 6) {
        // Recherche libre : « Joel Dicker La Verite sur l Affaire… ».
        score += 25;
      } else {
        continue;
      }
      final authors = (d['author_name'] as List? ?? const []).cast<String>();
      final names = {for (final a in authors) ...titleWords(a).map((w) => w.toLowerCase())};
      if (authorWords.isNotEmpty) {
        if (authorWords.intersection(names).isEmpty) {
          // Recherche libre : l'auteur peut être dans le titre demandé.
          if (!names.any((n) => n.length > 2 && wanted.contains(n))) continue;
        } else {
          score += 20;
        }
      } else if (names.any((n) => n.length > 2 && wanted.contains(n))) {
        score += 15;
      }
      if ((d['language'] as List? ?? const []).contains('fre')) score += 10;
      if (d['cover_i'] != null) score += 5;
      final year = (d['first_publish_year'] as num?)?.toInt();
      if (q.year != null && year != null && year <= q.year!) score += 3;
      if (score > bestScore) {
        bestScore = score;
        best = d;
      }
    }
    return bestScore >= 30 ? best : null;
  }

  // ---- Google Books --------------------------------------------------------

  Future<OnlineBook?> _google(BookQuery q) async {
    final terms = q.isbn != null
        ? 'isbn:${q.isbn}'
        : ['intitle:"${q.title.replaceAll('"', ' ')}"', if (q.author != null) 'inauthor:"${q.author!.replaceAll('"', ' ')}"'].join(' ');
    final json = await _get(Uri.parse('$google/volumes').replace(queryParameters: {
      'q': terms,
      'maxResults': '10',
      'printType': 'books',
      'key': googleKey,
    }));
    final wanted = titleKey(q.title);
    for (final item in (json?['items'] as List? ?? const []).whereType<Map>()) {
      final info = (item['volumeInfo'] as Map?)?.cast<String, dynamic>() ?? const {};
      final title = titleKey(info['title'] as String? ?? '');
      if (q.isbn == null && title != wanted && !title.startsWith(wanted) && !wanted.startsWith(title)) continue;
      final images = (info['imageLinks'] as Map?)?.cast<String, dynamic>();
      final cover = (images?['thumbnail'] ?? images?['smallThumbnail']) as String?;
      return OnlineBook(
        source: 'google',
        id: item['id'] as String? ?? '',
        title: info['title'] as String? ?? q.title,
        authors: (info['authors'] as List? ?? const []).cast<String>(),
        year: int.tryParse((info['publishedDate'] as String? ?? '').padRight(4).substring(0, 4)),
        description: info['description'] == null ? null : plainText(info['description'] as String),
        subjects: _subjects((info['categories'] as List? ?? const []).cast<String>()),
        publisher: info['publisher'] as String?,
        // Couverture plus grande que la vignette, en HTTPS.
        coverUrl: cover?.replaceFirst('http://', 'https://').replaceAll('&edge=curl', '').replaceFirst('zoom=1', 'zoom=2'),
      );
    }
    return null;
  }

  void close() => _http.close(force: true);
}
