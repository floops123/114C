import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:c411_core/book_name.dart';
import 'package:c411_core/ftp.dart';
import 'package:c411_web_books/config.dart';
import 'package:c411_web_books/content.dart';
import 'package:c411_web_books/inspect.dart';
import 'package:c411_web_books/library.dart';
import 'package:c411_web_books/online.dart';
import 'package:c411_web_books/remote_zip.dart';
import 'package:c411_web_books/server.dart';
import 'package:c411_web_books/service.dart';
import 'package:test/test.dart';

void main() {
  group('noms', () {
    BookGuess g(String p) => BookGuess.parse(p);

    test('livres : « Auteur - Titre », Calibre, scène, tome', () {
      final a = g('/ebooks/Victor Hugo - Les Misérables (1862).epub');
      expect((a.kind, a.title, a.author, a.year), (BookKind.book, 'Les Misérables', 'Victor Hugo', 1862));
      final b = g('/ebooks/Hugo, Victor - Notre-Dame de Paris [FR EPUB].epub');
      expect((b.title, b.author), ('Notre-Dame de Paris', 'Victor Hugo'));
      final c = g('/ebooks/Joel.Dicker.La.Verite.sur.l.Affaire.Harry.Quebert.2012.FRENCH.EPUB.epub');
      expect((c.title, c.author, c.year), ('Joel Dicker La Verite sur l Affaire Harry Quebert', null, 2012));
      final d = g('/ebooks/Harry Potter T1 - J.K. Rowling.epub');
      expect((d.title, d.author, d.series, d.volume), ('Harry Potter T1', 'J.K. Rowling', 'Harry Potter', 1.0));
    });

    test('BD et mangas : série et tome', () {
      final a = g('/BD/Astérix/Astérix - T01 - Astérix le Gaulois.cbz');
      expect((a.kind, a.series, a.volume, a.title), (BookKind.comic, 'Astérix', 1.0, 'Astérix le Gaulois'));
      final b = g('/BD/Blacksad T03 - Ame rouge (2005).cbr');
      expect((b.series, b.volume, b.title, b.year), ('Blacksad', 3.0, 'Ame rouge', 2005));
      final c = g('/Mangas/One Piece/One Piece 012.cbz');
      expect((c.kind, c.series, c.volume), (BookKind.manga, 'One Piece', 12.0));
      expect(g('/comics/Batman (2016) #001.cbz').volume, 1.0);
    });

    test('magazines : titre, numéro, date', () {
      final a = g('/Presse/Le Point N°2650 - 6 Juin 2025.pdf');
      expect((a.kind, a.title, a.issue, a.year, a.month, a.day), (BookKind.magazine, 'Le Point', 2650, 2025, 6, 6));
      final b = g('/torrents/Science & Vie - Juillet 2025.pdf');
      expect((b.kind, b.title, b.year, b.month), (BookKind.magazine, 'Science & Vie', 2025, 7));
      final c = g('/torrents/01net N°1023 du 04.06.2025.pdf');
      expect((c.title, c.issue, c.day, c.month), ('01net', 1023, 4, 6));
      final d = g('/torrents/Le.Monde.Diplomatique.Octobre.2025.FRENCH.PDF.pdf');
      expect((d.title, d.month), ('Le Monde Diplomatique', 10));
    });

    test('torrents : un pack de livres, pas la notice d’un jeu', () {
      final found = booksOfTorrents([
        {
          'hashString': 'AAA', 'downloadDir': '/t', 'percentDone': 1,
          'files': [
            {'name': 'Presse/Le Point N°2650.pdf', 'length': 60 << 20},
            {'name': 'Presse/facture.pdf', 'length': 50 << 10},
          ],
        },
        {
          'hashString': 'BBB', 'downloadDir': '/t', 'percentDone': 1,
          'files': [
            {'name': 'Jeu/data.pak', 'length': 4 << 30},
            {'name': 'Jeu/Manuel.pdf', 'length': 3 << 20},
          ],
        },
      ]);
      expect([for (final f in found) (f.path, f.hash)], [('/t/Presse/Le Point N°2650.pdf', 'aaa')]);
    });
  });

  group('archives et métadonnées', () {
    test('ZIP lu par morceaux : répertoire central, puis l’entrée', () async {
      final zip = buildZip({
        'mimetype': utf8.encode('application/epub+zip'),
        'Images/Couverture é.jpg': List.filled(5000, 7),
        'texte.xhtml': utf8.encode('<p>${'Bonjour ' * 2000}</p>'),
      }, deflate: {'texte.xhtml'});
      final reads = <(int, int)>[];
      final archive = await RemoteZip.open((start, length) async {
        reads.add((start, length));
        return Uint8List.sublistView(zip, start, (start + length).clamp(0, zip.length));
      }, zip.length);
      expect([for (final e in archive.entries) e.name], ['mimetype', 'Images/Couverture é.jpg', 'texte.xhtml']);
      expect(reads, hasLength(1), reason: 'la fin de l’archive suffit');
      expect(await archive.readText(archive.entry('texte.xhtml')!), startsWith('<p>Bonjour Bonjour'));
      expect((await archive.read(archive.entry('images/couverture é.jpg')!)).length, 5000,
          reason: 'nom sans tenir compte de la casse');
    });

    test('EPUB : OPF (titre, auteur, série, ISBN, résumé, couverture)', () {
      final e = parseOpf(_opf, opfPath: 'OEBPS/content.opf', names: ['OEBPS/Images/Cover.JPG']);
      expect((e.title, e.series, e.volume, e.isbn, e.language, e.year),
          ('Les Misérables', 'Les Misérables', 2.0, '9782070409228', 'fr', 1862));
      expect(e.authors, ['Victor Hugo'], reason: 'pas le traducteur');
      expect(e.description, 'Jean Valjean, ancien forçat.\nUne fresque.');
      expect(e.cover, 'OEBPS/Images/Cover.JPG', reason: 'chemin relatif résolu, casse du fichier');
      expect(e.subjects, ['Roman']);
    });

    test('BD : ComicInfo.xml, pages dans l’ordre naturel', () {
      final c = parseComicInfo(
          '<ComicInfo><Series>Astérix</Series><Number>3</Number><Title>Astérix et les Goths</Title>'
          '<Year>1963</Year><Month>4</Month><Writer>René Goscinny</Writer><Penciller>Albert Uderzo</Penciller>'
          '<Summary>&lt;b&gt;Panoramix&lt;/b&gt; est enlevé.</Summary><Manga>YesAndRightToLeft</Manga></ComicInfo>');
      expect((c.series, c.volume, c.title, c.date, c.description, c.rightToLeft),
          ('Astérix', 3.0, 'Astérix et les Goths', '1963-04', 'Panoramix est enlevé.', true));
      expect(c.authors, ['René Goscinny', 'Albert Uderzo']);
      expect(comicPages(['p10.jpg', 'p2.jpg', '__MACOSX/p1.jpg', '.cache.png', 'ComicInfo.xml', 'p1.webp']),
          ['p1.webp', 'p2.jpg', 'p10.jpg']);
      expect(imageType([0xff, 0xd8, 0xff]), 'image/jpeg');
    });
  });

  group('en ligne', () {
    const q = (title: 'Les Misérables', author: 'Victor Hugo', isbn: null, year: null);

    test('Open Library : titre, auteur, édition française', () {
      final best = OnlineBooks.pickOpenLibrary([
        {'key': '/works/autre', 'title': 'Les Misérables', 'author_name': ['Claude Schönberg'], 'language': ['fre']},
        {'key': '/works/en', 'title': 'Les Miserables', 'author_name': ['Victor Hugo'], 'language': ['eng']},
        {'key': '/works/fr', 'title': 'Les Misérables', 'author_name': ['Victor Hugo'], 'language': ['fre', 'eng'], 'cover_i': 1},
        {'key': '/works/x', 'title': 'Notre-Dame de Paris', 'author_name': ['Victor Hugo']},
      ], q);
      expect(best?['key'], '/works/fr');
      expect(OnlineBooks.pickOpenLibrary([{'key': '/works/x', 'title': 'Notre-Dame de Paris'}], q), isNull);
    });

    test('recherche puis œuvre (résumé), User-Agent', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final agents = <String?>[];
      server.listen((r) async {
        agents.add(r.headers.value(HttpHeaders.userAgentHeader));
        if (r.uri.path == '/search.json') expect(r.uri.queryParameters['lang'], 'fre');
        final body = switch (r.uri.path) {
          '/search.json' => {
              'docs': [
                {
                  'key': '/works/OL1W', 'title': 'Les Miserables', 'author_name': ['Victor Hugo'],
                  'first_publish_year': 1862, 'cover_i': 42,
                  // L'édition française (lang=fre) : son titre et sa couverture.
                  'editions': {
                    'docs': [
                      {'key': '/books/OL9M', 'title': 'Les Misérables', 'cover_i': 99, 'language': ['fre']},
                    ],
                  },
                },
              ],
            },
          '/works/OL1W.json' => {'description': {'value': 'Jean Valjean…'}, 'subjects': ['Fiction', 'France -- History']},
          _ => null,
        };
        r.response.statusCode = body == null ? 404 : 200;
        r.response.write(jsonEncode(body));
        await r.response.close();
      });
      final online = OnlineBooks(contact: 'moi', openLibrary: 'http://127.0.0.1:${server.port}', interval: Duration.zero);
      addTearDown(online.close);
      final b = await online.find(q);
      expect((b?.title, b?.year, b?.description, b?.coverUrl, b?.url), (
        'Les Misérables', 1862, 'Jean Valjean…', 'https://covers.openlibrary.org/b/id/99-L.jpg',
        'https://openlibrary.org/works/OL1W',
      ));
      expect(b?.subjects, ['Fiction'], reason: 'pas les sujets à rallonge');
      expect(agents.every((a) => a == 'C411Books/1.0 ( moi )'), isTrue);
    });
  });

  group('bibliothèque', () {
    test('le fichier prime, puis la fiche en ligne, puis le nom ; séries', () {
      final files = [
        BookFile(path: '/BD/Astérix - T02.cbz', size: 1),
        BookFile(path: '/BD/Astérix - T01.cbz', size: 1),
        BookFile(path: '/Presse/Le Point N°2651 - 13 Juin 2025.pdf', size: 1),
        BookFile(path: '/Presse/Le Point N°2650 - 6 Juin 2025.pdf', size: 1),
        BookFile(path: '/ebooks/Victor Hugo - Les Miserables.epub', size: 1),
        BookFile(path: '/ebooks/Inconnu - Seul.mobi', size: 1),
      ];
      final state = BookState({
        '/ebooks/Victor Hugo - Les Miserables.epub': BookInfo(
          embedded: const Embedded(title: 'Les Misérables', description: 'Du fichier.'),
          online: const OnlineBook(source: 'openlibrary', id: '/works/OL1W', title: 'Les Misérables (édition)', authors: ['Victor Hugo'], description: 'En ligne.', year: 1862),
        ),
      });
      final catalog = Catalog.of(files, state);
      final hugo = catalog.books.firstWhere((b) => b.file.format == 'epub');
      expect((hugo.title, hugo.description, hugo.year, hugo.file.reader), ('Les Misérables', 'Du fichier.', 1862, 'epub'));
      expect(hugo.authors, ['Victor Hugo'], reason: 'le fichier n’en dit rien : la fiche en ligne');
      final json = catalog.toJson(cover: (_) => false);
      final series = {for (final s in json['series'] as List) (s as Map)['name']: s['books'] as List};
      expect(series.keys, unorderedEquals(['Astérix', 'Le Point']), reason: 'un livre seul n’est pas une série');
      String title(String id) => catalog.book(id)!.file.name;
      expect(series['Astérix']!.map((id) => title(id as String)), ['Astérix - T01.cbz', 'Astérix - T02.cbz']);
      expect(series['Le Point']!.map((id) => catalog.book(id as String)!.guess.issue), [2650, 2651]);
      final mag = catalog.books.firstWhere((b) => b.guess.issue == 2650);
      expect((mag.date, mag.file.reader), ('2025-06-06', 'pdf'));
      expect(catalog.books.firstWhere((b) => b.file.format == 'mobi').file.reader, isNull);
    });

    test('base de l’application, état enregistré', () {
      final app = BookState.parseApp(jsonEncode({
        'flutter.mediaLibrary': jsonEncode({
          'books': [
            {'path': '/a.epub', 'size': 3, 'added': '2026-10-01T00:00:00.000'},
          ],
          'scannedAt': '2026-10-20T08:00:00.000',
        }),
      }));
      expect((app.files.single.path, app.scannedAt), ('/a.epub', DateTime(2026, 10, 20, 8)));
      final dir = Directory.systemTemp.createTempSync('c411_books');
      addTearDown(() => dir.deleteSync(recursive: true));
      BookState({'/a.epub': BookInfo(inspected: DateTime(2026), embedded: const Embedded(title: 'A', pages: 3))})
          .write('${dir.path}/x/books.json');
      final back = BookState.read('${dir.path}/x/books.json');
      expect(back.info['/a.epub']?.embedded?.title, 'A');
      expect(back.info['/a.epub']?.searchStale, isTrue, reason: 'jamais cherché');
    });
  });

  group('serveur', () {
    late Directory dir;
    late HttpServer files;
    late BooksServer server;
    late BooksService service;
    late Uri base;
    final epub = buildZip({
      'mimetype': utf8.encode('application/epub+zip'),
      'META-INF/container.xml': utf8.encode(
          '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>'),
      'OEBPS/content.opf': utf8.encode(_opf),
      'OEBPS/Images/Cover.JPG': [0xff, 0xd8, 0xff, ...List.filled(300, 1)],
    });
    final cbz = buildZip({
      'p2.jpg': [0xff, 0xd8, 0xff, 2],
      'p1.png': [0x89, 0x50, 0x4e, 0x47, 1],
      'ComicInfo.xml': utf8.encode('<ComicInfo><Series>Astérix</Series><Number>1</Number><Title>Astérix le Gaulois</Title></ComicInfo>'),
    });

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('c411_books');
      // Le relais FTP : les fichiers par chemin, avec Range.
      final blobs = {'/Livres/Hugo - Les Miserables.epub': epub, '/BD/Asterix - T01.cbz': cbz};
      files = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      files.listen((r) async {
        final data = blobs[Uri.decodeComponent(r.uri.path)];
        if (data == null) {
          r.response.statusCode = 404;
        } else {
          final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(r.headers.value('range') ?? '');
          final start = m == null ? 0 : int.parse(m[1]!);
          final end = m == null || m[2]!.isEmpty ? data.length - 1 : int.parse(m[2]!).clamp(0, data.length - 1);
          r.response
            ..statusCode = m == null ? 200 : 206
            ..headers.set('accept-ranges', 'bytes');
          if (m != null) r.response.headers.set('content-range', 'bytes $start-$end/${data.length}');
          r.response.add(data.sublist(start, end + 1));
        }
        await r.response.close();
      });
      File('${dir.path}/prefs.json').writeAsStringSync(jsonEncode({
        'flutter.mediaLibrary': jsonEncode({
          'books': [
            for (final MapEntry(:key, :value) in blobs.entries) {'path': key, 'size': value.length},
          ],
        }),
      }));
      File('${dir.path}/index.html').writeAsStringSync('<title>C411 Books</title>');
      final config = BooksConfig(
        ftp: const FtpConfig(host: 'ftp.invalid', port: 21, user: 'u', password: 'p', tls: false),
        library: '${dir.path}/prefs.json',
        state: '${dir.path}/state/books.json',
        port: 0,
        password: 'secret',
      );
      service = BooksService(
        appLibrary: config.library,
        statePath: config.state,
        content: Content(
          urlFor: (path) async => Uri.parse('http://127.0.0.1:${files.port}${Uri.encodeFull(path)}'),
          cacheDir: config.cacheDir,
          tools: const Tools(),
        ),
        // Sans réseau : la recherche échoue vite, sans rien casser.
        online: OnlineBooks(contact: 't', openLibrary: 'http://127.0.0.1:9', interval: Duration.zero),
      );
      service.refresh(); // Lance la lecture des fichiers, en arrière-plan.
      while (service.working) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      server = BooksServer(config, service: service, publicDir: dir.path);
      final http = await server.start();
      base = Uri.parse('http://127.0.0.1:${http.port}');
    });

    tearDown(() async {
      await server.close();
      service.close();
      await files.close(force: true);
      dir.deleteSync(recursive: true);
    });

    Future<(int, List<int>, HttpHeaders)> get(String path, {bool auth = true, Map<String, String> headers = const {}}) async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(base.resolve(path));
        if (auth) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Basic ${base64.encode(utf8.encode('x:secret'))}');
        }
        headers.forEach(request.headers.set);
        final reply = await request.close();
        final body = await reply.fold<List<int>>([], (a, b) => a..addAll(b));
        return (reply.statusCode, body, reply.headers);
      } finally {
        client.close(force: true);
      }
    }

    test('mot de passe exigé', () async {
      expect((await get('/', auth: false)).$1, 401);
      expect(utf8.decode((await get('/')).$2), contains('C411 Books'));
    });

    test('bibliothèque, couvertures, pages, fichier', () async {
      final (status, body, _) = await get('/api/library');
      expect(status, 200);
      final json = jsonDecode(utf8.decode(body)) as Map;
      final books = <String, dynamic>{for (final b in json['books'] as List) (b as Map)['format'] as String: b};
      expect(books['epub']['title'], 'Les Misérables');
      expect(books['epub']['cover'], isTrue);
      expect(books['cbz']['title'], 'Astérix le Gaulois');
      expect(books['cbz']['pages'], 2);
      expect(utf8.decode(body), isNot(contains('/Livres/')), reason: 'aucun chemin du FTP');
      expect((json['status'] as Map)['error'], contains('Recherche en ligne'), reason: 'pas de réseau dans les tests');

      final (coverStatus, cover, coverHeaders) = await get('/api/cover/${books['epub']['id']}');
      expect((coverStatus, coverHeaders.contentType?.mimeType), (200, 'image/jpeg'));
      expect(cover.take(3), [0xff, 0xd8, 0xff]);
      expect(Directory('${dir.path}/state/covers').listSync(), hasLength(1), reason: 'gardée sur le disque');

      final id = books['cbz']['id'];
      expect(jsonDecode(utf8.decode((await get('/api/pages/$id')).$2)), {'count': 2});
      final (_, page0, h0) = await get('/page/$id/0');
      expect(page0, [0x89, 0x50, 0x4e, 0x47, 1], reason: 'p1 avant p2');
      expect(h0.contentType?.mimeType, 'image/png');
      expect((await get('/page/$id/5')).$1, 404);

      final (rangeStatus, part, rangeHeaders) = await get('/media/${books['epub']['id']}', headers: {'range': 'bytes=0-7'});
      expect(rangeStatus, 206);
      expect(part, epub.sublist(0, 8));
      expect(rangeHeaders.contentType?.mimeType, 'application/epub+zip');
      final (_, _, download) = await get('/media/${books['cbz']['id']}?download=1');
      expect(download.value('content-disposition'), contains("filename*=UTF-8''Asterix%20-%20T01.cbz"));
      expect((await get('/api/cover/inconnu')).$1, 404);
    });
  });

  test('réglages', () {
    final dir = Directory.systemTemp.createTempSync('c411_books');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/personal.json')
      ..writeAsStringSync(jsonEncode({
        'ftpHost': 'ftp.example.org',
        'books': {'port': 9001, 'googleBooksKey': 'cle', 'cacheGb': 0.5, 'state': '/x/books.json'},
      }));
    final c = BooksConfig.load(file.path, overrides: {'host': '0.0.0.0'});
    expect((c.port, c.googleBooksKey, c.cacheBytes, c.cacheDir, c.public), (9001, 'cle', 1 << 29, '/x', true));
  });
}

const _opf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
<dc:title>Les Misérables</dc:title><dc:creator opf:role="aut">Victor Hugo</dc:creator>
<dc:creator opf:role="trl">Un Traducteur</dc:creator>
<dc:language>fr</dc:language><dc:date>1862-01-01</dc:date>
<dc:description>&lt;p&gt;Jean Valjean, ancien forçat.&lt;/p&gt;&lt;p&gt;Une fresque.&lt;/p&gt;</dc:description>
<dc:subject>Roman</dc:subject><dc:identifier opf:scheme="ISBN">978-2-07-040922-8</dc:identifier>
<meta name="cover" content="cov"/><meta name="calibre:series" content="Les Misérables"/><meta name="calibre:series_index" content="2"/>
</metadata>
<manifest><item id="cov" href="Images/cover.jpg" media-type="image/jpeg"/></manifest></package>''';

/// Archive ZIP minimale : entrées stockées, ou compressées pour [deflate].
Uint8List buildZip(Map<String, List<int>> entries, {Set<String> deflate = const {}}) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([v & 0xff, v >> 8 & 0xff]);
  void u32(BytesBuilder b, int v) => b.add([v & 0xff, v >> 8 & 0xff, v >> 16 & 0xff, v >> 24 & 0xff]);
  for (final MapEntry(key: name, value: raw) in entries.entries) {
    final nameBytes = utf8.encode(name);
    final method = deflate.contains(name) ? 8 : 0;
    final data = method == 8 ? ZLibEncoder(raw: true).convert(raw) : raw;
    final offset = out.length;
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0x800);
    u16(out, method);
    u32(out, 0);
    u32(out, 0); // CRC (non vérifié)
    u32(out, data.length);
    u32(out, raw.length);
    u16(out, nameBytes.length);
    u16(out, 0);
    out
      ..add(nameBytes)
      ..add(data);
    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0x800);
    u16(central, method);
    u32(central, 0);
    u32(central, 0);
    u32(central, data.length);
    u32(central, raw.length);
    u16(central, nameBytes.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(nameBytes);
  }
  final cdOffset = out.length;
  final cd = central.takeBytes();
  out.add(cd);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, entries.length);
  u16(out, entries.length);
  u32(out, cd.length);
  u32(out, cdOffset);
  u16(out, 0);
  return out.takeBytes();
}
