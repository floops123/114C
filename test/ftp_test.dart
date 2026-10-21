import 'dart:convert';

import 'package:c411_remote/api/ftp.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ftp.dart';

void main() {
  final files = {
    '/torrents/Film.2024.1080p.WEB-GRP.mkv': utf8.encode('0123456789'),
    '/torrents/Série.S01/Série.S01E01.mkv': utf8.encode('abc'),
  };

  for (final tls in [false, true]) {
    group(tls ? 'FTPS (TLS explicite)' : 'FTP', () {
      late FakeFtpServer server;
      setUp(() async => server = await FakeFtpServer.start({...files}, tls: tls));
      tearDown(() => server.close());

      FtpClient client({String password = 'secret'}) => FtpClient(FtpConfig(
          host: '127.0.0.1',
          port: server.port,
          user: 'moi',
          password: password,
          tls: tls));

      test('liste, taille et lecture à partir d’une position', () async {
        final ftp = client();
        await ftp.connect();
        final root = await ftp.list('/torrents');
        expect({for (final e in root) e.name: (e.isDir, e.size)}, {
          'Série.S01': (true, 4096),
          'Film.2024.1080p.WEB-GRP.mkv': (false, 10),
        });
        expect(await ftp.size('/torrents/Film.2024.1080p.WEB-GRP.mkv'), 10);
        expect(await ftp.size('/absent.mkv'), isNull);
        final stream =
            await ftp.read('/torrents/Film.2024.1080p.WEB-GRP.mkv', offset: 4);
        expect(utf8.decode(await stream.expand((c) => c).toList()), '456789');
        await ftp.close();
        if (tls) {
          expect(server.commands, containsAllInOrder(['AUTH TLS', 'PBSZ 0', 'PROT P']));
        }
      });

      test('envoi : dossiers créés, fichier écrit, progression', () async {
        final ftp = client();
        await ftp.connect();
        await ftp.makeDirs('/torrents/Nouveau/Sous');
        await ftp.makeDirs('/torrents/Nouveau'); // Existe déjà : sans erreur.
        final sent = <int>[];
        await ftp.write('/torrents/Nouveau/Sous/a.bin',
            Stream.fromIterable([utf8.encode('abc'), utf8.encode('defg')]),
            onProgress: sent.add);
        expect(utf8.decode(server.files['/torrents/Nouveau/Sous/a.bin']!), 'abcdefg');
        expect(sent, [3, 7]);
        expect(server.made, containsAll(['/torrents/Nouveau', '/torrents/Nouveau/Sous']));
        expect(await ftp.size('/torrents/Nouveau/Sous/a.bin'), 7);
        await ftp.close();
      });

      test('repli sur LIST sans MLSD', () async {
        server.noMlsd = true;
        final ftp = client();
        await ftp.connect();
        final entries = await ftp.list('/torrents/Série.S01');
        expect(entries.single.name, 'Série.S01E01.mkv');
        expect(entries.single.size, 3);
        await ftp.close();
      });

      test('identifiants refusés', () async {
        await expectLater(client(password: 'faux').connect(),
            throwsA(isA<FtpException>().having(
                (e) => e.message, 'message', 'Identifiants FTP refusés')));
      });
    });
  }
}
