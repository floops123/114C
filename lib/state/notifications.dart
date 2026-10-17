import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/c411_chat.dart';
import '../api/c411_socket.dart';
import '../core/settings.dart';

// Événements observés sur le WebSocket de C411 :
//   unread:update    compteurs de non-lus (messages privés, salons, demandes…)
//   channel:message  message d'un salon de discussion
//   channel:typing   un membre écrit (ou a arrêté)
//   channel:viewers  nombre de personnes dans un salon
//   stats:update     volumes du compte (envoyé, reçu, crédit), en direct
// Le client choisit son salon en émettant channel:join / channel:leave : le
// serveur ne diffuse les messages d'un salon qu'à ceux qui l'ont rejoint.
// Seules les hausses de compteurs (et les événements inconnus) deviennent des
// notifications ; le reste alimente le salon et l'encadré « Mon compte ».

/// Notification affichée dans l'application.
class AppNotification {
  AppNotification({
    required this.event,
    required this.title,
    required this.receivedAt,
    this.body,
    this.raw,
  });

  final String event;
  final String title;
  final String? body;
  final DateTime receivedAt;
  final Object? raw;

  /// Contenu brut lisible (affiché en détail).
  String get rawText {
    try {
      return const JsonEncoder.withIndent('  ').convert(raw);
    } on JsonUnsupportedObjectError {
      return '$raw';
    }
  }

  static const _titleKeys = ['title', 'subject', 'message', 'text', 'content'];
  static const _bodyKeys = ['body', 'description', 'message', 'text', 'content'];

  /// Événement inconnu : on cherche les champs usuels (titre, message…) et on
  /// retombe sur le nom de l'événement.
  factory AppNotification.fromEvent(SocketEvent e) {
    final data = e.data;
    String? pick(Map m, List<String> keys, {String? except}) {
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty && v != except) return v.trim();
      }
      return null;
    }

    String title = e.name;
    String? body;
    if (data is Map) {
      title = pick(data, _titleKeys) ?? e.name;
      body = pick(data, _bodyKeys, except: title);
    } else if (data is String && data.isNotEmpty) {
      body = data;
    }
    return AppNotification(
      event: e.name,
      title: title,
      body: body,
      receivedAt: e.receivedAt,
      raw: e.args.length == 1 ? e.args.first : e.args,
    );
  }
}

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
  });

  final SocketStatus status;
  final bool configured;

  /// Plus récentes en premier.
  final List<AppNotification> items;
  final int unread;
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

  NotificationsState copyWith({
    SocketStatus? status,
    List<AppNotification>? items,
    int? unread,
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
  }) =>
      NotificationsState(
        status: status ?? this.status,
        configured: configured,
        items: items ?? this.items,
        unread: unread ?? this.unread,
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
      );
}

/// Se connecte au WebSocket dès qu'un cookie de session est enregistré.
class NotificationsNotifier extends Notifier<NotificationsState> {
  static const maxItems = 200;
  static const maxChat = 600;
  static const historySize = 50;
  static const typingTimeout = Duration(seconds: 8);

  /// Salon général (pas de classe associée).
  static const defaultChannel = 1;

  C411Socket? _socket;

  @override
  NotificationsState build() {
    final cookie = ref.watch(
        settingsProvider.select((s) => s.value?.sessionCookie ?? ''));
    if (cookie.isEmpty) return const NotificationsState();

    final socket = C411Socket(
      cookie,
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
    return const NotificationsState(
        configured: true, status: SocketStatus.connecting);
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
        // Le serveur peut envoyer deux fois le même message.
        if (state.chat.any((x) => x.id == m.id && m.id != 0)) return;
        final typing = {...state.typing}..remove(m.username);
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
            account: AccountStats(
                n('uploaded'), n('downloaded'), n('upload_credit')));
      case 'unread:update' when data is Map:
        _onUnread(UnreadCounters.fromJson(data), e);
      // Autres événements de salon (join/leave…) : pas des notifications.
      case final name when name.startsWith('channel:'):
        final id = data is Map ? (data['channelId'] as num?)?.toInt() : null;
        if (id != null && !state.channels.contains(id)) {
          state = state.copyWith(channels: {...state.channels, id});
        }
      default:
        _notify(AppNotification.fromEvent(e));
    }
  }

  /// Une notification par compteur qui augmente ; au premier relevé, une
  /// seule par compteur non nul.
  void _onUnread(UnreadCounters next, SocketEvent e) {
    final previous = state.counters;
    state = state.copyWith(counters: next);
    for (final MapEntry(key: k, value: (_, title))
        in UnreadCounters.kinds.entries) {
      final now = next.counts[k] ?? 0;
      final before = previous?.counts[k] ?? 0;
      if (now > before) {
        _notify(AppNotification(
          event: e.name,
          title: title,
          body: '$now non lu${now > 1 ? 's' : ''}',
          receivedAt: e.receivedAt,
          raw: e.data,
        ));
      }
    }
  }

  void _notify(AppNotification n) {
    state = state.copyWith(
      items: [n, ...state.items].take(maxItems).toList(),
      unread: state.unread + 1,
    );
  }

  void markAllRead() {
    if (state.unread != 0) state = state.copyWith(unread: 0);
  }

  void clear() => state = state.copyWith(items: const [], unread: 0);

  /// Quitte le salon actuel et rejoint [id].
  void joinChannel(int id) {
    if (id == state.channelId) return;
    _socket?.emit('channel:leave', {'channelId': state.channelId});
    _socket?.emit('channel:join', {'channelId': id});
    state = state.copyWith(
        channelId: id, channels: {...state.channels, id}, typing: const {});
    loadHistory(id);
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
      final byId = {
        for (final m in state.chat) m.id: m,
        // L'historique fait foi (réactions, modifications).
        for (final m in history.messages) m.id: m,
      };
      final merged = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
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

/// API de discussion (null sans cookie de session).
final chatApiProvider = Provider<C411ChatApi?>((ref) {
  final cookie =
      ref.watch(settingsProvider.select((s) => s.value?.sessionCookie ?? ''));
  return cookie.isEmpty ? null : C411ChatApi(cookie);
});

final notificationsProvider =
    NotifierProvider<NotificationsNotifier, NotificationsState>(
        NotificationsNotifier.new);
