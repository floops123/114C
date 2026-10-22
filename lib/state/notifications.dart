import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/c411_chat.dart';
import '../api/c411_socket.dart';
import '../api/transmission.dart';
import '../core/preferences.dart';
import '../core/settings.dart';
import 'torrents.dart';

// Événements observés sur le WebSocket de C411 :
//   unread:update    compteurs de non-lus (messages privés, salons, demandes…)
//   channel:message  message d'un salon de discussion
//   channel:typing   un membre écrit (ou a arrêté)
//   channel:viewers  nombre de personnes dans un salon
//   channel:reaction réactions d'un message
//   stats:update     volumes du compte (envoyé, reçu, crédit), en direct
// Le client choisit son salon en émettant channel:join / channel:leave : le
// serveur ne diffuse les messages d'un salon qu'à ceux qui l'ont rejoint.
//
// Les notifications viennent de l'API du site (/api/notifications), relue
// périodiquement et à chaque événement inconnu du WebSocket. Les hausses de
// compteurs (message privé…) donnent seulement un bandeau.

/// Notification du site (`/api/notifications`).
class AppNotification {
  AppNotification({
    required this.type,
    required this.title,
    required this.receivedAt,
    this.id,
    this.body,
    this.link,
    this.isRead = false,
    this.raw,
  });

  factory AppNotification.fromSite(Map json) => AppNotification(
        id: (json['id'] as num?)?.toInt(),
        type: json['type'] as String? ?? '',
        title: plainMentions(unescapeHtml(json['title'] as String? ?? '')),
        body: json['message'] == null
            ? null
            : plainMentions(unescapeHtml(json['message'] as String)),
        link: json['link'] as String?,
        isRead: json['isRead'] == true,
        receivedAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        raw: json['data'],
      );

  /// Format du cache local.
  factory AppNotification.fromJson(Map json) => AppNotification(
        id: (json['id'] as num?)?.toInt(),
        type: json['type'] as String? ?? json['event'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String?,
        link: json['link'] as String?,
        isRead: json['isRead'] == true,
        receivedAt:
            DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        raw: json['raw'],
      );

  final int? id;

  /// `vtr_initialized`, `ic_level_up`, `channel_reply`, `token_attribution`…
  final String type;
  final String title;
  final String? body;

  /// Chemin sur le site (`/torrents/<hash>`, `/messages?channel=…`…).
  final String? link;
  final bool isRead;
  final DateTime receivedAt;

  /// Données propres au type (`data`).
  final Object? raw;

  /// Empreinte du torrent retiré du site (`torrent_deleted`), en minuscules.
  String? get deletedHash {
    if (type != 'torrent_deleted') return null;
    final data = raw;
    final hash = (data is Map ? data['infoHash'] as String? : null) ??
        RegExp(r'/torrents/([0-9a-fA-F]{40})').firstMatch(link ?? '')?.group(1);
    return hash != null && RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(hash)
        ? hash.toLowerCase()
        : null;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'body': body,
        'link': link,
        'isRead': isRead,
        'at': receivedAt.toIso8601String(),
        'raw': raw,
      };
}

/// Cache local des notifications et de la dernière vue (pour le badge).
abstract class NotificationStore {
  (List<AppNotification>, int seenUpTo) load();
  void save(List<AppNotification> items, int seenUpTo);

  /// Notifications de suppression déjà appliquées au client.
  Set<int> loadHandled();
  void saveHandled(Set<int> ids);
}

class PrefsNotificationStore implements NotificationStore {
  PrefsNotificationStore(this._prefs);
  final SharedPreferencesWithCache _prefs;
  static const key = 'notifications';

  @override
  (List<AppNotification>, int) load() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return (const [], 0);
      final json = jsonDecode(raw) as Map;
      return (
        [
          for (final n in (json['items'] as List? ?? const []).whereType<Map>())
            AppNotification.fromJson(n),
        ],
        (json['seenUpTo'] as num?)?.toInt() ?? 0,
      );
    } on Object {
      return (const [], 0); // Données illisibles : on repart de zéro.
    }
  }

  @override
  void save(List<AppNotification> items, int seenUpTo) => _prefs.setString(
      key,
      jsonEncode({
        'seenUpTo': seenUpTo,
        'items': [for (final n in items) n.toJson()],
      }));

  static const handledKey = 'notifications.deleted';

  @override
  Set<int> loadHandled() {
    try {
      final raw = _prefs.getString(handledKey);
      return {...(jsonDecode(raw ?? '[]') as List).whereType<int>()};
    } on Object {
      return {};
    }
  }

  @override
  void saveHandled(Set<int> ids) =>
      _prefs.setString(handledKey, jsonEncode(ids.toList()));
}

class MemoryNotificationStore implements NotificationStore {
  List<AppNotification> _items = const [];
  int _seenUpTo = 0;

  @override
  (List<AppNotification>, int) load() => (_items, _seenUpTo);

  @override
  void save(List<AppNotification> items, int seenUpTo) {
    _items = items;
    _seenUpTo = seenUpTo;
  }

  Set<int> handled = {};

  @override
  Set<int> loadHandled() => {...handled};

  @override
  void saveHandled(Set<int> ids) => handled = {...ids};
}

/// Étiquette posée sur un torrent que le site a supprimé.
const deletedLabel = 'à supprimer';

/// Met en pause et étiquette [deletedLabel] les torrents du client retirés du
/// site (notifications `torrent_deleted`). Renvoie les noms des torrents
/// trouvés dans le client.
Future<List<String>> holdDeletedTorrents(
    TransmissionClient client, Iterable<AppNotification> notes) async {
  final byHash = <String, AppNotification>{
    for (final n in notes) ?n.deletedHash: n,
  };
  if (byHash.isEmpty) return const [];
  // Transmission accepte les empreintes comme identifiants.
  final found = await client.torrentGet(['id', 'hashString', 'name', 'labels'],
      ids: byHash.keys.toList());
  final held = <String>[];
  for (final t in found.torrents) {
    final id = (t['id'] as num?)?.toInt();
    final hash = (t['hashString'] as String?)?.toLowerCase();
    if (id == null || !byHash.containsKey(hash)) continue;
    final labels =
        (t['labels'] as List? ?? const []).whereType<String>().toList();
    await client.action('torrent-stop', [id]);
    if (!labels.contains(deletedLabel)) {
      await client.torrentSet([id], {
        'labels': [...labels, deletedLabel],
      });
    }
    held.add(t['name'] as String? ?? hash!);
  }
  return held;
}

final notificationStoreProvider = Provider<NotificationStore>((ref) {
  try {
    return PrefsNotificationStore(ref.watch(sharedPrefsProvider));
  } on Object {
    // Préférences non initialisées (tests) : cache en mémoire.
    return MemoryNotificationStore();
  }
});

/// Compteurs de non-lus (`unread:update`).
class UnreadCounters {
  const UnreadCounters(this.counts, this.total);

  factory UnreadCounters.fromJson(Map json) => UnreadCounters(
        {
          for (final k in kinds.keys) k: (json[k] as num?)?.toInt() ?? 0,
        },
        (json['total'] as num?)?.toInt() ?? 0,
      );

  /// Clé du compteur → (libellé, titre de notification).
  static const kinds = {
    'privateMessages': ('Messages privés', 'Nouveau message privé'),
    'channelMessages': ('Salons', 'Nouveau message dans un salon'),
    'pendingRequests': ('Demandes', 'Nouvelle demande en attente'),
    'staffMessages': ('Staff', 'Nouveau message du staff'),
  };

  final Map<String, int> counts;
  final int total;
}

/// Volumes du compte (`stats:update`), en octets.
class AccountStats {
  const AccountStats(this.uploaded, this.downloaded, this.uploadCredit);
  final int uploaded;
  final int downloaded;
  final int uploadCredit;

  double? get ratio => downloaded == 0 ? null : uploaded / downloaded;
  double? get ratioWithCredit =>
      downloaded == 0 ? null : (uploaded + uploadCredit) / downloaded;
}

class NotificationsState {
  const NotificationsState({
    this.status = SocketStatus.disconnected,
    this.configured = false,
    this.items = const [],
    this.unread = 0,
    this.hasMore = false,
    this.loadingMore = false,
    this.notifError,
    this.arrival,
    this.arrivals = 0,
    this.error,
    this.counters,
    this.account,
    this.chat = const [],
    this.viewers = const {},
    this.typing = const {},
    this.channelId = NotificationsNotifier.defaultChannel,
    this.channels = const {NotificationsNotifier.defaultChannel},
    this.channelInfo = const {},
    this.pinned = const {},
    this.historyLoading = false,
    this.chatError,
    this.myUserId,
    this.myUsername,
  });

  final SocketStatus status;
  final bool configured;

  /// Plus récentes en premier.
  final List<AppNotification> items;

  /// Non lues sur le site et pas encore vues dans l'application (badge).
  final int unread;
  final bool hasMore;
  final bool loadingMore;
  final String? notifError;

  /// Dernier bandeau à afficher ; [arrivals] change à chaque nouveau.
  final String? arrival;
  final int arrivals;
  final String? error;
  final UnreadCounters? counters;
  final AccountStats? account;

  /// Messages du salon, du plus ancien au plus récent.
  final List<ChatMessage> chat;

  /// channelId → nombre de personnes présentes.
  final Map<int, int> viewers;

  /// Pseudo → instant où l'indication « écrit… » expire.
  final Map<String, DateTime> typing;

  /// Salon rejoint, et salons connus (rejoints ou vus passer).
  final int channelId;
  final Set<int> channels;

  /// Noms, couleurs… des salons (API), et message épinglé par salon.
  final Map<int, ChatChannel> channelInfo;
  final Map<int, PinnedMessage> pinned;
  final bool historyLoading;
  final String? chatError;

  /// Notre identifiant de membre (`user_id` de `stats:update`).
  final int? myUserId;

  /// Notre pseudo, appris d'un de nos messages ou d'une de nos réactions.
  final String? myUsername;

  NotificationsState copyWith({
    SocketStatus? status,
    List<AppNotification>? items,
    int? unread,
    bool? hasMore,
    bool? loadingMore,
    String? Function()? notifError,
    String? arrival,
    int? arrivals,
    String? Function()? error,
    UnreadCounters? counters,
    AccountStats? account,
    List<ChatMessage>? chat,
    Map<int, int>? viewers,
    Map<String, DateTime>? typing,
    int? channelId,
    Set<int>? channels,
    Map<int, ChatChannel>? channelInfo,
    Map<int, PinnedMessage>? pinned,
    bool? historyLoading,
    String? Function()? chatError,
    int? myUserId,
    String? myUsername,
  }) =>
      NotificationsState(
        status: status ?? this.status,
        configured: configured,
        items: items ?? this.items,
        unread: unread ?? this.unread,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        notifError: notifError != null ? notifError() : this.notifError,
        arrival: arrival ?? this.arrival,
        arrivals: arrivals ?? this.arrivals,
        error: error != null ? error() : this.error,
        counters: counters ?? this.counters,
        account: account ?? this.account,
        chat: chat ?? this.chat,
        viewers: viewers ?? this.viewers,
        typing: typing ?? this.typing,
        channelId: channelId ?? this.channelId,
        channels: channels ?? this.channels,
        channelInfo: channelInfo ?? this.channelInfo,
        pinned: pinned ?? this.pinned,
        historyLoading: historyLoading ?? this.historyLoading,
        chatError: chatError != null ? chatError() : this.chatError,
        myUserId: myUserId ?? this.myUserId,
        myUsername: myUsername ?? this.myUsername,
      );
}

/// Se connecte au WebSocket dès qu'un cookie de session est enregistré.
class NotificationsNotifier extends Notifier<NotificationsState> {
  static const maxItems = 500;
  static const pageSize = 30;
  static const pollInterval = Duration(minutes: 2);

  /// Notifications d'id ≤ à cette valeur déjà vues dans l'application.
  int _seenUpTo = 0;
  bool _loadedOnce = false;

  /// Suppressions déjà appliquées : un torrent remis en route par
  /// l'utilisateur n'est pas remis en pause.
  Set<int> _handled = {};
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  static const maxChat = 600;
  static const historySize = 50;
  static const typingTimeout = Duration(seconds: 8);

  /// Salon général (pas de classe associée).
  static const defaultChannel = 1;

  C411Socket? _socket;

  /// Pseudo et avatar de l'utilisateur, appris quand le serveur diffuse un de
  /// ses messages (pour l'affichage immédiat des suivants).
  String? _me;
  String? _myAvatar;

  @override
  NotificationsState build() {
    final cookie = ref.watch(
        settingsProvider.select((s) => s.value?.sessionCookie ?? ''));
    // Les dernières notifications chargées restent consultables hors ligne.
    final (stored, seenUpTo) = ref.read(notificationStoreProvider).load();
    _seenUpTo = seenUpTo;
    _handled = ref.read(notificationStoreProvider).loadHandled();
    if (cookie.isEmpty) {
      return NotificationsState(items: stored, unread: _unseen(stored));
    }

    final socket = C411Socket(
      cookie,
      url: ref.read(socketUrlProvider),
      onStatus: (s) {
        if (!ref.mounted) return;
        state = state.copyWith(
            status: s, error: s == SocketStatus.connected ? () => null : null);
        // À chaque (re)connexion, on rejoint le salon choisi et on recharge
        // son historique (pour combler une éventuelle coupure).
        if (s == SocketStatus.connected) {
          _socket?.emit('channel:join', {'channelId': state.channelId});
          loadHistory(state.channelId);
        }
      },
      onError: (e) {
        if (ref.mounted) state = state.copyWith(error: () => e);
      },
      onEvent: (e) {
        if (ref.mounted) handle(e);
      },
    );
    _socket = socket;
    ref.onDispose(socket.close);
    Future.microtask(socket.connect);
    Future.microtask(loadChannels);
    Future.microtask(refreshNotifications);
    final poll = Timer.periodic(pollInterval, (_) => refreshNotifications());
    ref.onDispose(poll.cancel);
    return NotificationsState(
      configured: true,
      status: SocketStatus.connecting,
      items: stored,
      unread: _unseen(stored),
    );
  }

  int _unseen(List<AppNotification> items) =>
      items.where((n) => !n.isRead && (n.id ?? 0) > _seenUpTo).length;

  void _persist() =>
      ref.read(notificationStoreProvider).save(state.items, _seenUpTo);

  /// Bandeau ponctuel (nouvelle notification, message privé…).
  void _arrive(String text) =>
      state = state.copyWith(arrival: text, arrivals: state.arrivals + 1);

  static List<AppNotification> _merge(
      List<AppNotification> a, List<AppNotification> b) {
    final byId = <Object, AppNotification>{
      for (final n in a) n.id ?? n: n,
      for (final n in b) n.id ?? n: n,
    };
    return byId.values.toList()
      ..sort((x, y) => y.receivedAt.compareTo(x.receivedAt));
  }

  /// Relit la première page du site ; signale les nouvelles non lues.
  Future<void> refreshNotifications() async {
    final api = ref.read(chatApiProvider);
    if (api == null) return;
    _lastRefresh = DateTime.now();
    try {
      final page = await api.notifications(perPage: pageSize);
      if (!ref.mounted) return;
      final fetched = [for (final j in page.items) AppNotification.fromSite(j)];
      final known = {for (final n in state.items) n.id};
      final fresh = [
        for (final n in fetched)
          if (!n.isRead && !known.contains(n.id)) n,
      ];
      final merged = _merge(state.items, fetched).take(maxItems).toList();
      state = state.copyWith(
        items: merged,
        unread: _unseen(merged),
        hasMore: merged.length <= fetched.length ? page.hasMore : state.hasMore,
        notifError: () => null,
      );
      if (_loadedOnce && fresh.isNotEmpty) {
        _arrive(fresh.length == 1
            ? fresh.first.title
            : '${fresh.length} nouvelles notifications');
      }
      _loadedOnce = true;
      _persist();
      await holdDeleted(fetched);
    } on ChatException catch (e) {
      if (ref.mounted) state = state.copyWith(notifError: () => e.message);
    }
  }

  /// Torrents supprimés du site : en pause et étiquetés dans le client, une
  /// seule fois par notification. Sans client joignable, on réessaiera au
  /// prochain relevé.
  Future<void> holdDeleted(List<AppNotification> notes) async {
    final todo = [
      for (final n in notes)
        if (n.deletedHash != null && n.id != null && !_handled.contains(n.id))
          n,
    ];
    final client = ref.read(transmissionProvider);
    if (todo.isEmpty || client == null) return;
    final List<String> held;
    try {
      held = await holdDeletedTorrents(client, todo);
    } on Object {
      return;
    }
    if (!ref.mounted) return;
    _handled = {..._handled, for (final n in todo) n.id!};
    ref.read(notificationStoreProvider).saveHandled(_handled);
    if (held.isEmpty) return;
    _arrive(held.length == 1
        ? 'Supprimé du site, mis en pause : ${held.first}'
        : '${held.length} torrents supprimés du site mis en pause');
    ref.read(torrentsProvider.notifier).refresh();
  }

  /// Page suivante (plus anciennes).
  Future<void> loadMoreNotifications() async {
    final api = ref.read(chatApiProvider);
    if (api == null || state.loadingMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await api.notifications(
          offset: state.items.length, perPage: pageSize);
      if (!ref.mounted) return;
      final merged = _merge(state.items,
              [for (final j in page.items) AppNotification.fromSite(j)])
          .take(maxItems)
          .toList();
      state = state.copyWith(
        items: merged,
        unread: _unseen(merged),
        hasMore: page.hasMore && merged.length < maxItems,
        loadingMore: false,
      );
      _persist();
    } on ChatException catch (e) {
      if (ref.mounted) {
        state = state.copyWith(loadingMore: false, notifError: () => e.message);
      }
    }
  }

  /// Aiguillage des événements (public pour les tests).
  void handle(SocketEvent e) {
    final data = e.data;
    switch (e.name) {
      case 'channel:message' when data is Map:
        final m = ChatMessage.fromJson(data);
        if (!state.channels.contains(m.channelId)) {
          state = state.copyWith(channels: {...state.channels, m.channelId});
        }
        final typing = {...state.typing}..remove(m.username);
        if (m.senderId != null && m.senderId == state.myUserId) {
          _learnMe(m.username, m.avatarUrl);
        }
        // Notre propre message (même tempId) ou un doublon (même id) : on
        // remplace l'existant par la version du serveur.
        final i = state.chat.indexWhere((x) =>
            (m.tempId != null && x.tempId == m.tempId) ||
            (m.id != 0 && x.id == m.id));
        if (i >= 0) {
          if (state.chat[i].tempId != null && state.chat[i].tempId == m.tempId) {
            _learnMe(m.username, m.avatarUrl);
          }
          final chat = [...state.chat]..[i] = m;
          state = state.copyWith(chat: chat, typing: typing);
          return;
        }
        state = state.copyWith(chat: _cap([...state.chat, m]), typing: typing);
      case 'channel:typing' when data is Map:
        final name = data['username'] as String?;
        if (name == null || data['channelId'] != state.channelId) return;
        final typing = {...state.typing};
        if (data['isTyping'] == true) {
          typing[name] = e.receivedAt.add(typingTimeout);
        } else {
          typing.remove(name);
        }
        state = state.copyWith(typing: typing);
      case 'channel:viewers' when data is Map:
        final id = (data['channelId'] as num?)?.toInt();
        final count = (data['count'] as num?)?.toInt();
        if (id == null || count == null) return;
        state = state.copyWith(viewers: {...state.viewers, id: count});
      case 'stats:update' when data is Map:
        int n(String k) => (data[k] as num?)?.toInt() ?? 0;
        state = state.copyWith(
          account: AccountStats(n('uploaded'), n('downloaded'), n('upload_credit')),
          myUserId: (data['user_id'] as num?)?.toInt(),
        );
      case 'channel:reaction' when data is Map:
        _onReaction(data);
      case 'unread:update' when data is Map:
        _onUnread(UnreadCounters.fromJson(data), e);
      // Autres événements de salon (join/leave…) : pas des notifications.
      case final name when name.startsWith('channel:'):
        final id = data is Map ? (data['channelId'] as num?)?.toInt() : null;
        if (id != null && !state.channels.contains(id)) {
          state = state.copyWith(channels: {...state.channels, id});
        }
      // Événement inconnu (probablement une nouvelle notification) : on relit
      // la liste, au plus une fois toutes les 10 s.
      default:
        if (DateTime.now().difference(_lastRefresh).inSeconds >= 10) {
          refreshNotifications();
        }
    }
  }

  void _learnMe(String username, String? avatar) {
    _me = username;
    _myAvatar = avatar ?? _myAvatar;
    if (state.myUsername != username) {
      state = state.copyWith(myUsername: username);
    }
  }

  /// Liste complète des réactions d'un message (remplace la précédente).
  void _onReaction(Map data) {
    final id = (data['messageId'] as num?)?.toInt();
    final reactions = ChatReaction.listFromJson(data['reactions']);
    final me = state.myUserId;
    if (me != null && _me == null) {
      for (final r in reactions) {
        final i = r.userIds.indexOf(me);
        if (i >= 0 && i < r.usernames.length) _learnMe(r.usernames[i], null);
      }
    }
    final i = state.chat.indexWhere((m) => m.id == id);
    if (id == null || i < 0) return;
    state = state.copyWith(
        chat: [...state.chat]..[i] = state.chat[i].copyWith(reactions: reactions));
  }

  /// Bandeau quand un compteur augmente (après le premier relevé).
  void _onUnread(UnreadCounters next, SocketEvent e) {
    final previous = state.counters;
    state = state.copyWith(counters: next);
    if (previous == null) return;
    for (final MapEntry(key: k, value: (_, title))
        in UnreadCounters.kinds.entries) {
      final now = next.counts[k] ?? 0;
      if (now > (previous.counts[k] ?? 0)) {
        _arrive('$title ($now non lu${now > 1 ? 's' : ''})');
      }
    }
  }

  /// Les notifications affichées sont vues : le badge repart de zéro.
  void markAllRead() {
    final maxId = state.items.fold(0, (m, n) => math.max(m, n.id ?? 0));
    if (maxId <= _seenUpTo && state.unread == 0) return;
    _seenUpTo = math.max(_seenUpTo, maxId);
    state = state.copyWith(unread: 0);
    _persist();
  }

  /// Quitte le salon actuel et rejoint [id].
  void joinChannel(int id) {
    if (id == state.channelId) return;
    _socket?.emit('channel:leave', {'channelId': state.channelId});
    _socket?.emit('channel:join', {'channelId': id});
    state = state.copyWith(
        channelId: id, channels: {...state.channels, id}, typing: const {});
    loadHistory(id);
  }

  /// Envoie un message dans le salon actif (`channel:send` avec accusé de
  /// réception). Le message s'affiche aussitôt, en attente de confirmation.
  Future<void> sendMessage(String text) async {
    final content = text.trim();
    if (content.isEmpty) return;
    final rnd = math.Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}-'
        '${List.generate(9, (_) => chars[rnd.nextInt(chars.length)]).join()}';
    final pending = ChatMessage(
      id: 0,
      channelId: state.channelId,
      username: _me ?? 'Moi',
      avatarUrl: _myAvatar,
      content: content,
      createdAt: DateTime.now(),
      tempId: tempId,
      sendState: SendState.pending,
    );
    state = state.copyWith(chat: _cap([...state.chat, pending]));
    await _deliver(pending);
  }

  /// Renvoie un message dont l'envoi a échoué.
  Future<void> retry(ChatMessage failed) async {
    _update(failed.tempId,
        (m) => m.copyWith(sendState: SendState.pending, sendError: null));
    await _deliver(failed);
  }

  Future<void> _deliver(ChatMessage m) async {
    final socket = _socket;
    try {
      if (socket == null) throw const SocketException('Non connecté');
      final ack = await socket.emitWithAck('channel:send', {
        'channelId': m.channelId,
        'content': m.content,
        'tempId': m.tempId,
      });
      if (!ref.mounted) return;
      if (ack is Map && ack['success'] == true) {
        _update(
            m.tempId,
            (x) => x.copyWith(
                id: (ack['messageId'] as num?)?.toInt(),
                sendState: SendState.sent));
      } else {
        final reason = ack is Map
            ? (ack['error'] ?? ack['message'] ?? ack['status'] ?? 'refusé')
            : 'refusé';
        _update(m.tempId,
            (x) => x.copyWith(sendState: SendState.failed, sendError: '$reason'));
      }
    } on SocketException catch (e) {
      if (ref.mounted) {
        _update(m.tempId,
            (x) => x.copyWith(sendState: SendState.failed, sendError: e.message));
      }
    }
  }

  /// Met à jour le message d'après son tempId (s'il est encore affiché).
  void _update(String? tempId, ChatMessage Function(ChatMessage) change) {
    final i = state.chat.indexWhere((x) => x.tempId != null && x.tempId == tempId);
    if (i < 0) return;
    // Déjà remplacé par la diffusion du serveur : rien à faire.
    if (state.chat[i].sendState == SendState.sent &&
        state.chat[i].id != 0) {
      return;
    }
    state = state.copyWith(chat: [...state.chat]..[i] = change(state.chat[i]));
  }

  static List<ChatMessage> _cap(List<ChatMessage> chat) =>
      chat.length > maxChat ? chat.sublist(chat.length - maxChat) : chat;

  Future<void> loadChannels() async {
    final api = ref.read(chatApiProvider);
    if (api == null) return;
    try {
      final list = await api.channels();
      if (!ref.mounted) return;
      state = state.copyWith(
        channelInfo: {for (final c in list) c.id: c},
        channels: {...state.channels, ...list.map((c) => c.id)},
      );
    } on ChatException catch (e) {
      if (ref.mounted) state = state.copyWith(chatError: () => e.message);
    }
  }

  /// Derniers messages du salon, fusionnés avec ceux reçus en direct.
  Future<void> loadHistory(int channelId) async {
    final api = ref.read(chatApiProvider);
    if (api == null) return;
    state = state.copyWith(historyLoading: true);
    try {
      final history = await api.history(channelId, limit: historySize);
      if (!ref.mounted) return;
      final byKey = {
        for (final m in state.chat) m.key: m,
        // L'historique fait foi (réactions, modifications).
        for (final m in history.messages) m.key: m,
      };
      // Messages en cours d'envoi (sans id) à la fin.
      int order(ChatMessage m) => m.id != 0 ? m.id : 1 << 62;
      final merged = byKey.values.toList()
        ..sort((a, b) => order(a).compareTo(order(b)));
      state = state.copyWith(
        chat: _cap(merged),
        pinned: {
          for (final e in state.pinned.entries)
            if (e.key != channelId) e.key: e.value,
          if (history.pinned != null) channelId: history.pinned!,
        },
        historyLoading: false,
        chatError: () => null,
      );
    } on ChatException catch (e) {
      if (ref.mounted) {
        state = state.copyWith(historyLoading: false, chatError: () => e.message);
      }
    }
  }

  /// Nouvelle tentative après une session refusée ou une coupure.
  void reconnect() => ref.invalidateSelf();
}

/// Adresse du WebSocket (remplaçable dans les tests).
final socketUrlProvider = Provider<Uri>((ref) => C411Socket.defaultUrl);

/// API de discussion (null sans cookie de session).
final chatApiProvider = Provider<C411ChatApi?>((ref) {
  final cookie =
      ref.watch(settingsProvider.select((s) => s.value?.sessionCookie ?? ''));
  if (cookie.isEmpty) return null;
  final api = C411ChatApi(cookie);
  ref.onDispose(api.close);
  return api;
});

final notificationsProvider =
    NotifierProvider<NotificationsNotifier, NotificationsState>(
        NotificationsNotifier.new);
