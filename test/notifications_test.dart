import 'dart:convert';

import 'package:c411_remote/api/c411_socket.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/notifications.dart';
import 'package:c411_remote/ui/notifications_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trames réelles du WebSocket C411 (pseudos, messages et identifiants
/// anonymisés).
const _frames = [
  '42["channel:message",{"id":851814,"tempId":"temp-1","channelId":135,"space":"public","classSlug":"swarm_keeper","sender":{"id":1001,"username":"MembreA","avatar":"/uploads/avatars/1001-md.webp","role":"user","isEarlyAdopter":false,"certificationBadge":null,"nameTone":"bronze"},"content":"Premier message","isSystem":false,"createdAt":"2026-10-17T04:20:16.543Z","replyTo":null,"isFirstEver":false}]',
  '42["channel:message",{"id":851814,"tempId":"temp-1","channelId":135,"space":"public","classSlug":"swarm_keeper","sender":{"id":1001,"username":"MembreA","avatar":"/uploads/avatars/1001-md.webp","role":"user","isEarlyAdopter":false,"certificationBadge":null,"nameTone":"bronze"},"content":"Premier message","isSystem":false,"createdAt":"2026-10-17T04:20:16.543Z","replyTo":null,"isFirstEver":false}]',
  '42["unread:update",{"privateMessages":0,"channelMessages":0,"pendingRequests":0,"staffMessages":0,"hasPublicUnread":true,"hasStaffUnread":false,"hasTeamUnread":false,"total":0}]',
  '42["channel:message",{"id":851810,"tempId":"temp-2","channelId":135,"space":"public","classSlug":"swarm_keeper","sender":{"id":1002,"username":"MembreB","avatar":null,"role":"user","isEarlyAdopter":false,"certificationBadge":{"type":"in_progress","label":"Novice","color":"#F59E0B","icon":"i-heroicons-book-open","categoryName":"Ebook","tierSlug":"novice"},"nameTone":"bronze"},"content":"Second message","isSystem":false,"createdAt":"2026-10-17T04:19:45.048Z","replyTo":null,"isFirstEver":false}]',
  '42["channel:viewers",{"channelId":135,"count":33}]',
  '42["channel:typing",{"channelId":135,"userId":1003,"username":"MembreC","isTyping":false}]',
  '42["channel:typing",{"channelId":135,"userId":1004,"username":"MembreD","isTyping":true}]',
  '42["stats:update",{"user_id":1,"uploaded":235381622681,"downloaded":512830663080,"upload_credit":177167400960}]',
  '42["unread:update",{"privateMessages":0,"channelMessages":0,"pendingRequests":0,"staffMessages":0,"hasPublicUnread":true,"hasStaffUnread":false,"hasTeamUnread":false,"total":0}]',
  '42["stats:update",{"user_id":1,"uploaded":235382889396,"downloaded":512830663080,"upload_credit":177167400960}]',
];

SocketEvent _event(String frame) {
  final list = jsonDecode(frame.substring(2)) as List;
  return SocketEvent(list.first as String, list.skip(1).toList(), DateTime.now());
}

class _NoSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

/// Comme connecté, mais sans WebSocket.
class _Connected extends NotificationsNotifier {
  @override
  NotificationsState build() => const NotificationsState(
      configured: true, status: SocketStatus.connected);
}

ProviderContainer _container() {
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith(_NoSettings.new),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('aiguillage des événements réels', () {
    final container = _container();
    final notifier = container.read(notificationsProvider.notifier);
    notifier.joinChannel(135);
    _frames.map(_event).forEach(notifier.handle);
    final s = container.read(notificationsProvider);

    // Salon : doublon ignoré, badge et avatar absolu.
    expect(s.chat.map((m) => m.content), ['Premier message', 'Second message']);
    expect(s.chat.first.avatarUrl,
        'https://c411.org/uploads/avatars/1001-md.webp');
    expect(s.chat.last.badge, 'Novice');
    expect(s.chat.last.badgeColor, 0xFFF59E0B);
    expect(s.viewers, {135: 33});
    expect(s.typing.keys, ['MembreD']);

    // Compte : dernière valeur reçue.
    expect(s.account!.uploaded, 235382889396);
    expect(s.account!.uploadCredit, 177167400960);

    // Compteurs à zéro, aucun événement inconnu : pas de notification.
    expect(s.counters!.total, 0);
    expect(s.items, isEmpty);
    expect(s.unread, 0);
  });

  test('une hausse de compteur devient une notification', () {
    final container = _container();
    final notifier = container.read(notificationsProvider.notifier);
    String unread(int pm, int req) => '42["unread:update",{"privateMessages":$pm,'
        '"channelMessages":0,"pendingRequests":$req,"staffMessages":0,'
        '"total":${pm + req}}]';
    notifier.handle(_event(unread(0, 0)));
    notifier.handle(_event(unread(2, 0)));
    notifier.handle(_event(unread(2, 1)));
    notifier.handle(_event(unread(1, 1))); // une lecture : rien de nouveau
    final s = container.read(notificationsProvider);
    expect(s.items.map((n) => (n.title, n.body)), [
      ('Nouvelle demande en attente', '1 non lu'),
      ('Nouveau message privé', '2 non lus'),
    ]);
    expect(s.unread, 2);
  });

  testWidgets('écran : compte, compteurs, salon', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      notificationsProvider.overrideWith(_Connected.new),
    ]);
    addTearDown(container.dispose);
    // Sans avatar réseau dans le test d'interface.
    final frames = [
      for (final f in _frames)
        f.replaceAll('"/uploads/avatars/1001-md.webp"', 'null'),
      '42["unread:update",{"privateMessages":3,"channelMessages":0,'
          '"pendingRequests":0,"staffMessages":0,"total":3}]',
    ];
    final notifier = container.read(notificationsProvider.notifier);
    notifier.joinChannel(135);
    frames.map(_event).forEach(notifier.handle);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.dark]),
        home: const NotificationsPage(),
      ),
    ));
    await tester.pump();

    expect(find.text('Connecté'), findsOneWidget);
    expect(find.text('MON COMPTE · EN DIRECT'), findsOneWidget);
    expect(find.text('Messages privés : 3'), findsOneWidget);
    expect(find.text('Nouveau message privé'), findsOneWidget);
    expect(find.text('Notifications (1)'), findsOneWidget);

    await tester.tap(find.text('Salon · 33 en ligne'));
    await tester.pump();
    expect(find.text('Premier message'), findsOneWidget);
    expect(find.text('Novice'), findsOneWidget);
    expect(find.text('MembreD écrit…'), findsOneWidget);

    // Changer de salon : les messages du salon 135 disparaissent.
    await tester.tap(find.text('Général'));
    await tester.pump();
    expect(find.text('Premier message'), findsNothing);
    expect(container.read(notificationsProvider).channelId, 1);
  });

  test('changements de salon et texte encodé en HTML', () {
    final container = _container();
    final notifier = container.read(notificationsProvider.notifier);
    for (final f in [
      '42["channel:leave",{"channelId":135}]',
      '42["channel:join",{"channelId":3}]',
      '42["channel:leave",{"channelId":3}]',
      '42["channel:join",{"channelId":26}]',
      '42["channel:message",{"id":851858,"channelId":1,"space":"public",'
          '"sender":{"id":1005,"username":"MembreE","avatar":null},'
          '"content":"Oui c&#x27;est marrant &amp; &quot;drôle&quot; &#128514;",'
          '"isSystem":false,"createdAt":"2026-10-17T04:29:10.522Z","replyTo":null}]',
    ]) {
      notifier.handle(_event(f));
    }
    final s = container.read(notificationsProvider);
    expect(s.items, isEmpty, reason: 'join/leave ne sont pas des notifications');
    expect(s.channels, {1, 3, 26, 135});
    expect(s.chat.single.content, 'Oui c\'est marrant & "drôle" 😂');
  });
}
