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
}
