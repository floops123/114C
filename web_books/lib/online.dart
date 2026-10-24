import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:c411_core/titles.dart';
import 'package:xml/xml.dart';

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

  /// `openlibrary`, `google`, `hardcover`, `bnf` ou `wikidata`.
  final String source;

  /// Œuvre Open Library (`/works/OL…W`), volume Google Books, livre
  /// Hardcover (son slug) ; pour la BnF et Wikidata, l'adresse de la notice
  /// (ou de l'article Wikipédia).
  final String id;
  final String title;
  final List<String> authors;
  final int? year;
  final String? description;
  final List<String> subjects;
  final String? publisher;
  final String? coverUrl;

  /// Lien vers la fiche, pour l'interface.
  String get url => switch (source) {
        'google' => 'https://books.google.com/books?id=$id',
        'hardcover' => 'https://hardcover.app/books/$id',
        'bnf' || 'wikidata' => id,
        _ => 'https://openlibrary.org$id',
      };

  /// Cette fiche, complétée par [other] là où il lui manque quelque chose
  /// (résumé, couverture, année, auteurs, genres) ; la source reste la sienne.
  OnlineBook completedBy(OnlineBook other) => OnlineBook(
        source: source,
        id: id,
        title: title,
        authors: authors.isNotEmpty ? authors : other.authors,
        year: year ?? other.year,
        description: description ?? other.description,
        subjects: subjects.isNotEmpty ? subjects : other.subjects,
        publisher: publisher ?? other.publisher,
        coverUrl: coverUrl ?? other.coverUrl,
      );

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
/// (meilleurs résumés en français), puis Hardcover si une clé est donnée,
/// puis Open Library, puis le catalogue de la BnF (éditions françaises), sans
/// clé. Une fiche sans résumé ou sans couverture (ou aucune fiche) est
/// complétée par Wikidata et l'article Wikipédia en français.
class OnlineBooks {
  OnlineBooks({
    required String contact,
    this.googleKey = '',
    String hardcoverKey = '',
    this.hardcoverQuotaFile,
    HttpClient? http,
    this.openLibrary = 'https://openlibrary.org',
    this.google = 'https://www.googleapis.com/books/v1',
    this.hardcover = 'https://api.hardcover.app/v1/graphql',
    this.bnf = 'https://catalogue.bnf.fr/api/SRU',
    this.wikidata = 'https://query.wikidata.org/sparql',
    this.wikipedia = 'https://fr.wikipedia.org',
    Duration interval = const Duration(milliseconds: 1100),
  })  : userAgent = 'C411Books/1.0 ( $contact )',
        // Accepté tel que copié depuis Hardcover, avec ou sans « Bearer ».
        hardcoverKey = hardcoverKey.trim().replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), ''),
        _http = http ?? HttpClient(),
        _pace = _Paced(interval),
        _hardcoverPace = _Paced(interval),
        _bnfPace = _Paced(interval),
        _wikiPace = _Paced(interval) {
    _loadQuota();
  }

  final String userAgent;
  final String googleKey;
  final String hardcoverKey;
  final String openLibrary;
  final String google;
  final String hardcover;
  final String bnf;
  final String wikidata;
  final String wikipedia;
  final HttpClient _http;
  final _Paced _pace;

  /// La BnF et Wikimedia, chacun à son rythme (une requête par seconde).
  final _Paced _bnfPace;
  final _Paced _wikiPace;

  /// Hardcover a son propre rythme (60 requêtes par minute au plus).
  final _Paced _hardcoverPace;

  /// Requêtes Hardcover permises par jour : 5 000 pour un compte gratuit,
  /// on s'arrête avant (le compteur du serveur peut différer du nôtre).
  static const hardcoverDailyBudget = 4500;

  /// Compteur du jour, gardé dans ce fichier pour survivre aux redémarrages.
  final String? hardcoverQuotaFile;
  String _hardcoverDay = '';
  int _hardcoverUsed = 0;

  /// Hardcover refuse (quota, saturation) : Open Library seul d'ici là.
  DateTime? _hardcoverPausedUntil;

  /// Clé refusée ou droits insuffisants : Hardcover écarté jusqu'au
  /// redémarrage. Pour l'état affiché.
  String? hardcoverProblem;

  /// Requêtes Hardcover faites aujourd'hui.
  int get hardcoverUsed {
    _rollDay();
    return _hardcoverUsed;
  }

  bool get _hardcoverReady =>
      hardcoverKey.isNotEmpty &&
      hardcoverProblem == null &&
      !(_hardcoverPausedUntil?.isAfter(DateTime.now()) ?? false) &&
      hardcoverUsed < hardcoverDailyBudget;

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
    OnlineBook? found;
    if (googleKey.isNotEmpty) found = await _google(q);
    if (found == null && _hardcoverReady) found = await _hardcover(q);
    // ISBN connu : les recherches exactes (Open Library, BnF) avant toute
    // recherche floue par titre, qui prendrait « Récits d'Ellis Island »
    // pour les « Récits » de Lovecraft.
    if (q.isbn != null) {
      found ??= await _openLibraryByIsbn(q);
      found ??= await _bnf(q, byIsbn: true);
    }
    found ??= await _openLibrary(q);
    found ??= await _bnf(q, byIsbn: false);
    if (found == null || found.description == null || found.coverUrl == null) {
      final wiki = await _wikidata(q, found);
      if (wiki != null) found = found == null ? wiki : found.completedBy(wiki);
    }
    return found;
  }

  /// Texte d'une réponse, à [pace] ; null si absent ou refusé (ces sources ne
  /// bloquent jamais la recherche : on passe à la suivante).
  Future<String?> _text(_Paced pace, Uri uri, {String accept = '*/*'}) => pace.run(() async {
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            final request = await _http.getUrl(uri);
            request.headers
              ..set(HttpHeaders.userAgentHeader, userAgent)
              ..set(HttpHeaders.acceptHeader, accept);
            final reply = await request.close().timeout(const Duration(seconds: 30));
            final body = await reply.transform(utf8.decoder).join();
            if (reply.statusCode == 200) return body;
            if (reply.statusCode != 429 && reply.statusCode != 503) return null;
          } on Object {
            // Réseau, délai : nouvel essai.
          }
          await Future<void>.delayed(Duration(seconds: 2 << attempt));
        }
        return null;
      });

  // ---- Open Library --------------------------------------------------------

  /// L'édition exacte par son ISBN, puis son œuvre.
  Future<OnlineBook?> _openLibraryByIsbn(BookQuery q) async {
    final edition = await _get(Uri.parse('$openLibrary/isbn/${q.isbn}.json'));
    final work = ((edition?['works'] as List?)?.firstOrNull as Map?)?['key'] as String?;
    if (edition == null || work == null) return null;
    final covers = (edition['covers'] as List?)?.whereType<num>().where((c) => c > 0);
    return _work(work,
        title: edition['title'] as String? ?? q.title,
        authors: q.author == null ? const [] : [q.author!],
        year: int.tryParse(RegExp(r'\d{4}').stringMatch('${edition['publish_date'] ?? ''}') ?? ''),
        cover: covers == null || covers.isEmpty ? null : covers.first.toInt(),
        publisher: ((edition['publishers'] as List?)?.firstOrNull) as String?);
  }

  /// Recherche par titre et auteur.
  Future<OnlineBook?> _openLibrary(BookQuery q) async {
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

  // ---- BnF (catalogue général, SRU) ------------------------------------------

  /// Notices de la BnF : par ISBN ([byIsbn] ; le catalogue n'indexe souvent
  /// que l'ISBN-10 des livres anciens : les deux formes), ou par titre et
  /// auteur.
  Future<OnlineBook?> _bnf(BookQuery q, {required bool byIsbn}) async {
    String clean(String s) => s.replaceAll(RegExp(r'["\\]'), ' ').trim();
    final isbn10 = q.isbn == null ? null : isbn10Of(q.isbn!);
    final queries = byIsbn
        ? [
            if (q.isbn != null) 'bib.isbn all "${q.isbn}"',
            if (isbn10 != null) 'bib.isbn all "$isbn10"',
          ]
        : ['bib.title all "${clean(q.title)}"${q.author == null ? '' : ' and bib.author all "${clean(q.author!)}"'}'];
    for (final cql in queries) {
      final xml = await _text(_bnfPace, Uri.parse(bnf).replace(queryParameters: {
        'version': '1.2',
        'operation': 'searchRetrieve',
        'query': cql,
        'recordSchema': 'dublincore',
        'maximumRecords': '20',
      }));
      if (xml == null) continue;
      final best = pickBnf(parseBnf(xml), q);
      if (best != null) return best;
    }
    return null;
  }

  /// Notices Dublin Core d'une réponse SRU de la BnF, nettoyées : titre sans
  /// sa mention de responsabilité, auteurs « Prénom Nom », éditeur sans la
  /// ville, année ; seulement les textes (pas les disques ni les partitions).
  static List<({OnlineBook book, Set<String> isbns})> parseBnf(String xml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } on Object {
      return const [];
    }
    final out = <({OnlineBook book, Set<String> isbns})>[];
    for (final dc in doc.findAllElements('dc', namespaceUri: '*')) {
      List<String> all(String name) =>
          [for (final e in dc.findElements(name, namespaceUri: '*')) e.innerText.trim()];
      if (!all('type').any((t) => t == 'texte imprimé' || t == 'text')) continue;
      // « Les fourmis : roman / Bernard Werber » → « Les fourmis ».
      final title = all('title').firstOrNull?.split(' / ').first.split(' : ').first.trim();
      final ark = all('identifier').firstWhere((i) => i.contains('ark:'), orElse: () => '');
      if (title == null || title.isEmpty || ark.isEmpty) continue;
      String person(String raw) {
        final name = raw.replaceFirst(RegExp(r'\s*\(.*$'), '').replaceFirst(RegExp(r'\.\s.*$'), '').trim();
        final parts = name.split(', ');
        return parts.length == 2 ? '${parts[1]} ${parts[0]}' : name;
      }
      out.add((
        book: OnlineBook(
          source: 'bnf',
          id: ark.replaceFirst('http://', 'https://'),
          title: title,
          authors: [for (final c in all('creator')) person(c)].where((a) => a.isNotEmpty).toList(),
          year: int.tryParse(RegExp(r'\d{4}').stringMatch(all('date').firstOrNull ?? '') ?? ''),
          publisher: all('publisher').firstOrNull?.replaceFirst(RegExp(r'\s*\(.*\)$'), ''),
        ),
        isbns: {
          for (final i in all('identifier'))
            if (i.startsWith('ISBN')) i.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase(),
        },
      ));
    }
    return out;
  }

  /// La notice de la BnF qui correspond : même ISBN, ou titre qui correspond
  /// et auteur en commun s'il est connu (un recueil qui contient la nouvelle
  /// cherchée ne passe pas).
  static OnlineBook? pickBnf(List<({OnlineBook book, Set<String> isbns})> records, BookQuery q) {
    final wanted = titleKey(q.title);
    final isbns = {?q.isbn, if (q.isbn != null) ?isbn10Of(q.isbn!)};
    final authorWords = q.author == null ? <String>{} : titleWords(q.author!).map((w) => w.toLowerCase()).toSet();
    for (final r in records) {
      if (r.isbns.intersection(isbns).isNotEmpty) return r.book;
    }
    for (final r in records) {
      final key = titleKey(r.book.title);
      if (key != wanted && !(key.isNotEmpty && (key.startsWith(wanted) || wanted.startsWith(key)))) continue;
      final names = {for (final a in r.book.authors) ...titleWords(a).map((w) => w.toLowerCase())};
      if (authorWords.isNotEmpty && authorWords.intersection(names).isEmpty) continue;
      return r.book;
    }
    return null;
  }

  /// ISBN-10 d'un ISBN-13 en 978, ou null.
  static String? isbn10Of(String isbn) {
    final d = isbn.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length != 13 || !d.startsWith('978')) return null;
    final core = d.substring(3, 12);
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      sum += (10 - i) * int.parse(core[i]);
    }
    final check = (11 - sum % 11) % 11;
    return '$core${check == 10 ? 'X' : '$check'}';
  }

  // ---- Wikidata et Wikipédia ------------------------------------------------

  /// L'œuvre sur Wikidata (titre et auteur), puis le résumé et l'image de
  /// son article Wikipédia en français. [found] : la fiche déjà trouvée, pour
  /// son auteur si [q] n'en a pas.
  Future<OnlineBook?> _wikidata(BookQuery q, OnlineBook? found) async {
    final title = q.title;
    final author = q.author ?? found?.authors.firstOrNull;
    String literal(String s) => s.replaceAll('\\', ' ').replaceAll('"', ' ').replaceAll('\n', ' ');
    final sparql = '''
SELECT ?item ?titre ?auteur ?date ?genre ?article WHERE {
  SERVICE wikibase:mwapi {
    bd:serviceParam wikibase:api "EntitySearch"; wikibase:endpoint "www.wikidata.org";
                    mwapi:search "${literal(title)}"; mwapi:language "fr"; mwapi:limit "10" .
    ?item wikibase:apiOutputItem mwapi:item .
  }
  ?item wdt:P50 ?a .
  ?a rdfs:label ?auteur . FILTER(LANG(?auteur) IN ("fr", "en"))
  OPTIONAL { ?item rdfs:label ?titre . FILTER(LANG(?titre) = "fr") }
  OPTIONAL { ?item wdt:P577 ?date }
  OPTIONAL { ?item wdt:P136 ?g . ?g rdfs:label ?genre . FILTER(LANG(?genre) = "fr") }
  OPTIONAL { ?article schema:about ?item ; schema:isPartOf <https://fr.wikipedia.org/> }
}''';
    final body = await _text(_wikiPace, Uri.parse(wikidata).replace(queryParameters: {'query': sparql}),
        accept: 'application/sparql-results+json');
    final work = body == null ? null : pickWikidata(body, (title: title, author: author, isbn: null, year: null));
    if (work == null) return null;
    String? description;
    String? cover;
    final article = work.article;
    if (article != null) {
      // Segment déjà encodé tel que donné par Wikidata (« ? » ou « / » dans
      // un titre ne doivent pas casser l'adresse).
      final page = article.substring(article.lastIndexOf('/') + 1);
      final summary = await _text(_wikiPace, Uri.parse('$wikipedia/api/rest_v1/page/summary/$page'),
          accept: 'application/json');
      try {
        final j = jsonDecode(summary ?? '') as Map<String, dynamic>;
        if (j['type'] == 'standard') {
          description = (j['extract'] as String?)?.trim();
          cover = ((j['originalimage'] ?? j['thumbnail']) as Map?)?['source'] as String?;
        }
      } on Object {
        // Pas de résumé.
      }
    }
    return OnlineBook(
      source: 'wikidata',
      id: article ?? work.item.replaceFirst('http://www.wikidata.org/entity/', 'https://www.wikidata.org/wiki/'),
      title: work.title ?? title,
      authors: work.authors,
      year: work.year,
      description: description == null || description.isEmpty ? null : description,
      subjects: _subjects(work.genres),
      coverUrl: cover,
    );
  }

  /// L'œuvre qui correspond dans une réponse SPARQL (une ligne par
  /// combinaison auteur × genre) : titre qui correspond, auteur en commun s'il
  /// est connu ; à égalité, celle qui a un article Wikipédia (l'œuvre plutôt
  /// qu'une de ses éditions), puis la plus ancienne.
  static ({String item, String? title, List<String> authors, int? year, List<String> genres, String? article})?
      pickWikidata(String json, BookQuery q) {
    final List<Object?> rows;
    try {
      rows = ((jsonDecode(json) as Map)['results'] as Map)['bindings'] as List;
    } on Object {
      return null;
    }
    final items = <String, Map<String, Object>>{};
    String? value(Map row, String k) => (row[k] as Map?)?['value'] as String?;
    for (final row in rows.whereType<Map>()) {
      final item = value(row, 'item');
      if (item == null) continue;
      final w = items.putIfAbsent(item, () => {'authors': <String>{}, 'genres': <String>{}});
      if (value(row, 'titre') case final t?) w['title'] = t;
      if (value(row, 'auteur') case final a?) (w['authors'] as Set<String>).add(a);
      if (value(row, 'genre') case final g?) (w['genres'] as Set<String>).add(g);
      if (value(row, 'article') case final a?) w['article'] = a;
      final year = int.tryParse((value(row, 'date') ?? '').padRight(4).substring(0, 4));
      if (year != null && (w['year'] == null || year < (w['year'] as int))) w['year'] = year;
    }
    final wanted = titleKey(q.title);
    final authorWords = q.author == null ? <String>{} : titleWords(q.author!).map((w) => w.toLowerCase()).toSet();
    MapEntry<String, Map<String, Object>>? best;
    var bestScore = -1;
    for (final e in items.entries) {
      final w = e.value;
      final key = titleKey(w['title'] as String? ?? '');
      if (key.isEmpty || (key != wanted && !key.startsWith(wanted) && !wanted.startsWith(key))) continue;
      final names = {for (final a in w['authors'] as Set<String>) ...titleWords(a).map((x) => x.toLowerCase())};
      if (authorWords.isNotEmpty && authorWords.intersection(names).isEmpty) continue;
      var score = key == wanted ? 10 : 5;
      if (w['article'] != null) score += 20;
      if (w['year'] != null) score += 1;
      if (score > bestScore) (bestScore, best) = (score, e);
    }
    if (best == null) return null;
    final w = best.value;
    return (
      item: best.key,
      title: w['title'] as String?,
      authors: (w['authors'] as Set<String>).toList(),
      year: w['year'] as int?,
      genres: (w['genres'] as Set<String>).toList(),
      article: w['article'] as String?,
    );
  }

  // ---- Hardcover (GraphQL) -------------------------------------------------

  static const _hardcoverSearch = r'''
query Livres($q: String!) {
  search(query: $q, query_type: "book", per_page: 10, page: 1) { results }
}''';

  /// Une recherche Hardcover : une seule requête (le résultat porte déjà
  /// résumé, genres et couverture). Jamais d'exception : en cas de souci,
  /// null, et la recherche continue sur Open Library.
  Future<OnlineBook?> _hardcover(BookQuery q) async {
    final query = q.isbn ?? [q.title, ?q.author].join(' ');
    final data = await _graphql(_hardcoverSearch, {'q': query});
    final results = (data?['search'] as Map?)?['results'];
    final hits = results is Map ? results['hits'] as List? ?? const [] : const [];
    final docs = [
      for (final h in hits.whereType<Map>())
        if (h['document'] case final Map d) d.cast<String, dynamic>(),
    ];
    final match = pickHardcover(docs, q);
    if (match == null) return null;
    final (doc, title) = match;
    final image = doc['image'];
    final description = doc['description'] as String?;
    return OnlineBook(
      source: 'hardcover',
      id: '${doc['slug'] ?? doc['id'] ?? ''}',
      title: title,
      authors: (doc['author_names'] as List? ?? const []).whereType<String>().toList(),
      year: (doc['release_year'] as num?)?.toInt(),
      description: description == null || description.trim().isEmpty ? null : plainText(description),
      subjects: _subjects((doc['genres'] as List? ?? const []).whereType<String>().toList()),
      coverUrl: image is Map ? image['url'] as String? : null,
    );
  }

  /// Le meilleur résultat Hardcover et le titre qui a correspondu (souvent
  /// le titre français parmi les `alternative_titles`), ou null. Mêmes
  /// règles que [pickOpenLibrary] ; un ISBN identique suffit.
  static (Map<String, dynamic>, String)? pickHardcover(List<Map<String, dynamic>> docs, BookQuery q) {
    (Map<String, dynamic>, String)? best;
    var bestScore = 0;
    final wanted = titleKey(q.title);
    final authorWords = q.author == null ? <String>{} : titleWords(q.author!).map((w) => w.toLowerCase()).toSet();
    for (final d in docs) {
      final isbns = (d['isbns'] as List? ?? const []).map((i) => '$i').toSet();
      final titles = [d['title'], ...(d['alternative_titles'] as List? ?? const [])].whereType<String>();
      var score = 0;
      var matched = d['title'] as String? ?? q.title;
      if (q.isbn != null && isbns.contains(q.isbn)) {
        score = 100;
      } else {
        for (final t in titles) {
          final key = titleKey(t);
          // À égalité (accents ignorés), le titre écrit comme celui cherché :
          // « Les Misérables » plutôt que « Les Miserables ».
          final s = key == wanted
              ? (t.trim() == q.title.trim() ? 51 : 50)
              : key.isNotEmpty && (wanted.startsWith(key) || key.startsWith(wanted))
                  ? 30
                  : 0;
          if (s > score) (score, matched) = (s, t);
        }
        if (score == 0) continue;
        final names = {
          for (final a in (d['author_names'] as List? ?? const []).whereType<String>())
            ...titleWords(a).map((w) => w.toLowerCase()),
        };
        if (authorWords.isNotEmpty) {
          if (authorWords.intersection(names).isEmpty) continue;
          score += 20;
        }
      }
      if (d['image'] is Map) score += 5;
      if ((d['description'] as String? ?? '').isNotEmpty) score += 3;
      if (score > bestScore) {
        bestScore = score;
        best = (d, matched);
      }
    }
    return bestScore >= 30 ? best : null;
  }

  Future<Map<String, dynamic>?> _graphql(String query, Map<String, Object?> variables) =>
      _hardcoverPace.run(() async {
        if (!_hardcoverReady) return null;
        _count();
        try {
          final request = await _http.postUrl(Uri.parse(hardcover));
          request.headers
            ..set(HttpHeaders.userAgentHeader, userAgent)
            ..set(HttpHeaders.authorizationHeader, 'Bearer $hardcoverKey')
            ..contentType = ContentType.json;
          request.write(jsonEncode({'query': query, 'variables': variables}));
          final reply = await request.close().timeout(const Duration(seconds: 30));
          final body = await reply.transform(utf8.decoder).join();
          switch (reply.statusCode) {
            case 200:
              final json = jsonDecode(body) as Map<String, dynamic>;
              return json['errors'] == null ? json['data'] as Map<String, dynamic>? : null;
            case 401:
              hardcoverProblem = 'clé Hardcover refusée ou expirée';
            case 403:
              hardcoverProblem = 'clé Hardcover sans le droit de lire les livres';
            case 429:
              // Quota du jour ou de la minute : on laisse Hardcover tranquille.
              _hardcoverPausedUntil = DateTime.now().add(const Duration(hours: 1));
          }
          return null;
        } on Object {
          return null; // Réseau, délai : Open Library prend le relais.
        }
      });

  void _rollDay() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (today != _hardcoverDay) {
      _hardcoverDay = today;
      _hardcoverUsed = 0;
    }
  }

  void _count() {
    _rollDay();
    _hardcoverUsed++;
    final file = hardcoverQuotaFile;
    if (file == null) return;
    try {
      File(file).writeAsStringSync(jsonEncode({'day': _hardcoverDay, 'used': _hardcoverUsed}));
    } on FileSystemException {
      // Compteur en mémoire seulement.
    }
  }

  void _loadQuota() {
    final file = hardcoverQuotaFile;
    if (file == null) return;
    try {
      final j = jsonDecode(File(file).readAsStringSync()) as Map;
      _hardcoverDay = j['day'] as String? ?? '';
      _hardcoverUsed = (j['used'] as num?)?.toInt() ?? 0;
    } on Object {
      // Pas encore de compteur.
    }
  }

  void close() => _http.close(force: true);
}
