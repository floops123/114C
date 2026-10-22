import 'dart:io';

import 'package:c411_remote/api/ftp.dart';
import 'package:c411_remote/api/media_relay.dart';
import 'package:c411_remote/state/media_library.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_webdav.dart';

void main() {
  final movie = List.generate(100000, (i) => i % 251);
  late FakeWebDav server;
  setUp(() async => server = await FakeWebDav.start({
        '/Films/Mon Film (2024).mkv': movie,
        '/Films/Série/S01E01.mkv': [1, 2, 3],
        '/Musique/a.flac': [4, 5],
      }));
  tearDown(() => server.close());

  WebDavClient client({String password = 'secret'}) =>
      WebDavClient(WebDavConfig(url: server.url, user: 'moi', password: password));

  test('WebDAV : dossiers, tailles, lecture à partir d’une position', () async {
    final dav = client();
    await dav.connect();
    final root = await dav.list('/');
    expect({for (final e in root) e.name: e.isDir}, {'Films': true, 'Musique': true});
    final films = await dav.list('/Films');
    expect({for (final e in films) e.name: (e.isDir, e.size)},
        {'Mon Film (2024).mkv': (false, 100000), 'Série': (true, 0)});

    expect(await dav.size('/Films/Mon Film (2024).mkv'), 100000);
    expect(await dav.size('/Films/absent.mkv'), isNull);
    expect(await dav.size('/Films'), isNull, reason: 'un dossier n’a pas de taille');

    final data = await dav.read('/Films/Mon Film (2024).mkv', offset: 99990);
    expect(await data.expand((c) => c).toList(), movie.sublist(99990));
    expect(server.requests.last, 'GET /Films/Mon Film (2024).mkv');
    await dav.close();
  });

  test('WebDAV : création de dossiers et envoi', () async {
    final dav = client();
    await dav.makeDirs('/Envois/Pack-GRP/sous');
    expect(server.dirs, containsAll(['/Envois', '/Envois/Pack-GRP', '/Envois/Pack-GRP/sous']));
    await dav.makeDirs('/Envois/Pack-GRP'); // Existe déjà : sans erreur.

    var sent = 0;
    await dav.write('/Envois/Pack-GRP/sous/b.txt', Stream.fromIterable([[1, 2], [3]]),
        onProgress: (n) => sent = n);
    expect(server.files['/Envois/Pack-GRP/sous/b.txt'], [1, 2, 3]);
    expect(sent, 3);
    await dav.close();
  });

  test('WebDAV : identifiants refusés, message clair', () async {
    final dav = client(password: 'faux');
    await expectLater(dav.connect(),
        throwsA(isA<RemoteFilesException>().having((e) => e.message, 'message', contains('refusés'))));
    await dav.close();
  });

  test('réponse PROPFIND : préfixes d’espace de noms variés', () {
    const xml = '<?xml version="1.0"?><multistatus xmlns="DAV:">'
        '<response><href>/dav/a%20b/</href><propstat><prop><resourcetype><collection/></resourcetype></prop></propstat></response>'
        '<response><href>https://h/dav/a%20b/c.mkv</href><propstat><prop><resourcetype/>'
        '<getcontentlength>42</getcontentlength></prop></propstat></response></multistatus>';
    expect(WebDavClient.parseMultistatus(xml), [('/dav/a b/', true, 0), ('/dav/a b/c.mkv', false, 42)]);
  });

  test('relais du lecteur en WebDAV : un seul client, connexion réutilisée', () async {
    final relay = MediaRelay(WebDavConfig(url: server.url, user: 'moi', password: 'secret'));
    final url = await relay.urlFor('/Films/Mon Film (2024).mkv');
    final http = HttpClient();
    Future<(int, List<int>)> get(String range) async {
      final request = await http.getUrl(url);
      request.headers.set('Range', range);
      final response = await request.close();
      return (response.statusCode, await response.expand((c) => c).toList());
    }

    for (final start in [0, 50000, 99000, 10]) {
      final (status, body) = await get('bytes=$start-${start + 9}');
      expect(status, 206);
      expect(body, movie.sublist(start, start + 10));
    }
    // Une vérification de l'accès et une taille, puis seulement des GET.
    expect(server.requests.where((r) => r.startsWith('PROPFIND')), hasLength(2));
    expect(server.clientPorts, hasLength(1), reason: 'keep-alive : une seule connexion');
    http.close();
    await relay.close();
  });

  test('parcours en WebDAV : sous-dossiers lus en parallèle', () async {
    final dav = client();
    final audio = <MediaFile>[];
    final found = await scanFolders(dav, ['/'], audio: audio);
    expect({for (final f in found) f.path},
        {'/Films/Mon Film (2024).mkv', '/Films/Série/S01E01.mkv'});
    expect([for (final f in audio) f.path], ['/Musique/a.flac']);
    await dav.close();
  });
}
