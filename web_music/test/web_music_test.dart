import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:c411_core/ftp.dart';
import 'package:c411_core/media_relay.dart';
import 'package:c411_core/music_name.dart';
import 'package:c411_web_music/config.dart';
import 'package:c411_web_music/library.dart';
import 'package:c411_web_music/musicbrainz.dart';
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

  group('ce qui est de la musique', () {
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
      final files = <AudioFile>[
        (path: '/m/Album/01.mp3', size: 8 * _mo, hash: null),
        (path: '/m/Album/02.mp3', size: 9 * _mo, hash: null),
        (path: '/m/Album/jingle.mp3', size: 100 * 1024, hash: null),
        for (var i = 0; i < 150; i++) (path: '/jeux/sfx/s$i.wav', size: 400 * 1024, hash: null),
      ];
      expect([for (final f in plausibleAlbums(files)) f.path], ['/m/Album/01.mp3', '/m/Album/02.mp3']);
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
      library.writeMb('${dir.path}/sub/library.json');
      final mb = MusicLibrary.readMb('${dir.path}/sub/library.json');
      expect(mb['/m/Air/Moon Safari']!.release!.tracks, hasLength(2));
      final back = library.copyWith(mb: mb);

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

    test('base de l’application relue quand elle change', () async {
      final dir = Directory.systemTemp.createTempSync('c411_music');
      addTearDown(() => dir.deleteSync(recursive: true));
      final prefs = '${dir.path}/prefs.json';
      MusicLibrary(mb: {
        '/m/Air/Moon Safari': MbMatch(checked: DateTime.now(), release: MusicBrainz.parseRelease(_release)),
        '/m/Inconnu': MbMatch(checked: DateTime.now()),
      }).writeMb('${dir.path}/state.json');
      _writeApp(prefs, [
        {'path': '/m/Air/Moon Safari/01 - femme.flac', 'size': 9 * _mo},
      ]);
      final service = MusicService(
        appLibrary: prefs,
        statePath: '${dir.path}/state.json',
        musicBrainz: MusicBrainz(contact: 't', base: 'http://127.0.0.1:9/ws/2', interval: Duration.zero),
      );
      addTearDown(service.close);
      expect(service.refresh(), isTrue);
      expect(service.refresh(), isFalse, reason: 'inchangée');
      expect(service.catalog.albums.single.title, 'Moon Safari');
      expect(service.status()['scannedAt'], '2026-10-20T08:00:00.000');

      // L'application a reparcouru : un album de plus (déjà cherché, en vain).
      _writeApp(prefs, [
        {'path': '/m/Air/Moon Safari/01 - femme.flac', 'size': 9 * _mo},
        {'path': '/m/Inconnu/01 - x.mp3', 'size': 9 * _mo},
      ], scannedAt: '2026-10-21T08:00:00.000');
      File(prefs).setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
      expect(service.refresh(), isTrue);
      expect(service.catalog.albums.map((a) => a.title), ['Inconnu', 'Moon Safari']);
      await service.identify();
      expect(service.error, isNull, reason: 'rien à chercher : aucune requête');
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
        mb: {'/m/Air/Moon Safari': MbMatch(checked: DateTime(2026), release: MusicBrainz.parseRelease(_release))},
      ).writeMb('${dir.path}/library.json');
      _writeApp('${dir.path}/prefs.json', [
        {'path': '/m/Air/Moon Safari/01 - femme.flac', 'size': 9 * _mo, 'added': '2026-10-01T10:00:00.000'},
      ]);
      final config = _config(password: 'secret', port: 0);
      service = MusicService(
        appLibrary: '${dir.path}/prefs.json',
        statePath: '${dir.path}/library.json',
        musicBrainz: MusicBrainz(contact: 'test', interval: Duration.zero),
      )..refresh();
      File('${dir.path}/index.html').writeAsStringSync('<title>C411 Music</title>');
      server = MusicServer(config,
          service: service,
          relay: MediaRelay(config.files),
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
      expect((await get('/api/scan', method: 'POST')).$1, 405, reason: 'le parcours est celui de l’application');
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
        'music': {'port': 9000, 'library': '/prefs.json', 'contact': 'moi@example.org'},
      }));
    final c = MusicConfig.load(file.path, overrides: {'state': '/etat.json'});
    expect((c.port, c.library, c.state, c.contact, c.public),
        (9000, '/prefs.json', '/etat.json', 'moi@example.org', false));
    expect(MusicConfig.load(file.path, overrides: {'host': '0.0.0.0'}).public, isTrue);
  });
}

MusicConfig _config({String password = '', int port = 8412}) => MusicConfig(
      files: const FtpConfig(host: 'ftp.invalid', port: 21, user: 'u', password: 'p', tls: false),
      library: '/nonexistent',
      state: '/nonexistent',
      password: password,
      port: port,
    );

/// Préférences de l'application, comme shared_preferences les écrit : la
/// base est une chaîne JSON.
void _writeApp(String path, List<Map<String, Object?>> music, {String scannedAt = '2026-10-20T08:00:00.000'}) =>
    File(path).writeAsStringSync(jsonEncode({
      'flutter.themeMode': 'dark',
      'flutter.mediaLibrary': jsonEncode({'files': [], 'music': music, 'scannedAt': scannedAt}),
    }));

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
