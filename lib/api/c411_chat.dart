import 'package:dio/dio.dart';

import 'quota.dart';
import 'tracker.dart';

/// Le contenu des messages arrive encodé en HTML (`c&#x27;est`).
String unescapeHtml(String s) => s.replaceAllMapped(
      RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos|nbsp);'),
      (m) {
        final e = m[1]!;
        if (e.startsWith('#x')) {
          return String.fromCharCode(int.parse(e.substring(2), radix: 16));
        }
        if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
        return const {
          'amp': '&',
          'lt': '<',
          'gt': '>',
          'quot': '"',
          'apos': "'",
          'nbsp': '\u00a0',
        }[e]!;
      },
    );

/// Mentions telles que le site les enregistre (`{{pseudo}}`) écrites
/// `@pseudo`, pour les textes affichés sans mise en forme (notifications,
/// aperçu d'une réponse).
String plainMentions(String s) => s.replaceAllMapped(
    RegExp(r'\{\{([^{}\s]{1,32})\}\}'), (m) => '@${m[1]}');

/// Texte enrichi (message épinglé…) : HTML décodé puis balises et gras
/// Markdown retirés, pour un affichage en texte simple.
String cleanRichText(String s) => plainMentions(unescapeHtml(s))
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('**', '')
    .trim();

/// `#RRGGBB` → valeur ARGB opaque.
int? parseHexColor(String? s) =>
    s != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s)
        ? int.parse('FF${s.substring(1)}', radix: 16)
        : null;

/// Images partagées dans les messages : chemins `/uploads/chat/…`.
final _imagePath = RegExp(
    r'(?:https://c411\.org)?(/uploads/chat/\S+?\.(?:webp|png|jpe?g|gif))',
    caseSensitive: false);

/// Réaction à un message : emoji Unicode ou émoticône du site (`:jul:`).
class ChatReaction {
  const ChatReaction(this.emoji, this.count,
      {this.userIds = const [], this.usernames = const [], this.hasReacted = false});

  factory ChatReaction.fromJson(Map json) => ChatReaction(
        json['emoji'] as String,
        (json['count'] as num?)?.toInt() ?? 1,
        userIds: [
          for (final id in json['userIds'] as List? ?? const [])
            if (id is num) id.toInt(),
        ],
        usernames: (json['usernames'] as List? ?? const []).whereType<String>().toList(),
        hasReacted: json['hasReacted'] == true,
      );

  static List<ChatReaction> listFromJson(Object? json) => [
        for (final r in (json as List? ?? const []).whereType<Map>())
          if (r['emoji'] is String) ChatReaction.fromJson(r),
      ];

  final String emoji;
  final int count;
  final List<int> userIds;
  final List<String> usernames;

  /// Fourni par l'historique ; en direct, on compare [userIds] à notre id.
  final bool hasReacted;

  bool isMine(int? myId) => hasReacted || (myId != null && userIds.contains(myId));
}

/// État d'un message que l'on a soi-même envoyé.
enum SendState { sent, pending, failed }

/// Message de salon, reçu en direct (`channel:message`) ou par l'historique
/// (`/api/messages/channels/{id}`), deux formats légèrement différents.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.channelId,
    required this.username,
    required this.content,
    required this.createdAt,
    this.senderId,
    this.role,
    this.nameTone,
    this.avatarUrl,
    this.badge,
    this.badgeColor,
    this.isSystem = false,
    this.isEdited = false,
    this.isDeleted = false,
    this.replyTo,
    this.reactions = const [],
    this.images = const [],
    this.tempId,
    this.sendState = SendState.sent,
    this.sendError,
  });

  factory ChatMessage.fromJson(Map json, {int? channelId}) {
    final sender = json['sender'] as Map? ?? const {};
    final badge = sender['certificationBadge'] as Map?;
    final avatar = sender['avatar'] as String?;
    final reply = json['replyTo'];
    var content = unescapeHtml(json['content'] as String? ?? '');
    final images = [
      for (final m in _imagePath.allMatches(content)) 'https://c411.org${m[1]}',
    ];
    content = content.replaceAll(_imagePath, '').trim();
    String? replyText;
    if (reply is Map) {
      final who = reply['senderUsername'] ??
          (reply['sender'] as Map?)?['username'] ??
          reply['username'] ??
          '';
      replyText = reply['isDeleted'] == true
          ? '$who : message supprimé'
          : plainMentions(unescapeHtml('$who : ${reply['content'] ?? ''}'));
    }
    return ChatMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      channelId: (json['channelId'] as num?)?.toInt() ?? channelId ?? 0,
      username: sender['username'] as String? ?? '?',
      senderId: (sender['id'] as num?)?.toInt(),
      role: sender['role'] as String?,
      nameTone: sender['nameTone'] as String?,
      content: content,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      avatarUrl: avatar == null
          ? null
          : (avatar.startsWith('http') ? avatar : 'https://c411.org$avatar'),
      badge: badge?['label'] as String?,
      badgeColor: parseHexColor(badge?['color'] as String?),
      isSystem: json['isSystem'] == true,
      isEdited: json['isEdited'] == true,
      isDeleted: json['isDeleted'] == true,
      replyTo: replyText,
      reactions: ChatReaction.listFromJson(json['reactions']),
      images: images,
      tempId: json['tempId'] as String?,
    );
  }

  /// Clé unique : l'id du serveur, ou le tempId tant qu'il n'est pas attribué.
  Object get key => id != 0 ? id : (tempId ?? identityHashCode(this));

  ChatMessage copyWith({
    int? id,
    String? username,
    String? avatarUrl,
    SendState? sendState,
    String? sendError,
    List<ChatReaction>? reactions,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        channelId: channelId,
        username: username ?? this.username,
        senderId: senderId,
        role: role,
        nameTone: nameTone,
        content: content,
        createdAt: createdAt,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        badge: badge,
        badgeColor: badgeColor,
        isSystem: isSystem,
        isEdited: isEdited,
        isDeleted: isDeleted,
        replyTo: replyTo,
        reactions: reactions ?? this.reactions,
        images: images,
        tempId: tempId,
        sendState: sendState ?? this.sendState,
        sendError: sendError,
      );

  final int id;
  final int channelId;
  final String username;
  final int? senderId;

  /// `user`, `moderator`, `admin`… (absent des messages envoyés d'avance).
  final String? role;

  /// Rang affiché par la couleur du pseudo (`bronze`, `argent`, `or`…).
  final String? nameTone;
  final String content;
  final DateTime createdAt;
  final String? avatarUrl;
  final String? badge;
  final int? badgeColor;
  final bool isSystem;
  final bool isEdited;
  final bool isDeleted;
  final String? replyTo;
  final List<ChatReaction> reactions;

  /// URL absolues des images jointes (retirées du texte).
  final List<String> images;

  /// Identifiant temporaire choisi par l'expéditeur (`temp-<ms>-<aléa>`),
  /// renvoyé par le serveur pour réconcilier le message affiché d'avance.
  final String? tempId;
  final SendState sendState;
  final String? sendError;
}

/// Salon de discussion (`/api/messages/channels`).
class ChatChannel {
  const ChatChannel({
    required this.id,
    required this.name,
    this.description,
    this.color,
    this.isDefault = false,
    this.isArchived = false,
    this.canWrite = false,
    this.slowModeSeconds = 0,
  });

  factory ChatChannel.fromJson(Map json) => ChatChannel(
        id: (json['id'] as num).toInt(),
        name: unescapeHtml(json['name'] as String? ?? '#${json['id']}'),
        description: json['description'] == null
            ? null
            : unescapeHtml(json['description'] as String),
        color: parseHexColor(json['color'] as String?),
        isDefault: json['isDefault'] == true,
        isArchived: json['isArchived'] == true,
        canWrite: json['canWrite'] == true,
        slowModeSeconds: (json['slowModeSeconds'] as num?)?.toInt() ?? 0,
      );

  final int id;
  final String name;
  final String? description;
  final int? color;
  final bool isDefault;
  final bool isArchived;
  final bool canWrite;

  /// Délai minimal entre deux messages (0 = libre).
  final int slowModeSeconds;
}

/// Message épinglé d'un salon.
class PinnedMessage {
  const PinnedMessage(this.content, this.username);
  final String content;
  final String username;
}

class ChannelHistory {
  const ChannelHistory(this.messages, this.pinned);
  final List<ChatMessage> messages;
  final PinnedMessage? pinned;
}

class ChatException implements Exception {
  const ChatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// API de discussion du site, authentifiée par le cookie de session (comme le
/// WebSocket ; la clé API n'y donne pas accès).
class C411ChatApi {
  C411ChatApi(String cookie)
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://c411.org',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: (_) => true,
          headers: {'Cookie': cookie, 'Origin': 'https://c411.org'},
        ));

  final Dio _dio;

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, dynamic>? query]) async {
    final Response<dynamic> res;
    try {
      res = await trackerRequest(Tracker.c411,
          () => _dio.get<dynamic>(path, queryParameters: query));
    } on DioException catch (e) {
      throw ChatException('C411 injoignable : ${e.message ?? e.type.name}');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const ChatException(
          'Session C411 refusée : recolle le cookie dans les réglages');
    }
    if (res.statusCode != 200 || res.data is! Map) {
      throw ChatException('Réponse C411 inattendue (HTTP ${res.statusCode})');
    }
    return (res.data as Map).cast<String, dynamic>();
  }

  /// Notifications du site, des plus récentes aux plus anciennes
  /// (`/api/notifications?offset=…&perPage=…`).
  Future<({List<Map<String, dynamic>> items, bool hasMore, int unread})>
      notifications({int offset = 0, int perPage = 30}) async {
    final body = await _get(
        '/api/notifications', {'offset': offset, 'perPage': perPage});
    final meta = body['meta'] as Map? ?? const {};
    return (
      items: [
        for (final n in (body['data'] as List? ?? const []).whereType<Map>())
          n.cast<String, dynamic>(),
      ],
      hasMore: meta['hasMore'] == true,
      unread: (meta['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Salons accessibles, tous espaces confondus (public…), hors archivés.
  Future<List<ChatChannel>> channels() async {
    final data = (await _get('/api/messages/channels'))['data'];
    final spaces = data is Map ? data.values : const [];
    return [
      for (final list in spaces)
        if (list is List)
          for (final c in list.whereType<Map>())
            if (c['isArchived'] != true) ChatChannel.fromJson(c),
    ];
  }

  /// Derniers messages d'un salon, du plus ancien au plus récent.
  Future<ChannelHistory> history(int channelId, {int limit = 50}) async {
    final body =
        await _get('/api/messages/channels/$channelId', {'limit': limit});
    final messages = [
      for (final m in (body['data'] as List? ?? const []).whereType<Map>())
        ChatMessage.fromJson(m, channelId: channelId),
    ];
    final pinned = (body['channel'] as Map?)?['pinnedMessage'];
    return ChannelHistory(
      messages,
      pinned is Map
          ? PinnedMessage(
              cleanRichText(pinned['content'] as String? ?? ''),
              (pinned['sender'] as Map?)?['username'] as String? ?? '',
            )
          : null,
    );
  }

  /// Libère les connexions (cookie changé : un nouveau client le remplace).
  void close() => _dio.close();
}
