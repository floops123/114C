import 'package:c411_remote/api/c411_chat.dart';
import 'package:c411_remote/api/c411_socket.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/notifications.dart';
import 'package:c411_remote/ui/notifications_page.dart';
import 'package:c411_remote/ui/rich_text.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _Connected extends NotificationsNotifier {
  @override
  NotificationsState build() => const NotificationsState(
      configured: true, status: SocketStatus.connected);
}

Map<String, dynamic> _site(int id, String type, String title, String message,
        String link, {bool read = false}) =>
    {
      'id': id,
      'type': type,
      'title': title,
      'message': message,
      'link': link,
      'data': {'k': id},
      'isRead': read,
      'createdAt': '2026-10-1${id % 10}T04:36:08.000Z',
    };

/// Faux site : 3 notifications en page 1 (dont 1 non lue), 1 en page 2 ;
/// [newest] ajoute une nouvelle non lue en tête.
class _FakeSite extends C411ChatApi {
  _FakeSite() : super('');
  bool newest = false;
  final offsets = <int>[];

  @override
  Future<({List<Map<String, dynamic>> items, bool hasMore, int unread})>
      notifications({int offset = 0, int perPage = 30}) async {
    offsets.add(offset);
    if (offset > 0) {
      return (
        items: [_site(1, 'ic_level_up', 'Niveau 17 atteint', '+2 Zen', '/community/my-rank', read: true)],
        hasMore: false,
        unread: 0,
      );
    }
    return (
      items: [
        if (newest) _site(6, 'ic_level_up', 'Niveau 19 atteint', '+2 Zen', '/community/my-rank'),
        _site(5, 'vtr_initialized', '18 torrents comptés', '18 torrents que vous seedez sont désormais comptés.', '/user/profile?tab=seeds'),
        _site(4, 'token_attribution', 'Versement Zen Journalier', '+6 Zen versés sur votre compte.', '/user/zens', read: true),
        _site(3, 'channel_reply', 'Nouvelle réponse', '4 nouvelles réponses dans #Swarm Keeper', '/messages?channel=135&space=public', read: true),
      ],
      hasMore: true,
      unread: newest ? 2 : 1,
    );
  }
}

/// Connecté sans WebSocket : seul le chargement des notifications compte.
class _Online extends NotificationsNotifier {
  @override
  NotificationsState build() {
    final (items, _) = ref.read(notificationStoreProvider).load();
    return NotificationsState(
        configured: true, status: SocketStatus.connected, items: items);
  }
}


void main() {
  group('mise en forme des messages', () {
    String render(List<InlineSpan> spans) => spans.map((s) => switch (s) {
          TextSpan(:final text, :final style) => switch (style) {
              TextStyle(fontWeight: FontWeight.w700) => '[b:$text]',
              TextStyle(fontStyle: FontStyle.italic) => '[i:$text]',
              TextStyle(decoration: TextDecoration.lineThrough) => '[s:$text]',
              TextStyle(fontFamily: 'monospace') => '[code:${text!.trim()}]',
              TextStyle(fontWeight: FontWeight.w600) => '[@:$text]',
              _ => text,
            },
          WidgetSpan() => '[lien]',
          _ => '?',
        }).join();

    test('gras, italique, barré, code, lien, mention', () {
      final spans = chatSpans(
          'Salut @MonPseudo, **lis** le *guide* ~~vite~~ `docker compose` : '
          'https://c411.org/guide/tokens#tous. 2*3*4 reste tel quel',
          colors: AppColors.dark,
          me: 'monpseudo');
      expect(
          render(spans),
          'Salut [@:@MonPseudo], [b:lis] le [i:guide] [s:vite] '
          '[code:docker compose] : [lien]. 2*3*4 reste tel quel');
    });

    test('mentions', () {
      expect(mentions('coucou @MonPseudo !', 'monpseudo'), isTrue);
      expect(mentions('mail@MonPseudo.fr', 'monpseudo'), isFalse);
      expect(mentions('coucou @Autre', 'monpseudo'), isFalse);
      expect(mentions('coucou', null), isFalse);
      // Format enregistré par le site : {{pseudo}}.
      expect(plainMentions('{{Zed}} vous a mentionné, {{x y}}'), '@Zed vous a mentionné, {{x y}}');
      expect(mentions('merci {{MonPseudo}} !', 'monpseudo'), isTrue);
      expect(render(chatSpans('merci {{MonPseudo}} et {{Autre}}',
              colors: AppColors.dark, me: 'monpseudo')),
          'merci [@:@MonPseudo] et [@:@Autre]');
      expect(render(chatSpans('{{pas une mention}}', colors: AppColors.dark)),
          '{{pas une mention}}');
    });
  });

  test('notifications du site : badge, nouvelles, cache hors ligne, pages', () async {
    final store = MemoryNotificationStore();
    final api = _FakeSite();
    ProviderContainer launch({required bool online}) {
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith(_NoSettings.new),
        notificationStoreProvider.overrideWithValue(store),
        if (online) notificationsProvider.overrideWith(_Online.new),
        chatApiProvider.overrideWithValue(online ? api : null),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    final first = launch(online: true);
    final n = first.read(notificationsProvider.notifier);
    await n.refreshNotifications();
    var s = first.read(notificationsProvider);
    expect(s.items.map((x) => x.id), [5, 4, 3]);
    expect(s.items.first.title, '18 torrents comptés');
    expect(s.unread, 1, reason: 'une seule non lue sur le site');
    expect(s.hasMore, isTrue);
    expect(s.arrivals, 0, reason: 'pas de bandeau au premier chargement');

    // Une nouvelle notification arrive sur le site.
    api.newest = true;
    await n.refreshNotifications();
    s = first.read(notificationsProvider);
    expect(s.items.first.id, 6);
    expect((s.arrivals, s.arrival), (1, 'Niveau 19 atteint'));
    expect(s.unread, 2);

    // Page suivante : offset = nombre déjà chargé.
    await n.loadMoreNotifications();
    s = first.read(notificationsProvider);
    expect(api.offsets, [0, 0, 4]);
    expect(s.items.last.id, 1);
    expect(s.hasMore, isFalse);

    // Vues dans l'application : le badge repart de zéro, même au lancement
    // suivant hors ligne (cache).
    n.markAllRead();
    first.dispose();
    final second = launch(online: false);
    s = second.read(notificationsProvider);
    expect(s.items.map((x) => x.id), [6, 5, 4, 3, 1]);
    expect(s.unread, 0);
    expect(s.items.first.isRead, isFalse, reason: 'état « lu » du site conservé');
  });

  test('cache : sérialisation d’une notification', () {
    final n = AppNotification.fromSite(_site(4, 'token_attribution',
        'Versement Zen Journalier', '+6 Zen versés', '/user/zens', read: true));
    final back = AppNotification.fromJson(n.toJson());
    expect((back.id, back.type, back.title, back.body, back.link, back.isRead),
        (4, 'token_attribution', 'Versement Zen Journalier', '+6 Zen versés',
            '/user/zens', true));
    expect(back.receivedAt, n.receivedAt);
    expect(back.raw, {'k': 4});
  });

  testWidgets('anciennes notifications : visibles hors ligne, paginées',
      (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryNotificationStore()
      ..save([
        for (var i = 0; i < 60; i++)
          AppNotification(
              id: 1000 - i,
              type: 'vtr_initialized',
              title: 'Notification $i',
              isRead: true,
              receivedAt: DateTime(2026, 10, 17, 12).subtract(Duration(hours: i))),
      ], 1000);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_NoSettings.new),
      notificationStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.dark]),
        home: const NotificationsPage(),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('Hors ligne'), findsOneWidget);
    expect(find.text('Notification 0'), findsOneWidget);
    expect(find.text('Notification 55'), findsNothing);
    await tester.tap(find.text('Afficher plus anciennes (10)'));
    await tester.pump();
    expect(find.text('Notification 59'), findsOneWidget);
  });

  testWidgets('clic sur une notification de salon : ouvre ce salon',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryNotificationStore()
      ..save([
        AppNotification.fromSite(_site(3, 'channel_reply', 'Nouvelle réponse',
            '4 nouvelles réponses à vos messages dans #Swarm Keeper',
            '/messages?channel=135&space=public', read: true)),
      ], 3);
    final container = ProviderContainer(overrides: [
      notificationsProvider.overrideWith(_Online.new),
      notificationStoreProvider.overrideWithValue(store),
      chatApiProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.dark]),
        home: const NotificationsPage(),
      ),
    ));
    expect(find.text('Nouvelle réponse'), findsOneWidget);
    await tester.tap(find.text('Nouvelle réponse'));
    await tester.pump();
    expect(container.read(notificationsProvider).channelId, 135);
    expect(find.text('Message à ce salon'), findsOneWidget,
        reason: 'la vue Salon est affichée');
  });

  testWidgets('salon : messages consécutifs regroupés', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      notificationsProvider.overrideWith(_Connected.new),
      chatApiProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);
    final n = container.read(notificationsProvider.notifier);
    Map<String, Object?> msg(int id, String user, String time) => {
          'id': id, 'channelId': 1, 'content': 'message $id',
          'sender': {'id': id, 'username': user, 'avatar': null},
          'createdAt': '2026-10-17T$time:00.000Z', 'isSystem': false,
        };
    for (final m in [
      msg(1, 'MembreA', '10:00'),
      msg(2, 'MembreA', '10:01'), // même auteur, < 5 min : regroupé
      msg(3, 'MembreB', '10:02'),
      msg(4, 'MembreA', '10:03'),
    ]) {
      n.handle(SocketEvent('channel:message', [m], DateTime.now()));
    }

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.dark]),
        home: const NotificationsPage(),
      ),
    ));
    await tester.tap(find.text('Salon'));
    await tester.pump();

    expect(find.text('message 2'), findsOneWidget);
    expect(find.text('MembreA'), findsNWidgets(2), reason: '1-2 regroupés, puis 4');
    expect(find.text('MembreB'), findsOneWidget);
  });
}
