import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/transmission.dart';
import '../core/format.dart';
import '../state/torrents.dart';
import 'theme.dart';
import 'torrent_actions.dart';
import 'torrent_detail_page.dart';
import 'widgets.dart';

/// Couleur associée à l'état d'un torrent, partagée par la liste et le détail.
Color torrentColor(Torrent t, AppColors c) {
  if (t.hasError) return c.danger;
  if (t.isDownloading) return c.accent;
  if (t.isSeeding) return c.success;
  if (t.isChecking) return c.info;
  return t.isComplete ? c.success.withValues(alpha: 0.6) : c.muted;
}

enum _Filter {
  all('Tous'),
  active('Actifs'),
  downloading('En cours'),
  seeding('Partage'),
  complete('Terminés'),
  queued('En file'),
  stopped('Arrêtés'),
  stalled('Bloqués'),
  error('Erreurs');

  const _Filter(this.label);
  final String label;

  bool accepts(Torrent t) => switch (this) {
        all => true,
        active => t.isActive,
        downloading => t.isDownloading,
        seeding => t.isSeeding,
        complete => t.isComplete,
        queued => t.isQueued,
        stopped => t.isStopped,
        stalled => t.isStalled,
        error => t.hasError,
      };
}

enum _Sort {
  added('Date d’ajout'),
  name('Nom'),
  queue('File d’attente'),
  progress('Progression'),
  download('Vitesse ↓'),
  upload('Vitesse ↑'),
  ratio('Ratio'),
  uploaded('Envoyé'),
  size('Taille');

  const _Sort(this.label);
  final String label;

  int compare(Torrent a, Torrent b) => switch (this) {
        added => b.addedDate.compareTo(a.addedDate),
        name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        queue => a.queuePosition.compareTo(b.queuePosition),
        progress => a.percentDone.compareTo(b.percentDone),
        download => b.rateDownload.compareTo(a.rateDownload),
        upload => b.rateUpload.compareTo(a.rateUpload),
        ratio => b.ratio.compareTo(a.ratio),
        uploaded => b.uploadedEver.compareTo(a.uploadedEver),
        size => b.totalSize.compareTo(a.totalSize),
      };
}

class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.added;
  String? _label;
  String _query = '';
  final _selected = <int>{};

  void _toggle(int id) => setState(
      () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  Future<void> _addDialog() async {
    final controller = TextEditingController();
    var withOptions = false;
    final link = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Ajouter un torrent'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'Lien magnet ou URL du .torrent'),
                onSubmitted: (v) => Navigator.pop(context, v),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: withOptions,
                onChanged: (v) => setState(() => withOptions = v ?? false),
                title: const Text('Choisir le dossier, les étiquettes…'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Ajouter')),
          ],
        ),
      ),
    );
    controller.dispose();
    if (link == null || link.trim().isEmpty || !mounted) return;
    var options = const AddOptions();
    if (withOptions) {
      final chosen = await askAddOptions(context, ref);
      if (chosen == null || !mounted) return;
      options = chosen;
    }
    var added = false;
    final ok = await runTorrentAction(context, ref, (c) async {
      added = await c.addTorrent(filename: link.trim(), options: options);
    });
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(added ? 'Torrent ajouté' : 'Déjà présent')));
    }
  }

  Future<void> _all(String method, String message) =>
      runTorrentAction(context, ref, (c) => c.action(method, null),
          success: message);

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(transmissionProvider) != null;
    final state = ref.watch(torrentsProvider);
    final notifier = ref.read(torrentsProvider.notifier);
    final c = context.colors;

    final labels = {for (final t in state.byId.values) ...t.labels}.toList()
      ..sort();
    if (_label != null && !labels.contains(_label)) _label = null;
    _selected.removeWhere((id) => !state.byId.containsKey(id));

    final query = _query.toLowerCase();
    final torrents = state.byId.values
        .where((t) =>
            _filter.accepts(t) &&
            (_label == null || t.labels.contains(_label)) &&
            (query.isEmpty || t.name.toLowerCase().contains(query)))
        .toList()
      ..sort(_sort.compare);
    final selection = [
      for (final id in _selected) ?state.byId[id],
    ];

    final header = _selected.isNotEmpty
        ? _SelectionBar(
            torrents: selection,
            onSelectAll: () => setState(
                () => _selected.addAll(torrents.map((t) => t.id))),
            onClear: () => setState(_selected.clear),
          )
        : PageHeader(
            title: 'Transferts',
            subtitle: state.loaded
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      StatPill(
                          icon: Icons.south_rounded,
                          color: c.accent,
                          label: formatSpeed(state.downloadRate)),
                      StatPill(
                          icon: Icons.north_rounded,
                          color: c.success,
                          label: formatSpeed(state.uploadRate)),
                      StatPill(
                          icon: Icons.layers_outlined,
                          label: '${state.byId.length}'),
                    ]),
                  )
                : null,
            actions: [
              PopupMenuButton<_Sort>(
                tooltip: 'Trier',
                icon: const Icon(Icons.swap_vert_rounded),
                initialValue: _sort,
                onSelected: (s) => setState(() => _sort = s),
                itemBuilder: (_) => [
                  for (final s in _Sort.values)
                    PopupMenuItem(value: s, child: Text(s.label)),
                ],
              ),
              IconButton(
                tooltip: 'Ajouter un lien',
                icon: const Icon(Icons.add_link_rounded),
                onPressed: configured ? _addDialog : null,
              ),
              PopupMenuButton<String>(
                tooltip: 'Plus',
                enabled: configured,
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (v) => switch (v) {
                  'start' => _all('torrent-start', 'Tous les torrents démarrés'),
                  'stop' => _all('torrent-stop', 'Tous les torrents arrêtés'),
                  _ => setState(() =>
                      _selected.addAll(torrents.map((t) => t.id))),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'select', child: Text('Sélectionner')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'start', child: Text('Tout démarrer')),
                  PopupMenuItem(value: 'stop', child: Text('Tout arrêter')),
                ],
              ),
            ],
          );

    return Scaffold(
      body: Column(children: [
        header,
        if (!configured)
          const Expanded(
            child: EmptyState(Icons.dns_outlined,
                'Renseigne l’adresse de ton serveur Transmission\ndans les réglages.'),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                hintText: 'Filtrer par nom',
              ),
            ),
          ),
          ChipRow<_Filter>(
            items: _Filter.values,
            selected: _filter,
            label: (f) => f.label,
            onSelected: (f) => setState(() => _filter = f),
          ),
          if (labels.isNotEmpty) ...[
            const SizedBox(height: 4),
            ChipRow<String?>(
              items: [null, ...labels],
              selected: _label,
              label: (l) => l ?? 'Toutes étiquettes',
              onSelected: (l) => setState(() => _label = l),
            ),
          ],
          const SizedBox(height: 8),
          if (state.error != null)
            ErrorBanner(state.error!,
                onRetry: () => notifier.refresh(full: true)),
          Divider(height: 1, color: c.border),
          Expanded(
            child: !state.loaded
                ? (state.error == null
                    ? const Center(child: CircularProgressIndicator())
                    : const SizedBox())
                : torrents.isEmpty
                    ? const EmptyState(Icons.inbox_outlined, 'Aucun torrent')
                    : ListView.builder(
                        itemExtent: 74,
                        itemCount: torrents.length,
                        itemBuilder: (_, i) {
                          final t = torrents[i];
                          return _TorrentRow(
                            torrent: t,
                            selected: _selected.contains(t.id),
                            selecting: _selected.isNotEmpty,
                            onToggle: () => _toggle(t.id),
                          );
                        },
                      ),
          ),
        ],
      ]),
    );
  }
}

/// En-tête affiché pendant une sélection multiple.
class _SelectionBar extends ConsumerWidget {
  const _SelectionBar({
    required this.torrents,
    required this.onSelectAll,
    required this.onClear,
  });

  final List<Torrent> torrents;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = [for (final t in torrents) t.id];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Row(children: [
        IconButton(
          tooltip: 'Annuler la sélection',
          icon: const Icon(Icons.close_rounded),
          onPressed: onClear,
        ),
        Expanded(
          child: Text('${torrents.length} sélectionné(s)',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          tooltip: 'Tout sélectionner',
          icon: const Icon(Icons.select_all_rounded),
          onPressed: onSelectAll,
        ),
        IconButton(
          tooltip: 'Démarrer',
          icon: const Icon(Icons.play_arrow_rounded),
          onPressed: () => runTorrentAction(
              context, ref, (c) => c.action('torrent-start', ids)),
        ),
        IconButton(
          tooltip: 'Arrêter',
          icon: const Icon(Icons.pause_rounded),
          onPressed: () => runTorrentAction(
              context, ref, (c) => c.action('torrent-stop', ids)),
        ),
        TorrentMenu(
          torrents: torrents,
          exclude: const {TorrentAction.start, TorrentAction.stop},
          onRemoved: onClear,
        ),
      ]),
    );
  }
}

class _TorrentRow extends ConsumerWidget {
  const _TorrentRow({
    required this.torrent,
    required this.selected,
    required this.selecting,
    required this.onToggle,
  });

  final Torrent torrent;
  final bool selected;
  final bool selecting;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = torrent;
    final c = context.colors;
    final color = torrentColor(t, c);
    final progress = t.isChecking
        ? t.recheckProgress
        : t.needsMetadata
            ? t.metadataPercentComplete
            : t.percentDone;

    final meta = <String>[
      if (t.needsMetadata)
        'Métadonnées ${formatPercent(t.metadataPercentComplete)}'
      else
        t.statusLabel,
      if (t.isQueued) 'n° ${t.queuePosition + 1}',
      if (t.isStalled) 'bloqué',
      if (t.percentDone < 1)
        '${formatBytes(t.sizeWhenDone - t.leftUntilDone)} / ${formatBytes(t.sizeWhenDone)}'
      else
        formatBytes(t.sizeWhenDone),
      if (t.isDownloading && t.eta >= 0) formatDuration(t.eta),
      'ratio ${formatRatio(t.ratio)}',
    ];
    const mono = [FontFeature.tabularFigures()];

    return InkWell(
      onLongPress: onToggle,
      onTap: selecting
          ? onToggle
          : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TorrentDetailPage(id: t.id, name: t.name))),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        decoration: BoxDecoration(
          color: selected ? c.accent.withValues(alpha: 0.12) : null,
          border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
        ),
        child: Row(children: [
          if (selecting)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? c.accent : c.muted,
              ),
            ),
          Container(
            width: 3,
            height: double.infinity,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  if (t.bandwidthPriority == TransmissionClient.priorityHigh)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.keyboard_double_arrow_up_rounded,
                          size: 14, color: c.warning),
                    ),
                  Expanded(
                    child: Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  for (final l in t.labels.take(2))
                    Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Tag(l, color: c.info)),
                  const SizedBox(width: 8),
                  Text(formatPercent(progress),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontFeatures: mono)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                      value: progress, color: color, minHeight: 3),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Text(
                      t.hasError ? t.errorString : meta.join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: t.hasError ? c.danger : c.muted),
                    ),
                  ),
                  if (t.rateDownload > 0)
                    Text('  ↓ ${formatSpeed(t.rateDownload)}',
                        style: TextStyle(
                            fontSize: 11.5, color: c.accent, fontFeatures: mono)),
                  if (t.rateUpload > 0)
                    Text('  ↑ ${formatSpeed(t.rateUpload)}',
                        style: TextStyle(
                            fontSize: 11.5, color: c.success, fontFeatures: mono)),
                ]),
              ],
            ),
          ),
          if (!selecting)
            IconButton(
              tooltip: t.isStopped ? 'Démarrer' : 'Arrêter',
              icon: Icon(
                  t.isStopped ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 22),
              onPressed: () => runTorrentAction(
                  context,
                  ref,
                  (c) => c.action(
                      t.isStopped ? 'torrent-start' : 'torrent-stop', [t.id])),
            ),
        ]),
      ),
    );
  }
}
