import 'package:c411_remote/api/c411_chat.dart';
import 'package:c411_remote/api/c411_socket.dart';
import 'package:c411_remote/state/notifications.dart';
import 'package:c411_remote/ui/notifications_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Extraits de /api/messages/channels et /api/messages/channels/1 (pseudos et
// messages anonymisés ; noms de salons publics conservés).
const _channels = [
  {'id': 1, 'name': 'Général', 'description': 'Salon de discussion général', 'color': '#10B981', 'isDefault': true, 'isArchived': false, 'canWrite': true},
  {'id': 26, 'name': 'Aide', 'description': 'Entraide entre membres', 'color': '#3B82F6', 'isDefault': false, 'isArchived': false, 'canWrite': true},
  {'id': 3, 'name': 'Annonces', 'description': 'Annonces officielles de l&#x27;équipe', 'color': '#F59E0B', 'isDefault': false, 'isArchived': false, 'canWrite': false},
  {'id': 99, 'name': 'Ancien', 'isArchived': true},
];

Map<String, Object?> _msg(int id, String content,
        {Map<String, Object?>? replyTo,
        bool edited = false,
        List<Map<String, Object?>> reactions = const []}) =>
    {
      'id': id,
      'sender': {'id': 1000 + id, 'username': 'Membre$id', 'avatar': null, 'certificationBadge': null},
      'content': content,
      'replyTo': replyTo,
      'isSystem': false,
      'isDeleted': false,
      'isEdited': edited,
      'createdAt': '2026-10-17T04:1$id:00.000Z',
      'reactions': reactions,
    };

final _history = [
  _msg(1, 'Faut attendre un mois ou deux.',
      replyTo: {'id': 0, 'senderId': 5, 'senderUsername': 'MembreX', 'content': 'C&#x27;est compliqué', 'isDeleted': false},
      reactions: [{'emoji': '👍', 'count': 2, 'hasReacted': false}]),
  _msg(2, 'Qui peut m&#x27;interpreter ca ? /uploads/chat/2026-10/abc.webp', edited: true),
  _msg(3, 'Bonjour', replyTo: {'id': 9, 'senderUsername': 'MembreY', 'content': 'x', 'isDeleted': true}),
];

class _FakeChat extends C411ChatApi {
  _FakeChat() : super('');

  @override
  Future<List<ChatChannel>> channels() async => [
        for (final c in _channels)
          if (c['isArchived'] != true) ChatChannel.fromJson(c),
      ];

  @override
  Future<ChannelHistory> history(int channelId, {int limit = 50}) async =>
      ChannelHistory(
        [for (final m in _history) ChatMessage.fromJson(m, channelId: channelId)],
        const PinnedMessage('Le guide : https://c411.org/guide', 'Modo'),
      );
}

class _Connected extends NotificationsNotifier {
  @override
  NotificationsState build() => const NotificationsState(
      configured: true, status: SocketStatus.connected);
}

void main() {
  test('message de l’historique : réponse, réactions, image, modifié', () {
    final m = [for (final j in _history) ChatMessage.fromJson(j, channelId: 1)];
    expect(m[0].channelId, 1);
    expect(m[0].replyTo, 'MembreX : C\'est compliqué');
    expect(m[0].reactions, [('👍', 2)]);
    expect(m[1].content, 'Qui peut m\'interpreter ca ?');
    expect(m[1].images, ['https://c411.org/uploads/chat/2026-10/abc.webp']);
    expect(m[1].isEdited, isTrue);
    expect(m[2].replyTo, 'MembreY : message supprimé');
  });

  test('salons et message épinglé', () {
    final c = ChatChannel.fromJson(_channels[2]);
    expect((c.name, c.description, c.color, c.canWrite),
        ('Annonces', 'Annonces officielles de l\'équipe', 0xFFF59E0B, false));
    expect(
        cleanRichText('Hello, **&lt;span class=&quot;underline&quot;&gt;'
            'vous trouverez surement réponse par ici :&lt;/span&gt;** https://c411.org/guide'),
        'Hello, vous trouverez surement réponse par ici : https://c411.org/guide');
  });

  test('historique fusionné avec le direct, sans doublon', () async {
    final container = ProviderContainer(overrides: [
      notificationsProvider.overrideWith(_Connected.new),
      chatApiProvider.overrideWithValue(_FakeChat()),
    ]);
    addTearDown(container.dispose);
    final n = container.read(notificationsProvider.notifier);
    // Un message en direct déjà présent dans l'historique, et un nouveau.
    for (final id in [2, 4]) {
      n.handle(SocketEvent('channel:message', [
        {..._msg(id, 'direct $id'), 'channelId': 1},
      ], DateTime.now()));
    }
    await n.loadChannels();
    await n.loadHistory(1);
    final s = container.read(notificationsProvider);
    expect(s.chat.map((m) => m.id), [1, 2, 3, 4]);
    expect(s.chat[1].isEdited, isTrue, reason: 'la version de l’historique fait foi');
    expect(s.channelInfo.keys, [1, 26, 3]);
    expect(s.pinned[1]?.username, 'Modo');
  });

  testWidgets('salon : vrais noms, description, épinglé, réactions', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      notificationsProvider.overrideWith(_Connected.new),
      chatApiProvider.overrideWithValue(_FakeChat()),
    ]);
    addTearDown(container.dispose);
    final n = container.read(notificationsProvider.notifier);
    await n.loadChannels();
    await n.loadHistory(1);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.dark]),
        home: const NotificationsPage(),
      ),
    ));
    await tester.tap(find.text('Salon'));
    await tester.pump();

    for (final name in ['Général', 'Aide', 'Annonces']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Salon de discussion général'), findsOneWidget);
    expect(find.textContaining('Le guide'), findsOneWidget);
    expect(find.text('👍 2'), findsOneWidget);
    expect(find.text('Message supprimé'), findsNothing);
  });
}
