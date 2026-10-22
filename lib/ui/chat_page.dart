import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/c411_chat.dart';
import '../api/c411_socket.dart';
import '../state/notifications.dart';
import 'day_label.dart';
import 'home_shell.dart';
import 'rich_text.dart';
import 'theme.dart';
import 'widgets.dart';

/// Salon de discussion C411 : onglet de la navigation principale (ouvert
/// aussi comme page, avec retour, hors de celle-ci).
class ChatPage extends ConsumerWidget {
  const ChatPage({super.key});

  /// Ouvre le salon : l'onglet Salon dans la navigation principale, sinon
  /// une page par-dessus.
  static void open(BuildContext context) {
    if (HomeShell.showChat(context)) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ChatPage()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final viewers = state.viewers[state.channelId];
    final name = state.channelInfo[state.channelId]?.name ??
        (state.channelId == NotificationsNotifier.defaultChannel
            ? 'Général'
            : 'Salon ${state.channelId}');
    final c = context.colors;
    final pushed = Navigator.of(context).canPop();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        top: pushed,
        child: Column(children: [
          PageHeader(
            title: 'Salon',
            subtitle: Text(
                [name, if (viewers != null && viewers > 0) '$viewers en ligne']
                    .join(' · '),
                style: TextStyle(fontSize: 12.5, color: c.success)),
            actions: [
              if (pushed)
                IconButton(
                  tooltip: 'Retour',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              if (state.status == SocketStatus.unauthorized ||
                  state.status == SocketStatus.disconnected)
                IconButton(
                  tooltip: 'Se reconnecter',
                  icon: const Icon(Icons.wifi_find_rounded),
                  onPressed: notifier.reconnect,
                ),
            ],
          ),
          // Sans cookie de session : invitation, sauf messages déjà reçus.
          if (!state.configured && state.chat.isEmpty)
            const Expanded(
              child: EmptyState(
                Icons.forum_outlined,
                'Ajoute tes cookies de session C411 dans les réglages\n'
                'pour rejoindre les salons du site.',
              ),
            )
          else ...[
            Divider(height: 1, color: c.border),
            Expanded(child: _ChatView(state: state)),
          ],
        ]),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
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
                              for (final url in pinned.images)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 240,
                                        maxHeight: 120,
                                      ),
                                      child: _ZoomableImage(
                                        url,
                                        memCacheWidth: 480,
                                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
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
              // Texte sélectionnable sur tout le fil (copier un message…) :
              // glisser à la souris y sélectionne au lieu de faire défiler.
              : MouseSelectsText(
                  child: SelectionArea(
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
        p == null || !sameDay(p.createdAt.toLocal(), m.createdAt.toLocal());
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

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Comme sur le site : pseudo coloré selon le rang (bronze, argent…).
          Text(
            m.username,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: mine ? c.accent : c.tone(m.nameTone),
            ),
          ),
          if (_roles[m.role] != null) Tag(_roles[m.role]!, color: c.danger),
          if (m.badge != null)
            Tag(
              m.badge!,
              color: m.badgeColor != null ? Color(m.badgeColor!) : null,
            ),
        ],
      ),
    );

    final bubbleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (m.replyTo != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            decoration: BoxDecoration(
              color: c.quote,
              borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: c.accent, width: 2)),
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
              children: chatSpans(m.content, colors: c, me: me),
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
                    maxWidth: 300,
                    maxHeight: 220,
                  ),
                  child: _ZoomableImage(
                    url,
                    memCacheWidth: 600,
                    errorWidget: (_, _, _) => Text(
                      url,
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
        // Pied de bulle : réactions, heure, « modifié ».
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final r in m.reactions) _ReactionChip(reaction: r),
              Text(
                m.isEdited ? '$hhmm · modifié' : hhmm,
                style: TextStyle(color: c.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );

    // Nos messages : bulle teintée de vert ; nous mentionnant : bordure orange.
    final bubble = Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
          decoration: BoxDecoration(
            color: mine
                ? Color.alphaBlend(c.accent.withValues(alpha: 0.16), c.bubble)
                : c.bubble,
            borderRadius: BorderRadius.circular(12),
            border: mentioned ? Border.all(color: c.warning, width: 1.2) : null,
          ),
          child: bubbleContent,
        ),
      ),
    );

    final tile = Padding(
      padding: EdgeInsets.fromLTRB(12, startsGroup ? 10 : 3, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 32, child: startsGroup ? avatar : null),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [if (startsGroup) header, bubble],
            ),
          ),
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
            children: [DaySeparator(m.createdAt), withState],
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
                  filled: true,
                  fillColor: c.bubble,
                  // Bordure verte, comme la zone de saisie du site.
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: c.accent.withValues(alpha: 0.45),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.accent, width: 1.4),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.border),
                  ),
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

/// Image d'un message : un clic l'ouvre en grand (zoom à la molette ou au
/// pincement), un clic à côté ou Échap la referme.
class _ZoomableImage extends StatelessWidget {
  const _ZoomableImage(this.url, {required this.memCacheWidth, required this.errorWidget});
  final String url;
  final int memCacheWidth;
  final LoadingErrorWidgetBuilder errorWidget;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.zoomIn,
        child: GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            barrierColor: Colors.black87,
            builder: (context) => GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            memCacheWidth: memCacheWidth,
            errorWidget: errorWidget,
          ),
        ),
      );
}
