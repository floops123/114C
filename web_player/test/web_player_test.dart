import 'dart:convert';
import 'dart:io';

import 'package:c411_core/votes.dart';
import 'package:c411_core/ftp.dart';
import 'package:c411_core/local_files.dart';
import 'package:c411_core/media_relay.dart';
import 'package:c411_core/webdav.dart';
import 'package:c411_web_player/config.dart';
import 'package:c411_web_player/library.dart';
import 'package:c411_web_player/server.dart';
import 'package:c411_web_player/transcode.dart';
import 'package:test/test.dart';

import '../../test/fake_ftp.dart';

/// Préférences de l'application, comme sur le disque : la base est une
/// chaîne JSON sous la clé `mediaLibrary`.
String _prefs(Map<String, Object?> library) =>
    jsonEncode({'themeMode': 'dark', 'mediaLibrary': jsonEncode(library)});

final _library = {
  'files': [
    {'path': '/t/VisionQuest.S01E04.Malware.MULTi.1080p.DSNP.WEB.H264-BYOR.mkv', 'size': 1900 << 20, 'added': '2026-10-20T10:00:00.000'},
    // Épisode court : gardé dès 100 Mo.
    {'path': '/t/VisionQuest.S01E03.MULTi.1080p.WEB.H265-GL0P.mkv', 'size': 211 << 20, 'added': '2026-10-21T10:00:00.000'},
    {'path': '/t/Dune.Part.Two.2024.1080p.mkv', 'size': 7 << 30},
    {'path': '/t/Dune.Deuxieme.Partie.2024.MULTi.2160p.mkv', 'size': 9 << 30},
    {'path': '/t/Inconnu.1999.720p.avi', 'size': 700 << 20},
    // Vidéo de jeu (3 Mo) : ni film ni épisode.
    {'path': '/t/vectrex/videos/Mine Storm-video.mp4', 'size': 3 << 20},
  ],
  'tmdb': {
    'tv:visionquest': {'id': 1, 'type': 'tv', 'title': 'VisionQuest', 'overview': 'Vision…', 'posterUrl': 'https://image/p.jpg', 'rating': 7.5, 'date': '2026-10-01'},
    'movie:dune part two:2024': {'id': 2, 'type': 'movie', 'title': 'Dune : Deuxième partie', 'date': '2024-02-28'},
    'movie:dune deuxieme partie:2024': {'id': 2, 'type': 'movie', 'title': 'Dune : Deuxième partie', 'date': '2024-02-28'},
    'movie:inconnu:1999': null,
  },
};

void main() {
  group('Catalog', () {
    test('regroupe comme l’application : séries, deux noms pour une fiche',
        () {
      final catalog = Catalog.parse(_prefs(_library));
      final byTitle = {for (final t in catalog.titles) t.title: t};
      expect(byTitle.keys, unorderedEquals(['VisionQuest', 'Dune : Deuxième partie', 'Inconnu']));

      final vq = byTitle['VisionQuest']!;
      expect(vq.series, isTrue);
      expect([for (final f in vq.files) f.guess.episode], [3, 4], reason: 'triés');
      expect(vq.year, 2026);
      expect(vq.poster, 'https://image/p.jpg');
      expect(vq.added, DateTime.parse('2026-10-21T10:00:00.000'));

      expect(byTitle['Dune : Deuxième partie']!.files, hasLength(2));
      expect(byTitle['Inconnu']!.series, isFalse);
      expect(byTitle['Inconnu']!.year, 1999);
    });

    test('trop petits pour un film ou un épisode : écartés', () {
      final catalog = Catalog.parse(_prefs(_library));
      final names = [for (final t in catalog.titles) for (final f in t.files) f.name];
      expect(names, isNot(contains('Mine Storm-video.mp4')));
      expect(names, contains('VisionQuest.S01E03.MULTi.1080p.WEB.H265-GL0P.mkv'));
    });

    test('identifiants stables, fichier retrouvé par identifiant', () {
      final a = Catalog.parse(_prefs(_library));
      final b = Catalog.parse(_prefs(_library));
      final id = a.titles.first.files.first.id;
      expect(id, hasLength(16));
      expect(b.file(id)?.path, a.titles.first.files.first.path);
    });

    test('accepte aussi un export de la base seule', () {
      expect(Catalog.parse(jsonEncode(_library)).titles, hasLength(3));
    });

    test('JSON : pas de chemin FTP exposé', () {
      final json = jsonEncode(Catalog.parse(_prefs(_library)).toJson());
      expect(json, isNot(contains('/t/')));
      expect(json, contains('VisionQuest.S01E03'));
    });
  });

  group('WebConfig', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('c411web'));
    tearDown(() => dir.deleteSync(recursive: true));

    File write(Map<String, Object?> json) =>
        File('${dir.path}/r.json')..writeAsStringSync(jsonEncode(json));

    test('réglages de l’application, section web et options', () {
      final file = write({
        'ftpHost': 'ftp.example', 'ftpPort': 2121, 'ftpUser': 'moi',
        'ftpPassword': 's', 'ftpTls': false, 'tmdbKey': 'k',
        'web': {'port': 9000, 'password': 'pw', 'library': '/lib.json'},
      });
      final c = WebConfig.load(file.path, overrides: {'host': '0.0.0.0'});
      final ftp = c.files as FtpConfig;
      expect((ftp.host, ftp.port, ftp.user, ftp.tls), ('ftp.example', 2121, 'moi', false));
      expect((c.port, c.password, c.library, c.host), (9000, 'pw', '/lib.json', '0.0.0.0'));
      expect(c.public, isTrue);
      expect(WebConfig.load(file.path).public, isFalse, reason: 'local par défaut');
    });

    test('WebDAV choisi dans les réglages', () {
      final c = WebConfig.load(write({
        'ftpHost': 'ftp.example', 'filesProtocol': 'webdav',
        'webdavUrl': 'https://dav.example/', 'webdavUser': 'moi', 'webdavPassword': 's',
      }).path);
      final dav = c.files as WebDavConfig;
      expect((dav.url, dav.user, dav.password), ('https://dav.example/', 'moi', 's'));
      // Sans filesProtocol : déduit de ce qui est rempli.
      expect(WebConfig.load(write({'webdavUrl': 'https://dav.example/'}).path).files,
          isA<WebDavConfig>());
      expect(WebConfig.load(write({'ftpHost': '', 'localRoot': '/mnt/x'}).path).files,
          isA<LocalConfig>());
      expect(WebConfig.load(write({'ftpHost': 'ftp.example', 'webdavUrl': 'https://d/'}).path).files,
          isA<FtpConfig>(), reason: 'FTP renseigné : comme avant');
      expect(() => WebConfig.load(write({'filesProtocol': 'webdav'}).path),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('webdavUrl'))));
    });

    test('sans hôte FTP : erreur claire', () {
      expect(() => WebConfig.load(write({'ftpUser': 'x'}).path),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('ftpHost'))));
    });
  });

  group('MediaInfo', () {
    Map<String, Object?> probeJson(String format, List<Map<String, Object?>> streams) =>
        {'format': {'format_name': format, 'duration': '3600.5'}, 'streams': streams};

    test('MKV H.265, DTS : converti ; piste française choisie', () {
      final info = MediaInfo.parse(jsonEncode(probeJson('matroska,webm', [
        {'index': 0, 'codec_type': 'video', 'codec_name': 'hevc', 'pix_fmt': 'yuv420p10le', 'width': 3840},
        {'index': 1, 'codec_type': 'audio', 'codec_name': 'dts', 'channels': 6, 'tags': {'language': 'eng'}},
        {'index': 2, 'codec_type': 'audio', 'codec_name': 'eac3', 'channels': 6, 'tags': {'language': 'fre', 'title': 'VFF'}},
      ])));
      expect(info.direct, isFalse);
      expect(info.duration, 3600.5);
      expect(info.preferredAudio?.index, 2);
      final args = info.ffmpegArgs('http://relay/x.mkv', start: 90);
      expect(args.join(' '), allOf(
        contains('-ss 90.00 -i http://relay/x.mkv'),
        contains('-map 0:v:0 -map 0:2'),
        contains('-c:v libx264'),
        contains('-vf scale=1920:-2'),
        contains('-c:a aac -ac 2'),
        contains('frag_keyframe+empty_moov'),
      ));
      expect(info.ffmpegArgs('u', audioIndex: 1).join(' '), contains('-map 0:1'));
    });

    test('MKV H.264 8 bits : vidéo copiée, audio converti', () {
      final info = MediaInfo.parse(jsonEncode(probeJson('matroska,webm', [
        {'index': 0, 'codec_type': 'video', 'codec_name': 'h264', 'pix_fmt': 'yuv420p', 'width': 1920},
        {'index': 1, 'codec_type': 'audio', 'codec_name': 'ac3', 'channels': 6},
      ])));
      expect(info.direct, isFalse);
      final args = info.ffmpegArgs('u').join(' ');
      expect(args, contains('-c:v copy'));
      expect(args, contains('-c:a aac'));
      // Vidéo copiée : départ de l'image clé pour les deux pistes (sinon le
      // son se décale), +0,2 s pour que ffmpeg ne recule pas d'une image clé.
      expect(info.ffmpegArgs('u', start: 600).join(' '), contains('-noaccurate_seek -ss 600.200 -i u'));
      expect(info.copiesVideo(), isTrue);
    });

    test('image clé avant t : lue dans la sortie de ffprobe', () {
      const csv = '9.960,__\n10.000,K_\n10.040,__\n15.480,__\n20.000,K_\n';
      expect(parseKeyframeBefore(csv, 15.5), 10.0);
      expect(parseKeyframeBefore(csv, 20.0), 20.0, reason: 'image clé pile à t');
      expect(parseKeyframeBefore(csv, 9.99), isNull);
      expect(parseKeyframeBefore('', 5), isNull);
    });

    test('codecs décrits pour que le navigateur tranche', () {
      final info = MediaInfo.parse(jsonEncode(probeJson('matroska,webm', [
        {'index': 0, 'codec_type': 'video', 'codec_name': 'hevc', 'profile': 'Main 10', 'level': 150, 'pix_fmt': 'yuv420p10le'},
        {'index': 1, 'codec_type': 'audio', 'codec_name': 'eac3', 'channels': 6, 'tags': {'language': 'eng'}},
        {'index': 2, 'codec_type': 'audio', 'codec_name': 'aac', 'channels': 2, 'tags': {'language': 'fre'}, 'disposition': {'default': 1}},
      ])));
      expect(info.videoMime, 'video/mp4; codecs="hvc1.2.4.L150.B0"');
      expect(info.browserAudio?.index, 2, reason: 'la piste marquée par défaut');
      expect(info.audio.map((a) => a.mime),
          ['audio/mp4; codecs="ec-3"', 'audio/mp4; codecs="mp4a.40.2"']);
      // Le navigateur décode le H.265 : vidéo copiée (étiquette hvc1).
      final copied = info.ffmpegArgs('u', copyVideo: true).join(' ');
      expect(copied, contains('-c:v copy -tag:v hvc1'));
      expect(copied, isNot(contains('libx264')));
      expect(info.ffmpegArgs('u').join(' '), contains('libx264'));

      final h264 = MediaInfo.parse(jsonEncode(probeJson('matroska,webm', [
        {'index': 0, 'codec_type': 'video', 'codec_name': 'h264', 'profile': 'High', 'level': 41, 'pix_fmt': 'yuv420p'},
        {'index': 1, 'codec_type': 'audio', 'codec_name': 'dts', 'channels': 6},
      ])));
      expect(h264.videoMime, 'video/mp4; codecs="avc1.640029"');
      expect(h264.audio.single.mime, isNull, reason: 'aucun navigateur ne lit le DTS');
    });

    test('MP4 H.264 AAC : lu tel quel', () {
      final info = MediaInfo.parse(jsonEncode(probeJson('mov,mp4,m4a,3gp,3g2,mj2', [
        {'index': 0, 'codec_type': 'video', 'codec_name': 'h264', 'pix_fmt': 'yuv420p'},
        {'index': 1, 'codec_type': 'audio', 'codec_name': 'aac', 'channels': 2},
      ])));
      expect(info.direct, isTrue);
    });
  });

  group('serveur', () {
    late FakeFtpServer ftp;
    late Directory dir;
    late WebPlayerServer server;
    late HttpClient http;
    late Uri base;
    late Catalog catalog;
    final content = List.generate(50000, (i) => i % 251);

    Future<void> start({String password = '', bool transcode = false,
        Future<MediaInfo> Function(String)? probe, String ffmpeg = 'ffmpeg',
        Future<double> Function(String, double)? keyframe,
        Map<String, List<int>>? files, bool votes = false}) async {
      ftp = await FakeFtpServer.start(files ?? {for (final f in _library['files'] as List) (f as Map)['path'] as String: content});
      dir = Directory.systemTemp.createTempSync('c411web');
      final lib = File('${dir.path}/prefs.json')..writeAsStringSync(_prefs(_library));
      final config = WebConfig(
        files: FtpConfig(host: '127.0.0.1', port: ftp.port, user: 'moi', password: 'secret', tls: false),
        library: lib.path,
        port: 0,
        password: password,
      );
      server = WebPlayerServer(
        config,
        catalog: CatalogSource(lib.path),
        relay: MediaRelay(config.files),
        publicDir: 'public',
        canTranscode: transcode,
        probe: probe,
        keyframe: keyframe,
        ffmpeg: ffmpeg,
        votes: votes ? Votes('${dir.path}/votes/votes.json') : null,
      );
      final http0 = await server.start();
      base = Uri.parse('http://127.0.0.1:${http0.port}/');
      http = HttpClient();
      catalog = Catalog.parse(_prefs(_library));
    }

    tearDown(() async {
      http.close(force: true);
      await server.close();
      await ftp.close();
      dir.deleteSync(recursive: true);
    });

    Future<(int, HttpHeaders, List<int>)> get(String path,
        {String? range, String? auth}) async {
      final request = await http.getUrl(base.resolve(path));
      if (range != null) request.headers.set('Range', range);
      if (auth != null) request.headers.set('Authorization', 'Basic ${base64.encode(utf8.encode(auth))}');
      final response = await request.close();
      final body = await response.expand((c) => c).toList();
      return (response.statusCode, response.headers, body);
    }

    String fileId(String name) => catalog.titles
        .expand((t) => t.files)
        .firstWhere((f) => f.name.startsWith(name))
        .id;

    test('interface et catalogue', () async {
      await start();
      final (status, headers, body) = await get('');
      expect(status, 200);
      expect(headers.contentType?.mimeType, 'text/html');
      expect(utf8.decode(body), contains('<script src="app.js">'));
      final (s2, _, json) = await get('api/library');
      expect(s2, 200);
      expect((jsonDecode(utf8.decode(json)) as Map)['titles'], hasLength(3));
      expect((await get('../pubspec.yaml')).$1, 404);
      expect((await get('api/play/inconnu')).$1, 404);
    });

    test('mot de passe : refusé sans, accepté avec', () async {
      await start(password: 'secret');
      final (s, h, _) = await get('api/library');
      expect(s, 401);
      expect(h.value('www-authenticate'), contains('Basic'));
      expect((await get('api/library', auth: 'qui:faux')).$1, 401);
      expect((await get('api/library', auth: 'qui:secret')).$1, 200);
    });

    Future<List<Object?>> vote(String id, Object? body, {String? user = 'alice', String type = 'application/json'}) async {
      final request = await http.postUrl(base.resolve('api/vote/$id'));
      if (user != null) request.headers.set('Remote-User', user);
      request.headers.set('Content-Type', type);
      request.write(body is String ? body : jsonEncode(body));
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      return [response.statusCode, jsonDecode(text)];
    }

    Future<Map> votesOf(String? user) async {
      final request = await http.getUrl(base.resolve('api/votes'));
      if (user != null) request.headers.set('Remote-User', user);
      return jsonDecode(await utf8.decodeStream(await request.close())) as Map;
    }

    test('votes : anonymes, un par membre, retirables, gardés sur disque', () async {
      await start(votes: true);
      final id = catalog.titles.first.id;
      expect(await vote(id, {'value': 1}), [200, [1, 0, 1]]);
      expect(await vote(id, {'value': -1}, user: 'bob'), [200, [1, 1, -1]]);
      expect(await vote(id, {'value': -1}), [200, [0, 2, -1]], reason: 'alice change d’avis');
      expect((await votesOf('bob'))['items'], {id: [0, 2, -1]});
      expect(await votesOf(null), {'user': false, 'items': {id: [0, 2, 0]}});
      expect(await vote(id, {'value': 0}, user: 'bob'), [200, [0, 1, 0]], reason: 'vote retiré');
      // Refus : sans membre, sans JSON, élément inconnu, valeur absurde
      expect((await vote(id, {'value': 1}, user: null))[0], 403);
      expect((await vote(id, 'value=1', type: 'application/x-www-form-urlencoded'))[0], 415);
      expect((await vote('inconnu', {'value': 1}))[0], 404);
      expect((await vote(id, {'value': 5}))[0], 400);
      // Sur disque : des empreintes, aucun nom ; relu au redémarrage
      final saved = File('${dir.path}/votes/votes.json').readAsStringSync();
      expect(saved, isNot(contains('alice')));
      expect(Votes('${dir.path}/votes/votes.json').tally(id, 'alice'), [0, 1, -1]);
      expect(Votes('${dir.path}/votes/votes.json').tally(id, 'carol'), [0, 1, 0]);
    });

    Future<Object?> favoritesOf(String? user) async {
      final request = await http.getUrl(base.resolve('api/favorites'));
      if (user != null) request.headers.set('Remote-User', user);
      return jsonDecode(await utf8.decodeStream(await request.close()));
    }

    test('favoris : ce que le membre a aimé, plus récent en tête', () async {
      await start(votes: true);
      final [a, b, c, ...] = [for (final t in catalog.titles) t.id];
      await vote(a, {'value': 1});
      await vote(b, {'value': 1});
      await vote(c, {'value': -1});
      expect(await favoritesOf('alice'), {'user': true, 'items': [b, a]}, reason: '« je n’aime pas » n’en fait pas partie');
      await vote(a, {'value': -1});
      await vote(a, {'value': 1});
      expect((await favoritesOf('alice') as Map)['items'], [a, b], reason: 'aimé à nouveau : remis en tête');
      await vote(b, {'value': 0});
      expect((await favoritesOf('alice') as Map)['items'], [a]);
      expect(await favoritesOf('bob'), {'user': true, 'items': []}, reason: 'chacun les siens');
      expect(await favoritesOf(null), {'user': false, 'items': []});
      expect(Votes('${dir.path}/votes/votes.json').liked('alice'), [a], reason: 'gardés sur disque');
    });

    test('votes : ancien format relu, ses « j’aime » deviennent des favoris', () async {
      await start(); // le tearDown du groupe arrête un serveur
      final d = Directory.systemTemp.createTempSync('votes');
      final old = Votes('${d.path}/v.json')..vote('x', 'alice', 1);
      // Réécrit à l'ancien format : les votes seuls.
      final saved = jsonDecode(File('${d.path}/v.json').readAsStringSync()) as Map;
      File('${d.path}/v.json').writeAsStringSync(jsonEncode(saved['votes']));
      expect(old.liked('alice'), ['x']);
      final again = Votes('${d.path}/v.json');
      expect(again.tally('x', 'alice'), [1, 0, 1]);
      expect(again.liked('alice'), ['x']);
      d.deleteSync(recursive: true);
    });

    test('lecture directe : le fichier par le FTP, avec Range', () async {
      await start();
      final id = fileId('Inconnu');
      final (status, headers, body) = await get('media/$id', range: 'bytes=100-199');
      expect(status, 206);
      expect(headers.value('content-range'), 'bytes 100-199/50000');
      expect(body, content.sublist(100, 200));
    });

    test('lecture : direct ou converti selon ffprobe', () async {
      await start(transcode: true, probe: (_) async => MediaInfo.parse(jsonEncode({
            'format': {'format_name': 'matroska,webm', 'duration': '60'},
            'streams': [
              {'index': 0, 'codec_type': 'video', 'codec_name': 'hevc'},
              {'index': 1, 'codec_type': 'audio', 'codec_name': 'aac', 'channels': 2},
            ],
          })));
      final id = fileId('VisionQuest.S01E03');
      final (_, _, body) = await get('api/play/$id');
      final play = jsonDecode(utf8.decode(body)) as Map;
      expect(play['mode'], 'stream');
      expect(play['url'], '/stream/$id');
      expect(play['directUrl'], '/media/$id');
      expect(play['streamUrl'], '/stream/$id');
      expect(play['duration'], 60);
    });

    test('flux converti : ffmpeg lancé sur le relais, depuis t', () async {
      // Faux ffmpeg : renvoie ses arguments.
      final script = File('${Directory.systemTemp.path}/fake_ffmpeg_$pid.sh')
        ..writeAsStringSync('#!/bin/sh\necho "\$@"\n');
      await Process.run('chmod', ['+x', script.path]);
      addTearDown(script.deleteSync);
      await start(
        transcode: true,
        ffmpeg: script.path,
        probe: (_) async => const MediaInfo(container: 'matroska,webm', duration: 60, videoCodec: 'hevc'),
      );
      final id = fileId('VisionQuest.S01E03');
      final (status, headers, body) = await get('stream/$id?t=42');
      expect(status, 200);
      expect(headers.contentType?.mimeType, 'video/mp4');
      final args = utf8.decode(body);
      expect(args, contains('-ss 42.00 -i http://127.0.0.1:'));
      expect(args, contains('VisionQuest.S01E03.MULTi.1080p.WEB.H265-GL0P.mkv'));
      expect(args, contains('libx264'));
      // Le navigateur a dit décoder la vidéo : copiée.
      final (_, _, copied) = await get('stream/$id?t=0&copy=1');
      expect(utf8.decode(copied), contains('-c:v copy -tag:v hvc1'));
    });

    test('image clé : seulement quand la vidéo sera copiée', () async {
      final asked = <double>[];
      await start(
        transcode: true,
        probe: (_) async => const MediaInfo(container: 'matroska,webm', duration: 60, videoCodec: 'hevc'),
        keyframe: (_, t) async {
          asked.add(t);
          return 10;
        },
      );
      final id = fileId('VisionQuest.S01E03');
      Future<Object?> at(String query) async =>
          (jsonDecode(utf8.decode((await get('api/keyframe/$id?$query')).$3)) as Map)['t'];
      expect(await at('t=15.5&copy=1'), 10, reason: 'H.265 copié : image clé');
      expect(await at('t=15.5'), 15.5, reason: 'réencodé : recherche précise');
      expect(await at('t=0&copy=1'), 0);
      expect(asked, [15.5]);
    });

    test('bout à bout, vrai ffmpeg : son et image synchrones après une reprise',
        () async {
      // MKV témoin : H.264 avec une image clé toutes les 10 s, E-AC3 ; un
      // flash blanc et un bip au début de chaque seconde.
      final sample = '${Directory.systemTemp.path}/c411sync_$pid.mkv';
      final made = await Process.run('ffmpeg', [
        '-y', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'color=c=black:s=160x120:r=25:d=30,format=yuv420p,'
            "geq=lum='if(eq(mod(N\\,25)\\,0)\\,235\\,16)':cb=128:cr=128",
        '-f', 'lavfi', '-i', "aevalsrc='if(lt(mod(t\\,1)\\,0.05)\\,0.8*sin(2*PI*1000*t)\\,0)':s=48000:d=30",
        '-c:v', 'libx264', '-g', '250', '-keyint_min', '250', '-sc_threshold', '0',
        '-c:a', 'eac3', sample,
      ]);
      expect(made.exitCode, 0, reason: '${made.stderr}');
      addTearDown(() => File(sample).deleteSync());
      await start(transcode: true, files: {
        '/t/VisionQuest.S01E03.MULTi.1080p.WEB.H265-GL0P.mkv': File(sample).readAsBytesSync(),
      });
      final id = fileId('VisionQuest.S01E03');

      // Reprise à 15,5 s : la conversion part de l'image clé de 10 s.
      final (_, _, kfBody) = await get('api/keyframe/$id?t=15.5&copy=1');
      final kf = (jsonDecode(utf8.decode(kfBody)) as Map)['t'] as num;
      expect(kf, closeTo(10, 0.01));

      final (status, _, mp4) = await get('stream/$id?t=$kf&copy=1');
      expect(status, 200);
      final out = '${Directory.systemTemp.path}/c411sync_$pid.mp4';
      File(out).writeAsBytesSync(mp4);
      addTearDown(() => File(out).deleteSync());

      // Pas de trou au début de la piste audio (le bug : 5,5 s de vide).
      final audio = await Process.run('ffprobe', ['-v', 'error', '-select_streams', 'a',
        '-show_entries', 'packet=pts_time', '-of', 'csv=p=0', out]);
      final pts = const LineSplitter().convert(audio.stdout as String).take(20).map(double.parse).toList();
      for (var i = 1; i < pts.length; i++) {
        expect(pts[i] - pts[i - 1], lessThan(0.1), reason: 'audio continu : $pts');
      }

      // Premier flash et premier bip au même instant.
      final video = await Process.run('ffprobe', ['-v', 'error', '-f', 'lavfi',
        'movie=$out,signalstats', '-show_entries', 'frame=pts_time:frame_tags=lavfi.signalstats.YAVG',
        '-of', 'csv=p=0']);
      final flash = const LineSplitter().convert(video.stdout as String)
          .map((l) => l.split(',')).where((c) => c.length > 1 && double.parse(c[1]) > 120)
          .map((c) => double.parse(c[0])).first;
      final sound = await Process.run('ffprobe', ['-v', 'error', '-f', 'lavfi',
        'amovie=$out,asetnsamples=480,astats=metadata=1:reset=1',
        '-show_entries', 'frame=pts_time:frame_tags=lavfi.astats.Overall.RMS_level', '-of', 'csv=p=0']);
      final beep = const LineSplitter().convert(sound.stdout as String)
          .map((l) => l.split(',')).where((c) => c.length > 1 && c[1] != '-inf' && double.parse(c[1]) > -30)
          .map((c) => double.parse(c[0])).first;
      expect((beep - flash).abs(), lessThan(0.1), reason: 'flash à $flash s, bip à $beep s');
    }, skip: Process.runSync('which', ['ffmpeg']).exitCode != 0 ? 'ffmpeg absent' : false,
        timeout: const Timeout(Duration(minutes: 2)));

    test('bout à bout avec le vrai ffmpeg : MKV H.265 à deux pistes audio',
        () async {
      // Petit MKV de 3 s : H.265 10 bits, audio anglais (AC3) puis français
      // (AC3), comme beaucoup de sorties.
      final sample = '${Directory.systemTemp.path}/c411web_$pid.mkv';
      final made = await Process.run('ffmpeg', [
        '-y', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=24:duration=3',
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3',
        '-f', 'lavfi', '-i', 'sine=frequency=880:duration=3',
        '-map', '0', '-map', '1', '-map', '2',
        '-c:v', 'libx265', '-pix_fmt', 'yuv420p10le', '-x265-params', 'log-level=error',
        '-c:a', 'ac3', '-ac', '6',
        '-metadata:s:a:0', 'language=eng', '-metadata:s:a:1', 'language=fre',
        sample,
      ]);
      expect(made.exitCode, 0, reason: '${made.stderr}');
      addTearDown(() => File(sample).deleteSync());
      final bytes = File(sample).readAsBytesSync();
      await start(transcode: true, files: {
        '/t/VisionQuest.S01E03.MULTi.1080p.WEB.H265-GL0P.mkv': bytes,
      });
      final id = fileId('VisionQuest.S01E03');

      final (_, _, playBody) = await get('api/play/$id');
      final play = jsonDecode(utf8.decode(playBody)) as Map;
      expect(play['mode'], 'stream');
      expect(play['video'], 'hevc');
      expect((play['duration'] as num).round(), 3);
      expect(play['preferredAudio'], 2, reason: 'la piste française');

      final (status, _, mp4) = await get('stream/$id?t=1');
      expect(status, 200);
      expect(mp4.length, greaterThan(1000));
      expect(ascii.decode(mp4.sublist(4, 8)), 'ftyp', reason: 'MP4 lisible');

      // Vidéo copiée (navigateur qui décode le H.265) : MP4 aussi.
      final (copyStatus, _, copied) = await get('stream/$id?t=0&copy=1');
      expect(copyStatus, 200);
      expect(ascii.decode(copied.sublist(4, 8)), 'ftyp');
      expect(utf8.decode(copied, allowMalformed: true), contains('hvc1'),
          reason: 'H.265 copié tel quel, étiqueté hvc1');
    }, skip: Process.runSync('which', ['ffmpeg']).exitCode != 0 ? 'ffmpeg absent' : false,
        timeout: const Timeout(Duration(minutes: 2)));
  });
}
