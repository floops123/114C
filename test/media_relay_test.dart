import 'dart:io';

import 'package:c411_remote/api/ftp.dart';
import 'package:c411_remote/api/media_relay.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ftp.dart';

void main() {
  test('plages demandées par le lecteur', () {
    expect(MediaRelay.parseRange(null, 100), (0, 99));
    expect(MediaRelay.parseRange('bytes=10-', 100), (10, 99));
    expect(MediaRelay.parseRange('bytes=10-19', 100), (10, 19));
    expect(MediaRelay.parseRange('bytes=-10', 100), (90, 99));
    expect(MediaRelay.parseRange('bytes=50-500', 100), (50, 99));
    expect(MediaRelay.parseRange('bytes=100-', 100), isNull);
  });

  test('relais HTTP local vers le FTPS, avec Range', () async {
    final content = List.generate(100000, (i) => i % 251);
    final server = await FakeFtpServer.start(
        {'/films/Mon Film (2024).mkv': content}, tls: true);
    final relay = MediaRelay(FtpConfig(
        host: '127.0.0.1', port: server.port, user: 'moi', password: 'secret'));
    final url = await relay.urlFor('/films/Mon Film (2024).mkv');
    expect(url.host, '127.0.0.1');
    expect(url.pathSegments.last, 'Mon Film (2024).mkv');

    final http = HttpClient();
    Future<(int, Map<String, String>, List<int>)> get([String? range]) async {
      final request = await http.getUrl(url);
      if (range != null) request.headers.set('Range', range);
      final response = await request.close();
      final body = await response.expand((c) => c).toList();
      return (
        response.statusCode,
        {
          'type': response.headers.contentType?.mimeType ?? '',
          'range': response.headers.value('content-range') ?? '',
          'length': '${response.contentLength}',
        },
        body,
      );
    }

    final (status, headers, body) = await get();
    expect(status, 200);
    expect(headers['type'], 'video/x-matroska');
    expect(body, content);

    final (status2, headers2, body2) = await get('bytes=50000-50009');
    expect(status2, 206);
    expect(headers2['range'], 'bytes 50000-50009/100000');
    expect(body2, content.sublist(50000, 50010));

    final (status3, _, _) = await get('bytes=200000-');
    expect(status3, 416);

    http.close();
    await relay.close();
    await server.close();
  });

  // Descripteurs : le lecteur abandonne une lecture à chaque saut dans la
  // vidéo, et une connexion peut être refusée. Rien ne doit rester ouvert
  // (sinon « Trop de fichiers ouverts » au bout d'un moment).
  test('ni lecture abandonnée ni connexion refusée ne laisse de socket ouverte',
      () async {
    int fds() => Directory('/proc/self/fd').listSync().length;
    final server = await FakeFtpServer.start(
        {'/f.mkv': List.filled(4 << 20, 7)}, tls: true);
    final config = FtpConfig(
        host: '127.0.0.1', port: server.port, user: 'moi', password: 'secret');
    final relay = MediaRelay(config);
    final url = await relay.urlFor('/f.mkv');
    final http = HttpClient();
    Future<void> seek() async {
      final request = await http.getUrl(url);
      request.headers.set('Range', 'bytes=1000-');
      final response = await request.close();
      await response.first;
      (await response.detachSocket()).destroy();
    }

    await seek();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final before = fds();
    for (var i = 0; i < 20; i++) {
      await seek();
    }
    for (var i = 0; i < 20; i++) {
      await expectLater(
          FtpClient(FtpConfig(
                  host: '127.0.0.1', port: server.port, user: 'moi', password: 'faux'))
              .connect(),
          throwsA(isA<FtpException>()));
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(fds(), lessThanOrEqualTo(before + 2));

    http.close(force: true);
    await relay.close();
    await server.close();
  }, skip: !Directory('/proc/self/fd').existsSync());
}
