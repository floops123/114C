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

SocketEvent _unread(int pm) => SocketEvent('unread:update', [
      {'privateMessages': pm, 'channelMessages': 0, 'pendingRequests': 0,
       'staffMessages': 0, 'total': pm},
    ], DateTime.now());

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
    });
  });

  test('historique conservé entre deux lancements', () {
    final store = MemoryNotificationStore();
    ProviderContainer launch() {
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith(_NoSettings.new),
        notificationStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    final first = launch();
    final n = first.read(notificationsProvider.notifier);
    n.handle(_unread(0));
    n.handle(_unread(2));
    expect(first.read(notificationsProvider).unread, 1);
    first.dispose();

    final second = launch();
    final s = second.read(notificationsProvider);
    expect(s.items.single.title, 'Nouveau message privé');
    expect(s.unread, 1, reason: 'le compteur de non-lues est conservé');
    second.read(notificationsProvider.notifier).markAllRead();
    expect(store.load().$2, 0);
  });

  test('sérialisation d’une notification', () {
    final n = AppNotification(
        event: 'x', title: 'T', body: 'B', receivedAt: DateTime.utc(2026, 1, 2),
        raw: {'a': 1});
    final back = AppNotification.fromJson(n.toJson());
    expect((back.event, back.title, back.body, back.receivedAt),
        ('x', 'T', 'B', DateTime.utc(2026, 1, 2)));
    expect(back.raw, {'a': 1});
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
              event: 'unread:update',
              title: 'Notification $i',
              receivedAt: DateTime(2026, 10, 17, 12).subtract(Duration(hours: i))),
      ], 0);
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
