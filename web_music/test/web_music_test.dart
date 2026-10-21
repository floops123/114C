import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:c411_core/ftp.dart';
import 'package:c411_core/media_relay.dart';
import 'package:c411_core/music_name.dart';
import 'package:c411_web_music/config.dart';
import 'package:c411_web_music/library.dart';
import 'package:c411_web_music/musicbrainz.dart';
import 'package:c411_web_music/scanner.dart';
import 'package:c411_web_music/server.dart';
import 'package:c411_web_music/service.dart';
import 'package:test/test.dart';

const _mo = 1024 * 1024;

void main() {
  group('noms', () {
    AlbumGuess album(String dir) => AlbumGuess.parse(dir);

    test('dossier « Artiste - Album (année) [format] »', () {
      final a = album('/musique/Daft Punk - Random Access Memories (2013) [FLAC 24-96]');
      expect((a.artist, a.title, a.year), ('Daft Punk', 'Random Access Memories', 2013));
    });

    test('artiste dans le dossier parent', () {
      final a = album('/musique/Daft Punk/2001 - Discovery');
      expect((a.artist, a.title, a.year), ('Daft Punk', 'Discovery', 2001));
      final b = album('/musique/Air/Moon Safari (1998)');
      expect((b.artist, b.title, b.year), ('Air', 'Moon Safari', 1998));
      // Un dossier générique n'est pas un artiste.
      final c = album('/torrents/Moon Safari');
      expect((c.artist, c.title), (null, 'Moon Safari'));
    });

    test('nom de scène', () {
      final a = album('/torrents/Daft_Punk-Random_Access_Memories-(88883716861)-WEB-2013-GRP');
      expect((a.artist, a.title, a.year), ('Daft Punk', 'Random Access Memories', 2013));
      final b = album('/torrents/Justice-Hyperdrama-WEB-FLAC-2024-ENRiCH');
      expect((b.artist, b.title, b.year), ('Justice', 'Hyperdrama', 2024));
    });

    test('année en tête, format en fin, édition gardée', () {
      final a = album('/m/Radiohead - 1997 - OK Computer FLAC');
      expect((a.artist, a.title, a.year), ('Radiohead', 'OK Computer', 1997));
      final b = album('/m/Stromae - Multitude (Deluxe Edition) [24bit]');
      expect(b.title, 'Multitude (Deluxe Edition)');
    });

    test('sous-dossiers de disques', () {
      expect(albumDirOf('/m/Pink Floyd - The Wall/CD2/01 - Hey You.flac'), '/m/Pink Floyd - The Wall');
      expect(albumDirOf('/m/Album/Disc 1/01.mp3'), '/m/Album');
      expect(TrackGuess.parse('/m/Pink Floyd - The Wall/CD2/01 - Hey You.flac').disc, 2);
    });

    test('pistes', () {
      TrackGuess t(String name) => TrackGuess.parse('/m/a/$name');
      expect((t('03 - Giorgio by Moroder.flac').number, t('03 - Giorgio by Moroder.flac').title),
          (3, 'Giorgio by Moroder'));
      final withArtist = t('05. Daft Punk - Get Lucky.mp3');
      expect((withArtist.number, withArtist.artist, withArtist.title), (5, 'Daft Punk', 'Get Lucky'));
      final disc = t('2-07 Interlude.m4a');
      expect((disc.disc, disc.number, disc.title), (2, 7, 'Interlude'));
      final three = t('104 Fin.flac');
      expect((three.disc, three.number), (1, 4));
      final scene = t('01-daft_punk-give_life_back_to_music-grp.flac');
      expect((scene.number, scene.title), (1, 'give life back to music'));
      expect(t('Sans numéro.ogg').number, isNull);
    });

    test('fichiers audio', () {
      expect(isAudioPath('/a/b.FLAC'), isTrue);
      expect(isAudioPath('/a/b.mkv'), isFalse);
      expect(isAudioPath('/a/b.webm'), isFalse);
    });
  });

  group('parcours', () {
    test('torrents : la musique, pas la bande-son d’un jeu', () {
      final audio = musicOfTorrents([
        {
          'hashString': 'AAA',
          'downloadDir': '/data/torrents',
          'percentDone': 1,
          'files': [
            {'name': 'Air - Moon Safari/01 - La Femme d\'Argent.flac', 'length': 40 * _mo},
            {'name': 'Air - Moon Safari/02 - Sexy Boy.flac', 'length': 30 * _mo},
            {'name': 'Air - Moon Safari/cover.jpg', 'length': 2 * _mo},
            {'name': 'Air - Moon Safari/jingle.mp3', 'length': 100 * 1024},
          ],
        },
        {
          'hashString': 'BBB',
          'downloadDir': '/data/torrents',
          'percentDone': 1,
          'files': [
            {'name': 'Jeu/data.pak', 'length': 4000 * _mo},
            {'name': 'Jeu/OST/01.ogg', 'length': 5 * _mo},
          ],
        },
        {
          'hashString': 'CCC',
          'downloadDir': '/data/torrents',
          'percentDone': 0.4,
          'files': [
            {'name': 'Pas fini/01.mp3', 'length': 8 * _mo},
          ],
        },
      ]);
      expect([for (final a in audio) a.path], [
        '/data/torrents/Air - Moon Safari/01 - La Femme d\'Argent.flac',
        '/data/torrents/Air - Moon Safari/02 - Sexy Boy.flac',
      ]);
      expect(audio.first.hash, 'aaa');
    });

    test('dossiers : pas les bruitages', () {
      final files = [
        MusicFile(path: '/m/Album/01.mp3', size: 8 * _mo),
        MusicFile(path: '/m/Album/02.mp3', size: 9 * _mo),
        for (var i = 0; i < 150; i++) MusicFile(path: '/jeux/sfx/s$i.wav', size: 400 * 1024),
      ];
      expect({for (final f in plausibleAlbums(files)) f.albumDir}, {'/m/Album'});
    });

    test('dossiers du FTP, correspondance des chemins Transmission', () async {
      final ftp = _FakeFtp({
        '/musique': [const FtpEntry('Air', isDir: true)],
        '/musique/Air': [const FtpEntry('Moon Safari (1998)', isDir: true)],
        '/musique/Air/Moon Safari (1998)': [
          const FtpEntry('01 - La Femme d\'Argent.flac', isDir: false, size: 40 * _mo),
          const FtpEntry('02 - Sexy Boy.flac', isDir: false, size: 30 * _mo),
          const FtpEntry('folder.jpg', isDir: false, size: 200 * 1024),
        ],
      }, sizes: {
        '/torrents/Justice - Hyperdrama/01 - Generator.flac': 30 * _mo,
      });
      final rpc = await _FakeTransmission.start([
        {
          'hashString': 'abc',
          'downloadDir': '/APPBOX_DATA/torrents',
          'percentDone': 1,
          'files': [
            {'name': 'Justice - Hyperdrama/01 - Generator.flac', 'length': 30 * _mo},
          ],
        },
      ]);
      addTearDown(rpc.close);
      final config = _config(folders: ['/musique'], rpcUrl: rpc.url);
      final scanner = Scanner(config, connect: () async => ftp);
      addTearDown(scanner.close);
      final result = await scanner.scan(MusicLibrary());
      expect(result.warning, isNull);
      expect(result.library.pathFrom, '/APPBOX_DATA');
      expect(result.library.pathTo, '');
      expect({for (final f in result.library.files) f.path}, {
        '/torrents/Justice - Hyperdrama/01 - Generator.flac',
        '/musique/Air/Moon Safari (1998)/01 - La Femme d\'Argent.flac',
        '/musique/Air/Moon Safari (1998)/02 - Sexy Boy.flac',
      });
      expect(result.library.files.first.hash, 'abc');
      expect(ftp.closed, isTrue);

      // Un second parcours garde la date d'ajout.
      final again = await scanner.scan(result.library);
      expect(again.library.files.first.added, result.library.files.first.added);
    });
  });

  group('MusicBrainz', () {
    test('choix de la parution', () {
      const guess = AlbumGuess(artist: 'Air', title: 'Moon Safari', year: 1998);
      final id = MusicBrainz.pick([
        {'id': 'autre', 'score': 100, 'title': 'Moon Safari Remixes', 'track-count': 5},
        {'id': 'japon', 'score': 100, 'title': 'Moon Safari', 'track-count': 12, 'date': '1998-03-16', 'status': 'Official'},
        {'id': 'bon', 'score': 98, 'title': 'Moon Safari', 'track-count': 10, 'date': '1998-01-16', 'status': 'Official'},
        {'id': 'sans', 'score': 40, 'title': 'Moon Safari', 'track-count': 10},
      ], guess, trackCount: 10);
      expect(id, 'bon', reason: 'le nombre de pistes départage');
      expect(MusicBrainz.pick([{'id': 'x', 'score': 95, 'title': 'Talkie Walkie'}], guess, trackCount: 10),
          isNull, reason: 'titre différent');
    });

    test('recherche puis fiche, User-Agent, genres du groupe', () async {
      final seen = <Uri>[];
      final agents = <String?>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((r) async {
        seen.add(r.uri);
        agents.add(r.headers.value(HttpHeaders.userAgentHeader));
        final body = switch (r.uri.path) {
          '/ws/2/release' => {
              'releases': [
                {'id': 'rel', 'score': 100, 'title': 'Moon Safari', 'track-count': 2, 'status': 'Official'},
              ],
            },
          '/ws/2/release/rel' => _release,
          '/ws/2/release-group/grp' => {
              'genres': [
                {'name': 'downtempo', 'count': 3},
                {'name': 'electronic', 'count': 9},
              ],
            },
          _ => null,
        };
        r.response.statusCode = body == null ? 404 : 200;
        r.response.write(jsonEncode(body));
        await r.response.close();
      });
      final mb = MusicBrainz(
        contact: 'test@example.org',
        base: 'http://127.0.0.1:${server.port}/ws/2',
        interval: Duration.zero,
      );
      addTearDown(mb.close);
      final release = await mb.find(const AlbumGuess(artist: 'Air', title: 'Moon Safari'), trackCount: 2);
      expect(release, isNotNull);
      expect(seen.first.queryParameters['query'], 'release:"Moon Safari" AND artist:"Air"');
      expect(seen.first.queryParameters['fmt'], 'json');
      expect(agents.every((a) => a == 'C411Music/1.0 ( test@example.org )'), isTrue);
      expect(release!.artist, 'Air');
      expect(release.artistName, 'Air');
      expect(release.year, 1998);
      expect(release.label, 'Source');
      expect(release.genres, ['electronic', 'downtempo']);
      expect(release.coverUrl, 'https://coverartarchive.org/release/rel/front-500');
      expect([for (final t in release.tracks) (t.disc, t.position, t.title, t.length)], [
        (1, 1, 'La Femme d’argent', 427000),
        (1, 2, 'Sexy Boy', 298000),
      ]);
      expect(release.tracks[1].artist, isNull, reason: 'même artiste que l’album');
    });
  });

  test('MusicBrainz saturé : nouvel essai', () async {
    var calls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((r) async {
      calls++;
      r.response.statusCode = calls < 3 ? 503 : 200;
      r.response.write(jsonEncode(_release));
      await r.response.close();
    });
    final mb = MusicBrainz(
        contact: 't', base: 'http://127.0.0.1:${server.port}/ws/2',
        interval: Duration.zero, backoff: Duration.zero);
    addTearDown(mb.close);
    expect((await mb.release('rel'))?.title, 'Moon Safari');
    expect(calls, 4, reason: '2 refus, la fiche, puis les genres du groupe');
    calls = -10; // Toujours saturé.
    await expectLater(mb.release('rel'), throwsA(isA<MusicBrainzBusy>()));
  });

  group('discothèque', () {
    test('pistes rattachées à la fiche : numéro, ordre, titre', () {
      final release = MusicBrainz.parseRelease(_release);
      final numbered = Album.match([
        MusicFile(path: '/m/Air/Moon Safari/02 - sexy boy.flac', size: 9 * _mo),
        MusicFile(path: '/m/Air/Moon Safari/01 - femme.flac', size: 9 * _mo),
      ], release);
      expect([for (final t in numbered) t.title], ['La Femme d’argent', 'Sexy Boy']);
      expect(numbered.first.toJson()['duration'], 427);

      final byTitle = Album.match([
        MusicFile(path: '/m/Air/Moon Safari/Sexy Boy.flac', size: 9 * _mo),
        MusicFile(path: '/m/Air/Moon Safari/bonus.flac', size: 9 * _mo),
        MusicFile(path: '/m/Air/Moon Safari/autre.flac', size: 9 * _mo),
      ], release);
      expect([for (final t in byTitle) (t.title, t.number)],
          [('Sexy Boy', 2), ('autre', null), ('bonus', null)]);
    });

    test('numéros continus sur deux disques', () {
      final release = MbRelease(id: 'r', title: 'Double', artist: 'X', tracks: [
        for (var d = 1; d <= 2; d++)
          for (var p = 1; p <= 2; p++) MbTrack(disc: d, position: p, title: 'D$d-P$p'),
      ]);
      final tracks = Album.match([
        for (var n = 1; n <= 4; n++) MusicFile(path: '/m/X - Double/0$n.flac', size: 9 * _mo),
      ], release);
      expect([for (final t in tracks) t.title], ['D1-P1', 'D1-P2', 'D2-P1', 'D2-P2']);
    });

    test('albums, artistes, enregistrement', () {
      final dir = Directory.systemTemp.createTempSync('c411_music');
      addTearDown(() => dir.deleteSync(recursive: true));
      final library = MusicLibrary(
        files: [
          MusicFile(path: '/m/Air/Moon Safari/01 - a.flac', size: 9 * _mo, added: DateTime(2026, 1, 2)),
          MusicFile(path: '/m/Air/Talkie Walkie/01 - b.flac', size: 9 * _mo),
          MusicFile(path: '/m/Justice - Cross/CD1/01 - c.mp3', size: 9 * _mo),
          MusicFile(path: '/m/Justice - Cross/CD2/01 - d.mp3', size: 9 * _mo),
        ],
        mb: {'/m/Air/Moon Safari': MbMatch(checked: DateTime(2026), release: MusicBrainz.parseRelease(_release))},
      );
      library.write('${dir.path}/sub/library.json');
      final back = MusicLibrary.read('${dir.path}/sub/library.json');
      expect(back.files.first.added, DateTime(2026, 1, 2));
      expect(back.mb['/m/Air/Moon Safari']!.release!.tracks, hasLength(2));

      final catalog = Catalog.of(back);
      expect(catalog.albums.map((a) => a.title), ['Cross', 'Moon Safari', 'Talkie Walkie']);
      final cross = catalog.albums.first;
      expect(cross.artist, 'Justice');
      expect([for (final t in cross.tracks) t.disc], [1, 2]);
      final json = catalog.toJson();
      final artists = {for (final a in json['artists'] as List) (a as Map)['name']: (a['albums'] as List).length};
      // « Talkie Walkie », non reconnu, rejoint l'« Air » de MusicBrainz.
      expect(artists, {'Justice': 1, 'Air': 2});
      final air = (json['artists'] as List).cast<Map>().firstWhere((a) => a['name'] == 'Air');
      expect(air['mbid'], 'air-id');
    });

    test('recherche infructueuse refaite au bout d’une semaine', () {
      expect(MbMatch(checked: DateTime.now()).stale, isFalse);
      expect(MbMatch(checked: DateTime.now().subtract(const Duration(days: 8))).stale, isTrue);
    });
  });

  group('serveur', () {
    late MusicServer server;
    late MusicService service;
    late Directory dir;
    late Uri base;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('c411_music');
      MusicLibrary(
        files: [MusicFile(path: '/m/Air/Moon Safari/01 - femme.flac', size: 9 * _mo)],
        mb: {'/m/Air/Moon Safari': MbMatch(checked: DateTime(2026), release: MusicBrainz.parseRelease(_release))},
      ).write('${dir.path}/library.json');
      final config = _config(password: 'secret', port: 0);
      service = MusicService(
        statePath: '${dir.path}/library.json',
        scanner: Scanner(config, connect: () async => _FakeFtp({})),
        musicBrainz: MusicBrainz(contact: 'test', interval: Duration.zero),
      );
      File('${dir.path}/index.html').writeAsStringSync('<title>C411 Music</title>');
      server = MusicServer(config,
          service: service,
          relay: MediaRelay(config.ftp),
          publicDir: dir.path,
          canTranscode: false);
      final http = await server.start();
      base = Uri.parse('http://127.0.0.1:${http.port}');
    });

    tearDown(() async {
      await server.close();
      service.close();
      dir.deleteSync(recursive: true);
    });

    Future<(int, String, HttpHeaders)> get(String path, {bool auth = true, String method = 'GET'}) async {
      final client = HttpClient();
      try {
        final request = await client.openUrl(method, base.resolve(path));
        request.followRedirects = false;
        if (auth) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Basic ${base64.encode(utf8.encode('x:secret'))}');
        }
        final reply = await request.close();
        return (reply.statusCode, await reply.transform(utf8.decoder).join(), reply.headers);
      } finally {
        client.close(force: true);
      }
    }

    test('mot de passe exigé', () async {
      expect((await get('/', auth: false)).$1, 401);
      expect((await get('/')).$2, contains('C411 Music'));
    });

    test('discothèque, pochette, lecture', () async {
      final (status, body, _) = await get('/api/library');
      expect(status, 200);
      final json = jsonDecode(body) as Map;
      final album = (json['albums'] as List).single as Map;
      expect((album['title'], album['artist'], album['year'], album['cover']), ('Moon Safari', 'Air', 1998, true));
      final track = (album['tracks'] as List).single as Map;
      expect(track['title'], 'La Femme d’argent');
      expect(json['status'], containsPair('albums', 1));
      // Aucun chemin du FTP dans la réponse.
      expect(body, isNot(contains('/m/Air')));

      // Pochette déjà dans le cache : servie sans aller sur le réseau.
      final cached = File(MusicServer.coverPath(
          '${dir.path}/library.json', 'https://coverartarchive.org/release/rel/front-500'))
        ..createSync(recursive: true)
        ..writeAsStringSync('JPEG');
      expect(cached.path, startsWith('${dir.path}/covers/'));
      final (coverStatus, coverBody, headers) = await get('/api/cover/${album['id']}');
      expect((coverStatus, coverBody), (200, 'JPEG'));
      expect(headers.contentType?.mimeType, 'image/jpeg');
      expect((await get('/api/cover/inconnu')).$1, 404);

      final play = jsonDecode((await get('/api/play/${track['id']}')).$2) as Map;
      expect(play, {'type': 'audio/flac', 'directUrl': '/media/${track['id']}', 'streamUrl': null, 'duration': 427.0});
      expect((await get('/api/play/inconnu')).$1, 404);
      expect((await get('/api/scan')).$1, 404, reason: 'GET : simple fichier introuvable');
      expect((await get('/api/scan', method: 'POST')).$1, 202);
    });
  });

  test('arguments ffmpeg', () {
    expect(MusicServer.ffmpegArgs('http://x/a.wma', start: 12.5),
        containsAllInOrder(['-ss', '12.50', '-i', 'http://x/a.wma', '-c:a', 'aac', '-f', 'adts', 'pipe:1']));
  });

  test('réglages', () {
    final dir = Directory.systemTemp.createTempSync('c411_music');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/personal.json')
      ..writeAsStringSync(jsonEncode({
        'ftpHost': 'ftp.example.org',
        'rpcUrl': 'seedbox:9091',
        'mediaFolders': ['/films'],
        'music': {'folders': ['/musique'], 'port': 9000, 'scanEvery': 0},
      }));
    final c = MusicConfig.load(file.path, overrides: {'folder': '/extra'});
    expect(c.rpcUrl, 'http://seedbox:9091/transmission/rpc');
    expect(c.folders, ['/extra', '/musique', '/films']);
    expect((c.port, c.scanEvery, c.public), (9000, Duration.zero, false));
  });
}

MusicConfig _config({List<String> folders = const [], String rpcUrl = '', String password = '', int port = 8412}) =>
    MusicConfig(
      ftp: const FtpConfig(host: 'ftp.invalid', port: 21, user: 'u', password: 'p', tls: false),
      state: '/nonexistent',
      folders: folders,
      rpcUrl: rpcUrl,
      appLibrary: '/nonexistent',
      password: password,
      port: port,
    );

final _release = <String, dynamic>{
  'id': 'rel',
  'title': 'Moon Safari',
  'date': '1998-01-16',
  'country': 'FR',
  'artist-credit': [
    {'name': 'Air', 'joinphrase': '', 'artist': {'id': 'air-id', 'name': 'Air'}},
  ],
  'release-group': {'id': 'grp', 'primary-type': 'Album', 'first-release-date': '1998-01-16'},
  'label-info': [
    {'label': {'name': 'Source'}},
  ],
  'cover-art-archive': {'front': true},
  'genres': <Object>[],
  'media': [
    {
      'position': 1,
      'tracks': [
        {
          'position': 1,
          'title': 'La Femme d’argent',
          'length': 427000,
          'artist-credit': [
            {'name': 'Air', 'artist': {'id': 'air-id', 'name': 'Air'}},
          ],
        },
        {'position': 2, 'title': 'Sexy Boy', 'recording': {'length': 298000}},
      ],
    },
  ],
};

class _FakeFtp implements FtpClient {
  _FakeFtp(this.dirs, {this.sizes = const {}});
  final Map<String, List<FtpEntry>> dirs;
  final Map<String, int> sizes;
  bool closed = false;

  @override
  Future<List<FtpEntry>> list(String path) async =>
      dirs[path] ?? (throw const FtpException('550 introuvable'));

  @override
  Future<int?> size(String path) async => sizes[path];

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransmission {
  _FakeTransmission(this._server);
  final HttpServer _server;
  String get url => 'http://127.0.0.1:${_server.port}/transmission/rpc';

  static Future<_FakeTransmission> start(List<Map<String, dynamic>> torrents) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      await r.drain<void>();
      // Premier appel sans jeton : 409, comme Transmission.
      if (r.headers.value('X-Transmission-Session-Id') != 'jeton') {
        r.response
          ..statusCode = 409
          ..headers.set('X-Transmission-Session-Id', 'jeton');
      } else {
        r.response.write(jsonEncode({
          'result': 'success',
          'arguments': {'torrents': torrents},
        }));
      }
      await r.response.close();
    });
    return _FakeTransmission(server);
  }

  Future<void> close() => _server.close(force: true);
}
