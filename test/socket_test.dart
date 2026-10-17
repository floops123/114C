import 'dart:async';
import 'dart:io';

import 'package:c411_remote/api/c411_socket.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faux serveur Socket.IO reproduisant les échanges observés sur c411.org.
Future<(HttpServer, List<String>, List<Map<String, String?>>)> _server(
    {required bool acceptSession}) async {
  final received = <String>[];
  final headers = <Map<String, String?>>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    headers.add({
      'origin': req.headers.value('origin'),
      'cookie': req.headers.value('cookie'),
    });
    final ws = await WebSocketTransformer.upgrade(req);
    ws.add('0{"sid":"abc","upgrades":[],"pingInterval":25000,'
        '"pingTimeout":60000,"maxPayload":131072}');
    ws.listen((m) {
      received.add('$m');
      if (m == '40') {
        if (!acceptSession) {
          ws.add('44{"message":"Session not found",'
              '"data":{"code":"no_session_cookie"}}');
          return;
        }
        ws.add('40{"sid":"xyz"}');
        ws.add('2'); // ping
        ws.add('42["notification",{"title":"Nouveau message",'
            '"message":"Bob vous a écrit","id":7}]');
        ws.add('42/autre,12["ignore-ns",{"a":1}]');
      }
    });
  });
  return (server, received, headers);
}

void main() {
  test('connexion, pong, événements et en-têtes envoyés', () async {
    final (server, received, headers) = await _server(acceptSession: true);
    final events = <SocketEvent>[];
    final connected = Completer<void>();
    final socket = C411Socket(
      'a=1; b=2',
      url: Uri.parse('ws://127.0.0.1:${server.port}/ws/?EIO=4&transport=websocket'),
      onStatus: (s) {
        if (s == SocketStatus.connected && !connected.isCompleted) {
          connected.complete();
        }
      },
      onEvent: events.add,
    );
    await socket.connect();
    await connected.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    socket.emit('channel:join', {'channelId': 1});
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(headers.single, {'origin': 'https://c411.org', 'cookie': 'a=1; b=2'});
    expect(received, ['40', '3', '42["channel:join",{"channelId":1}]']);
    expect(events.map((e) => e.name), ['notification', 'ignore-ns']);
    expect((events.first.data as Map)['title'], 'Nouveau message');

    await socket.close();
    await server.close(force: true);
  });

  test('session refusée : statut dédié, pas de nouvelle tentative', () async {
    final (server, _, headers) = await _server(acceptSession: false);
    final statuses = <SocketStatus>[];
    String? error;
    final socket = C411Socket(
      'x=y',
      url: Uri.parse('ws://127.0.0.1:${server.port}/ws/'),
      onStatus: statuses.add,
      onError: (e) => error = e,
    );
    await socket.connect();
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(statuses.last, SocketStatus.unauthorized);
    expect(error, contains('no_session_cookie'));
    expect(headers, hasLength(1), reason: 'aucune reconnexion');
    await socket.close();
    await server.close(force: true);
  });

  test('nettoyage du cookie collé', () {
    expect(normalizeCookie('Cookie: a=1; b=2'), 'a=1; b=2');
    expect(normalizeCookie(' a=1;\n b=2 ;; '), 'a=1; b=2');
    expect(normalizeCookie('pas un cookie'), '');
  });

}
