import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../core/format.dart';
import '../state/release_watch.dart';
import '../state/releases.dart';
import 'content_art.dart';
import 'quota_notice.dart';
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

  /// Type de contenu affiché ; null : tous.
  ContentKind? _kind;

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
    final kinds = {for (final i in state.items) i.key: ContentKind.of(i.release)};
    final counts = <ContentKind, int>{};
    for (final k in kinds.values) {
      counts[k] = (counts[k] ?? 0) + 1;
    }
    // Un type filtré qui n'a plus de sortie (liste vidée) : tout.
    final kind = counts.containsKey(_kind) ? _kind : null;
    final shown = [
      for (final i in state.items)
        if (kind == null || kinds[i.key] == kind) i,
    ];

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
          QuotaNotice(
            trackers: ref.watch(trackersProvider).keys,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
          else ...[
            if (counts.length > 1)
              _KindFilter(
                counts: counts,
                total: state.items.length,
                selected: kind,
                onSelected: (k) => setState(() => _kind = k),
              ),
            for (final item in shown)
              _WatchRow(
                item: item,
                kind: kinds[item.key]!,
                highlight: item.isNew || _highlight.contains(item.key),
              ),
          ],
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

/// Filtres par type de contenu, avec le nombre de sorties de chacun.
class _KindFilter extends StatelessWidget {
  const _KindFilter({
    required this.counts,
    required this.total,
    required this.selected,
    required this.onSelected,
  });
  final Map<ContentKind, int> counts;
  final int total;
  final ContentKind? selected;
  final ValueChanged<ContentKind?> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kinds = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(spacing: 6, children: [
        ChoiceChip(
          label: Text('Tout · $total'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final k in kinds)
          ChoiceChip(
            avatar: Icon(k.icon,
                size: 16, color: selected == k ? c.onAccent : k.colors(c).first),
            label: Text('${k.label} · ${counts[k]}'),
            selected: selected == k,
            onSelected: (_) => onSelected(selected == k ? null : k),
          ),
      ]),
    );
  }
}

/// Vignette du type de contenu : dégradé et icône, reconnaissables d'un
/// coup d'œil dans la liste.
class _KindTile extends StatelessWidget {
  const _KindTile(this.kind);
  final ContentKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = kind.colors(context.colors);
    return Tooltip(
      message: kind.label,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: Icon(kind.icon, size: 24, color: Colors.white),
      ),
    );
  }
}

/// Catégorie telle que le tracker la range : « Jeux Vidéo › Windows » (C411 :
/// catégorie et sous-catégorie), « Movies/HD » (Torznab), sinon le type.
String categoryLabel(Release r, ContentKind kind) {
  final sub = r.subcategory.trim();
  final parent = r.categories.where((c) => c.trim().isNotEmpty && c != sub).firstOrNull;
  if (sub.isNotEmpty && parent != null && !sub.toLowerCase().contains(parent.toLowerCase())) {
    return '$parent › $sub';
  }
  if (sub.isNotEmpty) return sub;
  // Torznab : la plus précise (« Movies/HD » plutôt que « Movies »).
  final precise = [...r.categories]..sort((a, b) => b.length.compareTo(a.length));
  return precise.firstOrNull ?? kind.label;
}

/// Étiquette de catégorie : icône du type et nom, à la couleur du type.
class _KindTag extends StatelessWidget {
  const _KindTag(this.kind, this.label);
  final ContentKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = kind.colors(c).first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Color.lerp(color, c.surface, 0.82),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Color.lerp(color, c.surface, 0.5)!),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(kind.icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: c.text, letterSpacing: .3)),
      ]),
    );
  }
}

class _WatchRow extends ConsumerWidget {
  const _WatchRow({required this.item, required this.kind, required this.highlight});
  final WatchedRelease item;
  final ContentKind kind;
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
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(children: [
              _KindTile(kind),
              const SizedBox(width: 12),
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
                        _KindTag(kind, categoryLabel(r, kind)),
                        Tag(r.tracker.label, color: c.accent),
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
