import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/c411_socket.dart';
import '../core/format.dart';
import '../state/c411_overview.dart';
import '../state/notifications.dart';
import '../state/torrents.dart';
import 'c411_account.dart';
import 'chat_page.dart';
import 'day_label.dart';
import 'theme.dart';
import 'torrent_detail_page.dart';
import 'zen_page.dart';
import 'widgets.dart';

/// Notifications du site C411 : état de la connexion, compte en direct,
/// compteurs, puis les notifications par jour (le salon a son onglet).
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final c = context.colors;

    return Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'C411',
            subtitle: state.unread > 0
                ? Text(
                    '${state.unread} notification${state.unread > 1 ? 's' : ''} '
                    'non lue${state.unread > 1 ? 's' : ''}',
                    style: TextStyle(color: c.accent, fontSize: 12.5))
                : Text('Notifications et compte',
                    style: TextStyle(color: c.muted, fontSize: 12.5)),
            actions: [
              if (state.status == SocketStatus.unauthorized ||
                  state.status == SocketStatus.disconnected)
                IconButton(
                  tooltip: 'Se reconnecter',
                  icon: const Icon(Icons.wifi_find_rounded),
                  onPressed: notifier.reconnect,
                ),
              if (state.configured)
                IconButton(
                  tooltip: 'Rafraîchir',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () {
                    notifier.refreshNotifications();
                    ref.invalidate(c411OverviewProvider);
                  },
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
          Expanded(
            child: !state.configured && state.items.isEmpty
                ? const EmptyState(
                    Icons.notifications_off_outlined,
                    'Ajoute tes cookies de session C411 dans les réglages\n'
                    'pour recevoir les notifications du site.',
                  )
                : _NotificationsView(state: state),
          ),
        ],
      ),
    );
  }
}

/// Haut de page (connexion, compte, compteurs), puis les
/// notifications groupées par jour, paginées (les plus récentes d'abord ;
/// « Afficher plus » pour remonter l'historique).
class _NotificationsView extends ConsumerStatefulWidget {
  const _NotificationsView({required this.state});
  final NotificationsState state;

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
    final overview = ref.watch(c411OverviewProvider);
    final o = overview.value;

    final top = <Widget>[
      if (!state.configured)
        Text(
          'Hors ligne : historique local. Ajoute tes cookies de session dans '
          'les réglages pour recevoir les nouvelles.',
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: _ConnectionTile(status: state.status),
      ),
      if (o != null && (o.account != null || o.level != null))
        C411ProfileCard(account: o.account, level: o.level),
      if (state.account != null) _AccountCard(state.account!),
      if (state.counters != null) _Counters(state.counters!),
      if (o != null && (o.balance != null || o.forecast != null || o.history != null))
        const ZenPageButton(),
      if (o != null && (o.balance != null || o.forecast != null || o.history != null))
        ZenSection(balance: o.balance, forecast: o.forecast, history: o.history),
      if (o?.revivals case final revivals? when revivals.isNotEmpty)
        RevivalsCard(
          revivals: revivals,
          inTransmission: ref.watch(torrentsProvider.select((t) => t.loaded ? t.hashes : null)),
        ),
      if (o?.leaderboard case final board?)
        LeaderboardCard(board: board, me: o?.account?.username),
      if (overview.hasError)
        ErrorBanner('Compte C411 : ${overview.error}'),
    ];

    return RefreshIndicator(
      onRefresh: () => Future.wait([
        notifier.refreshNotifications(),
        ref.refresh(c411OverviewProvider.future).catchError((Object _) => null),
      ]),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (state.notifError != null) ErrorBanner(state.notifError!),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final w in top) ...[w, const SizedBox(height: 12)],
              ],
            ),
          ),
          if (state.items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
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
                  !sameDay(
                    shown[i - 1].receivedAt.toLocal(),
                    n.receivedAt.toLocal(),
                  ))
                DaySeparator(n.receivedAt),
              _NotificationTile(notification: n),
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

/// État de la connexion au site en direct (toujours une icône et un
/// libellé, pas seulement une couleur).
class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({required this.status});
  final SocketStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color color, IconData icon, String detail) = switch (status) {
      SocketStatus.connected => (c.success, Icons.wifi_rounded, 'Notifications en direct'),
      SocketStatus.connecting => (c.muted, Icons.sync_rounded, 'Connexion au site…'),
      SocketStatus.disconnected => (c.warning, Icons.wifi_off_rounded, 'Nouvel essai bientôt'),
      SocketStatus.unauthorized => (c.danger, Icons.lock_outline_rounded, 'Cookie de session refusé'),
    };
    return Container(
      height: 60,
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color.lerp(color, c.border, 0.5)!),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _Bubble(icon: icon, color: color),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(status.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: color)),
              Text(detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.muted)),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Pastille ronde colorée portant une icône.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.icon, required this.color, this.size = 36});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // Teinte opaque (mélange avec la surface), sans transparence.
        color: Color.lerp(color, c.surface, 0.8),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size * 0.52, color: color),
    );
  }
}

/// Mon compte en direct (`stats:update`) : tuiles colorées. Le ratio change de
/// couleur selon sa valeur (rouge sous 1, ambre sous 2, vert au-delà).
class _AccountCard extends StatelessWidget {
  const _AccountCard(this.account);
  final AccountStats account;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Color ratioColor(double? r) => r == null
        ? c.muted
        : r < 1
            ? c.danger
            : r < 2
                ? c.warning
                : c.success;
    final ratio = account.ratio;
    final withCredit = account.ratioWithCredit;
    final tiles = [
      _Figure(Icons.north_rounded, c.upload, 'Envoyé', formatBytes(account.uploaded)),
      _Figure(Icons.south_rounded, c.download, 'Reçu', formatBytes(account.downloaded)),
      _Figure(Icons.savings_rounded, c.accent, 'Crédit d’envoi',
          formatBytes(account.uploadCredit)),
      _Figure(Icons.balance_rounded, ratioColor(ratio), 'Ratio',
          ratio == null ? '—' : formatRatio(ratio)),
      if (withCredit != null)
        _Figure(Icons.workspace_premium_rounded, ratioColor(withCredit),
            'Ratio avec crédit', formatRatio(withCredit)),
    ];
    return Panel(
      radius: 16,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.person_rounded, size: 18, color: c.accent),
            const SizedBox(width: 6),
            const Text('Mon compte',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Tag('EN DIRECT', color: c.success),
          ]),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            // Tuiles de même largeur : 2 par ligne sur téléphone, toutes sur
            // une ligne si la place le permet.
            final perRow = constraints.maxWidth >= 900
                ? tiles.length
                : constraints.maxWidth >= 560
                    ? 3
                    : 2;
            final width = (constraints.maxWidth - (perRow - 1) * 10) / perRow;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              for (final t in tiles) SizedBox(width: width, child: t),
            ]);
          }),
        ]),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.icon, this.color, this.label, this.value);
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.lerp(color, c.surface, 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color.lerp(color, c.surface, 0.6)!),
      ),
      child: Row(children: [
        _Bubble(icon: icon, color: color, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()])),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: c.muted)),
          ]),
        ),
      ]),
    );
  }
}

/// Compteurs de non-lus du site (`unread:update`) : colorés quand il y a du
/// nouveau.
class _Counters extends StatelessWidget {
  const _Counters(this.counters);
  final UnreadCounters counters;

  static const _icons = {
    'privateMessages': Icons.mail_rounded,
    'channelMessages': Icons.forum_rounded,
    'pendingRequests': Icons.person_add_alt_1_rounded,
    'staffMessages': Icons.shield_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final MapEntry(key: k, value: (label, _))
          in UnreadCounters.kinds.entries)
        Builder(builder: (context) {
          final n = counters.counts[k] ?? 0;
          final color = n > 0 ? c.accent : c.muted;
          return Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            decoration: BoxDecoration(
              color: n > 0 ? Color.lerp(c.accent, c.surface, 0.85) : c.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: n > 0 ? Color.lerp(c.accent, c.surface, 0.5)! : c.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_icons[k], size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, color: c.text)),
              const SizedBox(width: 6),
              Text('$n',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
            ]),
          );
        }),
    ]);
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

/// Couleur d'un type de notification (pastille de la carte).
Color _colorFor(String type, AppColors c) => switch (type) {
  'vtr_initialized' || 'token_attribution' => c.warning,
  'ic_level_up' => c.success,
  'channel_reply' || 'channel_mention' => c.info,
  final t when t.contains('message') => c.accent,
  final t when t.contains('torrent') => c.download,
  final t when t.contains('comment') => c.upload,
  _ => c.muted,
};

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});
  final AppNotification notification;

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
      ChatPage.open(context);
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
    final color = _colorFor(n.type, c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: Material(
        color: unread ? Color.lerp(c.accent, c.surface, 0.92) : c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: unread ? Color.lerp(c.accent, c.surface, 0.5)! : c.border),
        ),
        child: InkWell(
          onTap: n.link == null ? null : () => _open(context, ref),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bubble(icon: _iconFor(n.type), color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                                color: c.accent, shape: BoxShape.circle),
                          ),
                        Expanded(
                          child: Text(n.title,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight:
                                      unread ? FontWeight.w800 : FontWeight.w600)),
                        ),
                        const SizedBox(width: 8),
                        Text(shortTime(n.receivedAt),
                            style: TextStyle(color: c.muted, fontSize: 12)),
                      ]),
                      if (n.body != null && n.body!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(n.body!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.muted, fontSize: 13, height: 1.4)),
                      ],
                    ],
                  ),
                ),
                if (n.link != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 8),
                    child: Icon(Icons.chevron_right_rounded,
                        size: 20, color: c.muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
