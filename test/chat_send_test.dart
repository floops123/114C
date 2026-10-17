import 'dart:convert';
import 'dart:io';

import 'package:c411_remote/api/c411_chat.dart';
import 'package:c411_remote/api/c411_socket.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _WithCookie extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings(sessionCookie: 'a=b');
}

/// Faux serveur : accuse réception de `channel:send` comme c411.org
/// (`42<n>[…]` → `43<n>[{success,messageId,tempId,status}]`), puis diffuse le
/// message. Le premier envoi est refusé si [refuseFirst].
Future<HttpServer> _server({bool refuseFirst = false}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var refused = !refuseFirst;
  server.listen((req) async {
    final ws = await WebSocketTransformer.upgrade(req);
    ws.add('0{"sid":"s","upgrades":[],"pingInterval":25000,"pingTimeout":60000}');
    ws.listen((m) {
      final frame = '$m';
      if (frame == '40') ws.add('40{"sid":"x"}');
      final send = RegExp(r'^42(\d+)(\[.*\])$').firstMatch(frame);
      if (send == null) return;
      final payload = (jsonDecode(send[2]!) as List)[1] as Map;
      if (!refused) {
        refused = true;
        ws.add('43${send[1]}[{"success":false,"error":"Mode lent"}]');
        return;
      }
      ws.add('43${send[1]}[${jsonEncode({
        'success': true,
        'messageId': 900,
        'tempId': payload['tempId'],
        'status': 'sent',
        'content': payload['content'],
      })}]');
      ws.add('42${jsonEncode(['channel:message', {
        'id': 900,
        'tempId': payload['tempId'],
        'channelId': payload['channelId'],
        'sender': {'id': 1, 'username': 'MonPseudo', 'avatar': null},
        'content': payload['content'],
        'isSystem': false,
        'createdAt': '2026-10-17T05:00:00.000Z',
      }])}');
    });
  });
  return server;
}

Future<ProviderContainer> _connected(HttpServer server) async {
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith(_WithCookie.new),
    socketUrlProvider.overrideWithValue(
        Uri.parse('ws://127.0.0.1:${server.port}/ws/')),
    chatApiProvider.overrideWithValue(null),
  ]);
  await container.read(settingsProvider.future);
  container.listen(notificationsProvider, (_, _) {});
  for (var i = 0; i < 50; i++) {
    if (container.read(notificationsProvider).status == SocketStatus.connected) {
      return container;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('pas de connexion au faux serveur');
}

void main() {
  test('envoi : affichage immédiat puis réconciliation par tempId', () async {
    final server = await _server();
    final container = await _connected(server);
    final n = container.read(notificationsProvider.notifier);

    final sending = n.sendMessage('  Bon week-end ;)  ');
    final pending = container.read(notificationsProvider).chat.single;
    expect(pending.sendState, SendState.pending);
    expect(pending.content, 'Bon week-end ;)');
    expect(pending.tempId, matches(RegExp(r'^temp-\d+-[a-z0-9]{9}$')));

    await sending;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sent = container.read(notificationsProvider).chat.single;
    expect((sent.id, sent.sendState, sent.username), (900, SendState.sent, 'MonPseudo'));

    container.dispose();
    await server.close(force: true);
  });

  test('envoi refusé puis « Réessayer »', () async {
    final server = await _server(refuseFirst: true);
    final container = await _connected(server);
    final n = container.read(notificationsProvider.notifier);

    await n.sendMessage('Salut');
    final failed = container.read(notificationsProvider).chat.single;
    expect((failed.sendState, failed.sendError), (SendState.failed, 'Mode lent'));

    await n.retry(failed);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final chat = container.read(notificationsProvider).chat;
    expect(chat, hasLength(1), reason: 'pas de doublon après la nouvelle tentative');
    expect((chat.single.id, chat.single.sendState), (900, SendState.sent));

    container.dispose();
    await server.close(force: true);
  });

  test('accusé de réception sans connexion : erreur immédiate', () async {
    final socket = C411Socket('a=b');
    expect(socket.emitWithAck('channel:send', {}), throwsA(isA<SocketException>()));
  });
}
