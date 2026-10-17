import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/c411_chat.dart';
import '../api/c411_socket.dart';
import '../core/format.dart';
import '../state/notifications.dart';
import '../state/torrents.dart';
import 'torrent_detail_page.dart';
import 'rich_text.dart';
import 'theme.dart';
import 'widgets.dart';

enum _View { notifications, chat }

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  _View _view = _View.notifications;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final c = context.colors;

    final (Color color, IconData icon) = switch (state.status) {
      SocketStatus.connected => (c.success, Icons.wifi_rounded),
      SocketStatus.connecting => (c.muted, Icons.sync_rounded),
      SocketStatus.disconnected => (c.warning, Icons.wifi_off_rounded),
      SocketStatus.unauthorized => (c.danger, Icons.lock_outline_rounded),
    };
    final viewers = state.viewers[state.channelId];

    return Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Notifications',
            subtitle: state.configured
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        // L'état s'accompagne toujours d'une icône et d'un libellé.
                        StatPill(
                          icon: icon,
                          color: color,
                          label: state.status.label,
                        ),
                      ],
                    ),
                  )
                : null,
            actions: [
              if (state.status == SocketStatus.unauthorized ||
                  state.status == SocketStatus.disconnected)
                IconButton(
                  tooltip: 'Se reconnecter',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: notifier.reconnect,
                ),
              if (_view == _View.notifications && state.configured)
                IconButton(
                  tooltip: 'Rafraîchir',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: notifier.refreshNotifications,
                ),
            ],
          ),
          if (state.error != null && state.status != SocketStatus.connected)
            ErrorBanner(
              state.status == SocketStatus.unauthorized
                  ? '${state.error}\nLe cookie de session a peut-être expiré : '
                        'recolle-le dans les réglages.'
                  : state.error!,
            ),
          if (!state.configured && state.items.isEmpty)
            const Expanded(
              child: EmptyState(
                Icons.notifications_off_outlined,
                'Ajoute tes cookies de session C411 dans les réglages\n'
                'pour recevoir les notifications du site.',
              ),
            )
          else ...[
            if (!state.configured)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Hors ligne : historique local. Ajoute tes cookies de '
                  'session dans les réglages pour recevoir les nouvelles.',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ),
            ChipRow<_View>(
              items: _View.values,
              selected: _view,
              label: (v) => switch (v) {
                _View.notifications =>
                  state.unread > 0
                      ? 'Notifications (${state.unread})'
                      : 'Notifications',
                _View.chat =>
                  viewers != null && viewers > 0
                      ? 'Salon · $viewers en ligne'
                      : 'Salon',
              },
              onSelected: (v) => setState(() => _view = v),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: c.border),
            Expanded(
              child: _view == _View.notifications
                  ? _NotificationsView(
                      state: state,
                      onOpenChannel: () => setState(() => _view = _View.chat),
                    )
                  : _ChatView(state: state),
            ),
          ],
        ],
      ),
    );
  }
}

/// Liste des notifications, groupées par jour, paginée (les plus récentes en
/// premier ; « Afficher plus » pour remonter l'historique local).
class _NotificationsView extends ConsumerStatefulWidget {
  const _NotificationsView({required this.state, required this.onOpenChannel});
  final NotificationsState state;

  /// Ouvre la vue Salon (lien `/messages?channel=…`).
  final VoidCallback onOpenChannel;

  @override
  ConsumerState<_NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends ConsumerState<_NotificationsView> {
  static const _page = 50;
  int _shown = _page;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = ref.read(notificationsProvider.notifier);
    final c = context.colors;
    final shown = state.items.take(_shown).toList();
    final remaining = state.items.length - shown.length;
    final header = <Widget>[
      if (state.account != null) _AccountCard(state.account!),
      if (state.counters != null) _CountersRow(state.counters!),
    ];
    return RefreshIndicator(
      onRefresh: notifier.refreshNotifications,
      child: ListView(
        children: [
          if (state.notifError != null) ErrorBanner(state.notifError!),
          if (header.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final w in header) ...[w, const SizedBox(height: 10)],
                ],
              ),
            ),
          if (state.items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: EmptyState(
                Icons.notifications_none_rounded,
                state.status == SocketStatus.connected
                    ? 'Aucune notification pour le moment.'
                    : 'En attente de connexion…',
              ),
            )
          else ...[
            for (final (i, n) in shown.indexed) ...[
              if (i == 0 ||
                  !_sameDay(
                    shown[i - 1].receivedAt.toLocal(),
                    n.receivedAt.toLocal(),
                  ))
                _DaySeparator(n.receivedAt)
              else
                Divider(height: 1, indent: 36, color: c.border),
              _NotificationTile(
                notification: n,
                onOpenChannel: widget.onOpenChannel,
              ),
            ],
            // D'abord celles déjà chargées, puis la page suivante du site.
            if (remaining > 0 || state.hasMore)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: state.loadingMore
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _shown += _page);
                            if (remaining < _page && state.hasMore) {
                              notifier.loadMoreNotifications();
                            }
                          },
                          icon: const Icon(Icons.history_rounded, size: 18),
                          label: Text(
                            remaining > 0
                                ? 'Afficher plus anciennes ($remaining)'
                                : 'Afficher plus anciennes',
                          ),
                        ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Volumes du compte reçus en direct (`stats:update`).
class _AccountCard extends StatelessWidget {
  const _AccountCard(this.account);
  final AccountStats account;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget figure(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.muted, fontSize: 12)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ],
    );
    final ratio = account.ratio;
    final withCredit = account.ratioWithCredit;
    return Section(
      title: 'Mon compte · en direct',
      children: [
        Wrap(
          spacing: 28,
          runSpacing: 12,
          children: [
            figure('Envoyé', formatBytes(account.uploaded)),
            figure('Reçu', formatBytes(account.downloaded)),
            figure('Crédit d’envoi', formatBytes(account.uploadCredit)),
            figure('Ratio', ratio == null ? '—' : formatRatio(ratio)),
            if (withCredit != null)
              figure('Ratio avec crédit', formatRatio(withCredit)),
          ],
        ),
      ],
    );
  }
}

/// Compteurs de non-lus du site (`unread:update`).
class _CountersRow extends StatelessWidget {
  const _CountersRow(this.counters);
  final UnreadCounters counters;

  static const _icons = {
    'privateMessages': Icons.mail_outline_rounded,
    'channelMessages': Icons.forum_outlined,
    'pendingRequests': Icons.person_add_alt_outlined,
    'staffMessages': Icons.shield_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final MapEntry(key: k, value: (label, _))
            in UnreadCounters.kinds.entries)
          StatPill(
            icon: _icons[k]!,
            color: (counters.counts[k] ?? 0) > 0 ? c.accent : c.muted,
            label: '$label : ${counters.counts[k] ?? 0}',
          ),
      ],
    );
  }
}

/// Icône selon le type de notification du site.
IconData _iconFor(String type) => switch (type) {
  'vtr_initialized' => Icons.savings_outlined,
  'token_attribution' => Icons.toll_outlined,
  'ic_level_up' => Icons.trending_up_rounded,
  'channel_reply' || 'channel_mention' => Icons.forum_outlined,
  final t when t.contains('message') => Icons.mail_outline_rounded,
  final t when t.contains('torrent') => Icons.movie_outlined,
  final t when t.contains('comment') => Icons.chat_bubble_outline_rounded,
  _ => Icons.notifications_none_rounded,
};

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({
    required this.notification,
    required this.onOpenChannel,
  });
  final AppNotification notification;
  final VoidCallback onOpenChannel;

  /// Ouvre la cible de la notification : torrent présent dans Transmission,
  /// salon dans l'application, sinon la page du site dans le navigateur.
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final link = notification.link;
    if (link == null || link.isEmpty) return;
    final uri = Uri.parse(link);
    final segments = uri.pathSegments;
    if (segments.length == 2 && segments.first == 'torrents') {
      final hash = segments[1].toLowerCase();
      final torrent = ref
          .read(torrentsProvider)
          .byId
          .values
          .where((t) => t.hash == hash)
          .firstOrNull;
      if (torrent != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                TorrentDetailPage(id: torrent.id, name: torrent.name),
          ),
        );
        return;
      }
    }
    final channel = int.tryParse(uri.queryParameters['channel'] ?? '');
    if (segments.firstOrNull == 'messages' && channel != null) {
      ref.read(notificationsProvider.notifier).joinChannel(channel);
      onOpenChannel();
      return;
    }
    await launchUrl(
      uri.hasScheme ? uri : Uri.parse('https://c411.org$link'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final c = context.colors;
    final unread = !n.isRead;
    return InkWell(
      onTap: n.link == null ? null : () => _open(context, ref),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: unread ? c.accent.withValues(alpha: 0.15) : c.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconFor(n.type),
                size: 18,
                color: unread ? c.accent : c.muted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (unread)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          n.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _when(n.receivedAt),
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                    ],
                  ),
                  if (n.body != null && n.body!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      n.body!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (n.link != null)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 8),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: c.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Salon de discussion en direct (lecture seule).
class _ChatView extends StatefulWidget {
  const _ChatView({required this.state});
  final NotificationsState state;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Fait disparaître les « … écrit » expirés même sans nouvel événement.
    _tick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (widget.state.typing.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final typing = [
      for (final MapEntry(:key, :value) in widget.state.typing.entries)
        if (value.isAfter(now)) key,
    ];
    final state = widget.state;
    final chat = [
      for (final m in state.chat)
        if (m.channelId == state.channelId) m,
    ];

    final info = state.channelInfo[state.channelId];
    final pinned = state.pinned[state.channelId];

    return Column(
      children: [
        _ChannelPicker(state: state),
        if (info?.description != null || pinned != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (info?.description != null)
                  Text(
                    info!.description!,
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                if (pinned != null)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.push_pin_outlined, size: 16, color: c.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          // Même mise en forme que les messages (liens
                          // cliquables) ; hauteur ajustée au contenu.
                          child: Text.rich(
                            TextSpan(
                              children: [
                                ...chatSpans(pinned.content, colors: c),
                                TextSpan(
                                  text: '\n— ${pinned.username}',
                                  style: TextStyle(color: c.muted),
                                ),
                              ],
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (state.chatError != null) ErrorBanner(state.chatError!),
        if (state.historyLoading) const LinearProgressIndicator(minHeight: 2),
        Divider(height: 1, color: c.border),
        Expanded(
          child: chat.isEmpty
              ? const EmptyState(
                  Icons.forum_outlined,
                  'Aucun message dans ce salon pour le moment.',
                )
              // Texte sélectionnable sur tout le fil (copier un message…).
              : SelectionArea(
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: chat.length,
                    itemBuilder: (_, i) {
                      final index = chat.length - 1 - i;
                      return _ChatTile(
                        message: chat[index],
                        previous: index > 0 ? chat[index - 1] : null,
                      );
                    },
                  ),
                ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          child: typing.isEmpty
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Text(
                    typing.length == 1
                        ? '${typing.first} écrit…'
                        : typing.length <= 3
                        ? '${typing.join(', ')} écrivent…'
                        : '${typing.length} personnes écrivent…',
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
        ),
        _Composer(state: state),
      ],
    );
  }
}

/// Choix du salon : ceux déjà rencontrés, plus la saisie d'un numéro.
class _ChannelPicker extends ConsumerWidget {
  const _ChannelPicker({required this.state});
  final NotificationsState state;

  String label(int id) =>
      state.channelInfo[id]?.name ??
      (id == NotificationsNotifier.defaultChannel ? 'Général' : 'Salon $id');

  Future<void> _askId(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final id = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rejoindre un salon'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Numéro du salon'),
          onSubmitted: (v) => Navigator.pop(context, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Rejoindre'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (id != null) ref.read(notificationsProvider.notifier).joinChannel(id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Salon par défaut d'abord, puis l'ordre de l'API, puis les inconnus.
    final known = state.channelInfo.values.toList()
      ..sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));
    final channels = [
      ...known.map((c) => c.id),
      ...(state.channels
          .where((id) => !state.channelInfo.containsKey(id))
          .toList()
        ..sort()),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ChipRow<int>(
              items: channels,
              selected: state.channelId,
              label: label,
              onSelected: ref.read(notificationsProvider.notifier).joinChannel,
            ),
          ),
          IconButton(
            tooltip: 'Rejoindre un autre salon',
            icon: const Icon(Icons.add_comment_outlined, size: 20),
            onPressed: () => _askId(context, ref),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

const _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];
const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// « Aujourd'hui », « Hier », « vendredi 16 octobre » (+ année si besoin).
String dayLabel(DateTime d) {
  final day = d.toLocal();
  final now = DateTime.now();
  if (_sameDay(day, now)) return 'Aujourd’hui';
  if (_sameDay(day, now.subtract(const Duration(days: 1)))) return 'Hier';
  final label =
      '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';
  return day.year == now.year ? label : '$label ${day.year}';
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator(this.date);
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              dayLabel(date),
              style: TextStyle(
                color: c.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(color: c.border)),
        ],
      ),
    );
  }
}

/// Heure d'une notification : relative le jour même, sinon HH:mm (le jour
/// figure dans le séparateur).
String _when(DateTime d) {
  final t = d.toLocal();
  if (_sameDay(t, DateTime.now())) return formatAgo(d);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

const _roles = {'admin': 'Admin', 'moderator': 'Modo', 'staff': 'Staff'};

/// Message du salon. Les messages consécutifs d'un même auteur (moins de
/// 5 min d'écart) sont regroupés : avatar et en-tête seulement sur le premier.
class _ChatTile extends ConsumerWidget {
  const _ChatTile({required this.message, this.previous});
  final ChatMessage message;

  /// Message précédent (plus ancien) du salon.
  final ChatMessage? previous;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = message;
    final p = previous;
    final c = context.colors;
    final (myId, me) = ref.watch(
      notificationsProvider.select((s) => (s.myUserId, s.myUsername)),
    );

    final newDay =
        p == null || !_sameDay(p.createdAt.toLocal(), m.createdAt.toLocal());
    final startsGroup =
        newDay ||
        p.username != m.username ||
        p.isSystem != m.isSystem ||
        m.createdAt.difference(p.createdAt).inMinutes >= 5;
    final mine =
        m.tempId != null && m.sendState != SendState.sent ||
        (myId != null && m.senderId == myId);
    final mentioned = !mine && mentions(m.content, me);
    final time = m.createdAt.toLocal();
    final hhmm =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';

    final initial = m.username.isEmpty ? '?' : m.username[0].toUpperCase();
    final fallback = CircleAvatar(
      radius: 16,
      backgroundColor: c.surfaceAlt,
      child: Text(
        initial,
        style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
      ),
    );
    final avatar = m.avatarUrl == null
        ? fallback
        : ClipOval(
            child: CachedNetworkImage(
              imageUrl: m.avatarUrl!,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              memCacheWidth: 64,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
          );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (startsGroup)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  m.username,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: mine ? c.accent : c.text,
                  ),
                ),
                if (_roles[m.role] != null)
                  Tag(_roles[m.role]!, color: c.danger),
                if (m.badge != null)
                  Tag(
                    m.badge!,
                    color: m.badgeColor != null ? Color(m.badgeColor!) : null,
                  ),
                Text(hhmm, style: TextStyle(color: c.muted, fontSize: 11.5)),
              ],
            ),
          ),
        if (m.replyTo != null)
          Container(
            margin: const EdgeInsets.only(top: 2, bottom: 4),
            padding: const EdgeInsets.fromLTRB(8, 2, 0, 2),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: c.accent.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
            ),
            child: Text(
              m.replyTo!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ),
        if (m.isDeleted)
          Text(
            'Message supprimé',
            style: TextStyle(
              color: c.muted,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          )
        else if (m.content.isNotEmpty)
          Text.rich(
            TextSpan(
              children: [
                ...chatSpans(m.content, colors: c, me: me),
                if (m.isEdited)
                  TextSpan(
                    text: '  (modifié)',
                    style: TextStyle(color: c.muted, fontSize: 11.5),
                  ),
              ],
            ),
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: m.isSystem ? c.muted : c.text,
              fontStyle: m.isSystem ? FontStyle.italic : null,
            ),
          ),
        if (!m.isDeleted)
          for (final url in m.images)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 320,
                    maxHeight: 240,
                  ),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    memCacheWidth: 640,
                    errorWidget: (_, _, _) => Text(
                      url,
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
        if (m.reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final r in m.reactions) _ReactionChip(reaction: r),
              ],
            ),
          ),
      ],
    );

    // Nos messages : liseré d'accent ; ceux qui nous mentionnent : fond teinté.
    final Color? bar = mine
        ? c.accent.withValues(alpha: 0.6)
        : mentioned
        ? c.warning
        : null;
    final tile = Container(
      decoration: BoxDecoration(
        color: mentioned ? c.warning.withValues(alpha: 0.08) : null,
        border: Border(
          left: BorderSide(color: bar ?? Colors.transparent, width: 3),
        ),
      ),
      padding: EdgeInsets.fromLTRB(13, startsGroup ? 8 : 1, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: startsGroup
                ? avatar
                // Heure discrète à la place de l'avatar dans un groupe.
                : Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      hhmm,
                      style: TextStyle(
                        color: c.muted.withValues(alpha: 0.7),
                        fontSize: 9.5,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(child: body),
        ],
      ),
    );

    final withState = switch (m.sendState) {
      SendState.sent => tile,
      SendState.pending => Opacity(opacity: 0.55, child: tile),
      SendState.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(opacity: 0.55, child: tile),
          Padding(
            padding: const EdgeInsets.fromLTRB(58, 0, 16, 6),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Icon(Icons.error_outline, size: 14, color: c.danger),
                Text(
                  'Non envoyé : ${m.sendError ?? 'erreur'}',
                  style: TextStyle(color: c.danger, fontSize: 12),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(notificationsProvider.notifier).retry(m),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ],
      ),
    };

    return newDay
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_DaySeparator(m.createdAt), withState],
          )
        : withState;
  }
}

/// Réaction : emoji et nombre ; bordure d'accent si l'on a soi-même réagi,
/// liste des membres au survol.
class _ReactionChip extends ConsumerWidget {
  const _ReactionChip({required this.reaction});
  final ChatReaction reaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mine = reaction.isMine(
      ref.watch(notificationsProvider.select((s) => s.myUserId)),
    );
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: mine ? c.accent.withValues(alpha: 0.15) : c.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: mine ? c.accent : Colors.transparent),
      ),
      child: Text(
        '${reaction.emoji} ${reaction.count}',
        style: const TextStyle(fontSize: 12),
      ),
    );
    if (reaction.usernames.isEmpty) return chip;
    return Tooltip(message: reaction.usernames.join(', '), child: chip);
  }
}

/// Zone de saisie : Entrée envoie, Maj+Entrée passe à la ligne.
class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.state});
  final NotificationsState state;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _text = TextEditingController();
  late final _focus = FocusNode(
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed) {
        _send();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    _text.clear();
    ref.read(notificationsProvider.notifier).sendMessage(text);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.state;
    final info = s.channelInfo[s.channelId];
    final connected = s.status == SocketStatus.connected;
    final canWrite = info?.canWrite ?? true;

    if (!canWrite) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: Text(
          'Lecture seule dans ce salon',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 12.5),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _focus,
                enabled: connected,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: connected
                      ? 'Message à ${info?.name ?? 'ce salon'}'
                      : 'Connexion au salon…',
                  helperText: (info?.slowModeSeconds ?? 0) > 0
                      ? 'Mode lent : un message toutes les '
                            '${info!.slowModeSeconds} s'
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Envoyer',
              onPressed: connected && _text.text.trim().isNotEmpty
                  ? _send
                  : null,
              icon: const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
