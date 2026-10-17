import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../core/format.dart';
import '../state/cross_seed.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ordre d'affichage des catégories de résultats.
const _order = [
  CrossSeedStatus.match,
  CrossSeedStatus.added,
  CrossSeedStatus.searching,
  CrossSeedStatus.waiting,
  CrossSeedStatus.mismatch,
  CrossSeedStatus.error,
  CrossSeedStatus.present,
  CrossSeedStatus.notFound,
];

class CrossSeedPage extends ConsumerStatefulWidget {
  const CrossSeedPage({super.key});

  @override
  ConsumerState<CrossSeedPage> createState() => _CrossSeedPageState();
}

class _CrossSeedPageState extends ConsumerState<CrossSeedPage> {
  /// null = toutes les catégories.
  CrossSeedStatus? _filter;

  Future<void> _addAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await ref.read(crossSeedProvider.notifier).addAll();
    messenger.showSnackBar(SnackBar(
        content: Text('$n torrent(s) ajouté(s) en cross-seed')));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(crossSeedProvider);
    final notifier = ref.read(crossSeedProvider.notifier);
    final trackers = ref.watch(trackersProvider).keys.toList();
    final directions = ref.watch(crossSeedDirectionsProvider);
    final setDirections = ref.read(crossSeedDirectionsProvider.notifier);
    final from = <Tracker?>[...Tracker.values, null];
    final to = [for (final t in trackers) if (directions.to(t)) t];
    // Au moins un sens possible : une origine et une destination différentes.
    final ready = from.any((f) =>
        directions.from(f) && to.any((t) => t != f));
    final c = context.colors;
    final matches = state.count(CrossSeedStatus.match);
    final total = state.items.length;

    final items = [
      for (final s in _order)
        for (final i in state.items)
          if (i.status == s && (_filter == null || _filter == s)) i,
    ];
    final present = {for (final i in state.items) i.status};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cross-seed'),
        actions: [
          if (state.running)
            TextButton.icon(
              onPressed: notifier.stop,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Arrêter'),
            )
          else
            PopupMenuButton<bool>(
              tooltip: 'Analyser',
              enabled: ready,
              onSelected: (force) => notifier.scan(force: force),
              itemBuilder: (_) => const [
                PopupMenuItem(value: false, child: Text('Analyser')),
                PopupMenuItem(
                    value: true,
                    child: Text('Tout réanalyser (ignorer la mémoire)')),
              ],
              icon: const Icon(Icons.more_vert_rounded),
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cherche sur les trackers de destination les torrents '
                'terminés de Transmission venant des trackers d’origine : '
                'même nom, même taille, mêmes fichiers. Une correspondance '
                's’ajoute dans le dossier existant, sans rien retélécharger '
                '(étiquette « ${CrossSeedNotifier.label} »).',
                style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
              ),
              _Choices<Tracker?>(
                title: 'Torrents venant de',
                items: from,
                label: (t) => t?.label ?? 'Autres trackers',
                selected: directions.from,
                onToggle: state.running ? null : setDirections.toggleFrom,
              ),
              _Choices<Tracker>(
                title: 'À partager sur',
                items: trackers,
                label: (t) => t.label,
                selected: directions.to,
                onToggle: state.running ? null : setDirections.toggleTo,
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: state.running || !ready ? null : notifier.scan,
                    icon: state.running
                        ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.onAccent))
                        : const Icon(Icons.manage_search_rounded, size: 18),
                    label: Text(state.running
                        ? 'Analyse ${state.done} / $total'
                        : 'Analyser'),
                  ),
                ),
                if (matches > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addAll,
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: Text('Tout ajouter ($matches)'),
                    ),
                  ),
                ],
              ]),
              if (state.running && total > 0) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: state.done / total,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
              if (state.skipped > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '${state.skipped} analyse(s) récente(s) non refaite(s) '
                  '(moins de 7 jours) — « Tout réanalyser » dans le menu.',
                  style: TextStyle(color: c.muted, fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
        if (state.error != null) ErrorBanner(state.error!),
        if (state.items.isNotEmpty)
          ChipRow<CrossSeedStatus?>(
            items: [null, ..._order.where(present.contains)],
            selected: _filter,
            label: (s) => s == null
                ? 'Tous (${state.items.length})'
                : '${s.label} (${state.count(s)})',
            onSelected: (s) => setState(() => _filter = s),
          ),
        const SizedBox(height: 6),
        Divider(height: 1, color: c.border),
        Expanded(
          child: state.items.isEmpty
              ? EmptyState(
                  Icons.compare_arrows_rounded,
                  state.running
                      ? 'Lecture des torrents de Transmission…'
                      : state.skipped > 0
                          ? 'Rien de nouveau à analyser.'
                          : 'Lance une analyse pour trouver les torrents à '
                              'partager aussi sur tes autres trackers.',
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => _ItemTile(item: items[i]),
                ),
        ),
      ]),
    );
  }
}

/// Ligne de cases à cocher (origines ou destinations).
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.title,
    required this.items,
    required this.label,
    required this.selected,
    required this.onToggle,
  });
  final String title;
  final List<T> items;
  final String Function(T) label;
  final bool Function(T) selected;
  final ValueChanged<T>? onToggle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(title,
                style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
          ),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final item in items)
              FilterChip(
                label: Text(label(item)),
                selected: selected(item),
                onSelected:
                    onToggle == null ? null : (_) => onToggle!(item),
              ),
          ]),
        ],
      );
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item});
  final CrossSeedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final (Color color, IconData icon) = switch (item.status) {
      CrossSeedStatus.match => (c.accent, Icons.add_link_rounded),
      CrossSeedStatus.added => (c.success, Icons.check_circle_rounded),
      CrossSeedStatus.present => (c.success, Icons.check_rounded),
      CrossSeedStatus.searching => (c.info, Icons.manage_search_rounded),
      CrossSeedStatus.mismatch => (c.warning, Icons.difference_outlined),
      CrossSeedStatus.error => (c.danger, Icons.error_outline_rounded),
      _ => (c.muted, Icons.remove_rounded),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tag('${item.source?.label ?? 'Autre'} → ${item.target.label}',
                      color: c.accent),
                  // L'état a toujours un libellé, pas seulement une couleur.
                  Text(item.status.label,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                  Text(formatBytes(item.size),
                      style: TextStyle(fontSize: 11.5, color: c.muted)),
                ],
              ),
              if (item.detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(item.detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: c.muted)),
                ),
            ],
          ),
        ),
        if (item.status == CrossSeedStatus.match)
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final error =
                  await ref.read(crossSeedProvider.notifier).add(item);
              messenger.showSnackBar(SnackBar(
                  content: Text(error ??
                      'Ajouté : ${item.name} (${item.target.label})')));
            },
            child: const Text('Ajouter'),
          ),
      ]),
    );
  }
}
