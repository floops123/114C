import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../core/format.dart';
import '../state/release_watch.dart';
import '../state/releases.dart';
import 'release_detail_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Nouveautés : les dernières sorties repérées par la veille des trackers.
class ReleaseWatchPage extends ConsumerStatefulWidget {
  const ReleaseWatchPage({super.key});

  @override
  ConsumerState<ReleaseWatchPage> createState() => _ReleaseWatchPageState();
}

class _ReleaseWatchPageState extends ConsumerState<ReleaseWatchPage> {
  /// Nouvelles à l'ouverture : restent signalées le temps de la visite, même
  /// une fois marquées comme vues.
  late final Set<String> _highlight;

  @override
  void initState() {
    super.initState();
    _highlight = {
      for (final i in ref.read(releaseWatchProvider).items)
        if (i.isNew) i.key,
    };
    final notifier = ref.read(releaseWatchProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => notifier.markAllSeen());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(releaseWatchProvider);
    final config = ref.watch(watchConfigProvider);
    final notifier = ref.read(releaseWatchProvider.notifier);
    final small = TextStyle(fontSize: 12, color: c.muted);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveautés'),
        actions: [
          state.checking
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  tooltip: 'Vérifier maintenant',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: notifier.check,
                ),
          PopupMenuButton<void>(
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: state.items.isNotEmpty,
                onTap: notifier.clear,
                child: const Text('Vider la liste'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Panel(
              radius: 14,
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                initiallyExpanded: !config.enabled,
                title: Text(config.enabled
                    ? 'Veille active, toutes les ${intervalLabel(config.minutes)}'
                    : 'Veille désactivée'),
                subtitle: Text(_status(state), style: small),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: const [WatchSettingsPanel()],
              ),
            ),
          ),
          for (final MapEntry(key: t, value: e) in state.errors.entries)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ErrorBanner(e.contains(t.label) ? e : '${t.label} : $e'),
            ),
          if (state.items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: EmptyState(
                Icons.new_releases_outlined,
                config.enabled
                    ? 'Aucune sortie pour l’instant : la liste se remplit au '
                        'prochain relevé.'
                    : 'Active la veille pour suivre les nouvelles sorties '
                        'des trackers.',
              ),
            )
          else
            for (final item in state.items)
              _WatchRow(
                item: item,
                highlight: item.isNew || _highlight.contains(item.key),
              ),
        ],
      ),
    );
  }

  String _status(WatchState s) {
    final last = s.lastCheck;
    if (s.checking) return 'Relevé en cours…';
    if (last == null) return 'Aucun relevé pour l’instant';
    return 'Dernier relevé ${formatAgo(last)} · ${s.items.length} sorties';
  }
}

String intervalLabel(int minutes) =>
    minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h';

/// Réglages de la veille, partagés par Nouveautés et Réglages. Appliqués
/// tout de suite, sans « Enregistrer ».
class WatchSettingsPanel extends ConsumerWidget {
  const WatchSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final config = ref.watch(watchConfigProvider);
    final configured = ref.watch(trackersProvider).keys.toList();
    final notifier = ref.read(watchConfigProvider.notifier);
    final small = TextStyle(fontSize: 12, color: c.muted);

    void toggleTracker(Tracker t, bool on) {
      final next = {...config.trackers ?? configured};
      on ? next.add(t) : next.remove(t);
      // Tous cochés : « tous », y compris ceux ajoutés plus tard.
      final all = configured.every(next.contains);
      notifier.set(config.copyWith(trackers: () => all ? null : next));
    }

    Future<void> toggleNotify(bool on) async {
      final messenger = ScaffoldMessenger.of(context);
      notifier.set(config.copyWith(notify: on));
      if (on && !await ref.read(systemNotifierProvider).requestPermission()) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Le système n’autorise pas les notifications de '
                'l’application')));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Vérifier les nouveaux torrents'),
          subtitle: Text('Tant que l’application est ouverte', style: small),
          value: config.enabled,
          onChanged: (v) => notifier.set(config.copyWith(enabled: v)),
        ),
        Row(children: [
          const Text('Toutes les'),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: WatchConfig.choices.contains(config.minutes)
                ? config.minutes
                : null,
            hint: Text(intervalLabel(config.minutes)),
            items: [
              for (final m in WatchConfig.choices)
                DropdownMenuItem(value: m, child: Text(intervalLabel(m))),
            ],
            onChanged: (m) => notifier.set(config.copyWith(minutes: m)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Trackers surveillés', style: small),
        const SizedBox(height: 6),
        if (configured.isEmpty)
          Text('Aucun tracker configuré : renseigne une clé dans les Réglages.',
              style: small)
        else
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final t in configured)
              FilterChip(
                label: Text(t.label),
                selected: config.watches(t),
                onSelected: (on) => toggleTracker(t, on),
              ),
          ]),
        if (configured.isNotEmpty && !configured.any(config.watches))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Aucun tracker surveillé', style: small),
          ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Notification à l’arrivée'),
          subtitle: Text('Notification du système pour chaque relevé '
              'qui apporte des nouveautés', style: small),
          value: config.notify,
          onChanged: toggleNotify,
        ),
      ],
    );
  }
}

class _WatchRow extends ConsumerWidget {
  const _WatchRow({required this.item, required this.highlight});
  final WatchedRelease item;
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final r = item.release;
    final small = TextStyle(fontSize: 11.5, color: c.muted);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: highlight ? c.accent.withValues(alpha: 0.6) : c.border),
        ),
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ReleaseDetailPage(release: r))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 5),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(spacing: 6, children: [
                        if (highlight) Tag('NOUVEAU', color: c.success),
                        Tag(r.tracker.label, color: c.accent),
                        if (r.subcategory.isNotEmpty) Tag(r.subcategory),
                        Text(formatBytes(r.size), style: small),
                        Text('▲ ${r.seeders}', style: small),
                        Text('▼ ${r.leechers}', style: small),
                        Text(formatAgo(r.createdAt), style: small),
                      ]),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Envoyer à Transmission',
                icon: const Icon(Icons.download_rounded),
                onPressed: () => sendToTransmission(context, ref, r),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
