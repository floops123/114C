import 'dart:io';

import 'package:c411_remote/api/ftp.dart';
import 'package:c411_remote/api/media_relay.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/media_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  final movie = List.generate(50000, (i) => i % 251);
  setUp(() {
    dir = Directory.systemTemp.createTempSync('c411local');
    File('${dir.path}/Films/Mon Film (2024).mkv')
      ..createSync(recursive: true)
      ..writeAsBytesSync(movie);
    File('${dir.path}/Films/Série/S01E01.mkv')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('dossier local : listes, tailles, lecture, écriture', () async {
    final files = openRemoteFiles(LocalConfig(dir.path));
    await files.connect();
    expect([for (final e in await files.list('/')) (e.name, e.isDir)], [('Films', true)]);
    expect({for (final e in await files.list('/Films')) e.name: (e.isDir, e.size)},
        {'Mon Film (2024).mkv': (false, 50000), 'Série': (true, 0)});
    expect(await files.size('/Films/Mon Film (2024).mkv'), 50000);
    expect(await files.size('/absent.mkv'), isNull);
    final tail = await (await files.read('/Films/Mon Film (2024).mkv', offset: 49990))
        .expand((c) => c)
        .toList();
    expect(tail, movie.sublist(49990));

    await files.makeDirs('/Envois/Pack');
    await files.write('/Envois/Pack/a.txt', Stream.value([104, 105]));
    expect(File('${dir.path}/Envois/Pack/a.txt').readAsStringSync(), 'hi');

    expect(() => files.size('/../etc/passwd'), throwsA(isA<RemoteFilesException>()),
        reason: 'pas de sortie du dossier');
    await expectLater(openRemoteFiles(LocalConfig('${dir.path}/absent')).connect(),
        throwsA(isA<RemoteFilesException>()));
  });

  test('dossier local : réglages, parcours et lecteur', () async {
    final settings = AppSettings(filesProtocol: 'local', localRoot: dir.path);
    expect(settings.hasFiles, isTrue);
    final config = filesConfigOf(settings);
    expect((config as LocalConfig).root, dir.path);
    expect((filesConfigFromJson({'filesProtocol': 'local', 'localRoot': '/mnt/x'}) as LocalConfig).root,
        '/mnt/x');

    final found = await scanFolders(openRemoteFiles(config), ['/']);
    expect({for (final f in found) f.path}, {'/Films/Mon Film (2024).mkv', '/Films/Série/S01E01.mkv'});

    final relay = MediaRelay(config);
    final url = await relay.urlFor('/Films/Mon Film (2024).mkv');
    final http = HttpClient();
    final req = await http.getUrl(url)..headers.set('Range', 'bytes=100-109');
    final res = await req.close();
    expect(res.statusCode, 206);
    expect(await res.expand((c) => c).toList(), movie.sublist(100, 110));
    http.close();
    await relay.close();
  });
}
