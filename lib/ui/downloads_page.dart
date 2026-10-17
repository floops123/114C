import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/transmission.dart';
import '../core/preferences.dart';
import '../core/format.dart';
import '../state/torrents.dart';
import 'cross_seed_page.dart';
import 'stats_page.dart';
import 'theme.dart';
import 'torrent_actions.dart';
import 'torrent_detail_page.dart';
import 'widgets.dart';

/// Couleur associée à l'état d'un torrent, partagée par la liste et le détail.
Color torrentColor(Torrent t, AppColors c) {
  if (t.hasError) return c.danger;
  // Bleu de la réception (distinct du vert du partage et de l'accent).
  if (t.isDownloading) return c.download;
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

/// Critères de tri des transferts ; [compare] trie par ordre croissant.
enum _Sort {
  added('Date d’ajout'),
  name('Nom', ascendingByDefault: true),
  status('État', ascendingByDefault: true),
  queue('File d’attente', ascendingByDefault: true),
  progress('Progression'),
  eta('Temps restant', ascendingByDefault: true),
  download('Vitesse de réception'),
  upload('Vitesse d’envoi'),
  peers('Pairs connectés'),
  ratio('Ratio'),
  uploaded('Volume envoyé'),
  size('Taille');

  const _Sort(this.label, {this.ascendingByDefault = false});
  final String label;
  final bool ascendingByDefault;

  // eta vaut -1 ou -2 quand il est inconnu : on le place après les autres.
  static int _eta(Torrent t) => t.eta < 0 ? 1 << 40 : t.eta;

  int compare(Torrent a, Torrent b) => switch (this) {
    added => a.addedDate.compareTo(b.addedDate),
    name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    status => a.status.compareTo(b.status),
    queue => a.queuePosition.compareTo(b.queuePosition),
    progress => a.percentDone.compareTo(b.percentDone),
    eta => _eta(a).compareTo(_eta(b)),
    download => a.rateDownload.compareTo(b.rateDownload),
    upload => a.rateUpload.compareTo(b.rateUpload),
    peers => a.peersConnected.compareTo(b.peersConnected),
    ratio => a.ratio.compareTo(b.ratio),
    uploaded => a.uploadedEver.compareTo(b.uploadedEver),
    size => a.totalSize.compareTo(b.totalSize),
  };
}

class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  _Filter _filter = _Filter.all;
  String? _label;
  String _query = '';
  final _selected = <int>{};

  void _toggle(int id) => setState(
    () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id),
  );

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Lien magnet ou URL du .torrent',
                  ),
                  onSubmitted: (v) => Navigator.pop(context, v),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: withOptions,
                  onChanged: (v) => setState(() => withOptions = v ?? false),
                  title: const Text('Choisir le dossier, les étiquettes…'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Ajouter'),
            ),
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
        SnackBar(content: Text(added ? 'Torrent ajouté' : 'Déjà présent')),
      );
    }
  }

  Future<void> _all(String method, String message) => runTorrentAction(
    context,
    ref,
    (c) => c.action(method, null),
    success: message,
  );

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(transmissionProvider) != null;
    final notifier = ref.read(torrentsProvider.notifier);
    final c = context.colors;

    // L'écran ne se reconstruit que pour ce qui le concerne : la liste et les
    // vitesses ont leurs propres abonnements aux rafraîchissements (2 s).
    final error = ref.watch(torrentsProvider.select((s) => s.error));
    final labelsKey = ref.watch(
      torrentsProvider.select(
        (s) => ({
          for (final t in s.byId.values) ...t.labels,
        }.toList()..sort()).join('\n'),
      ),
    );
    final labels = labelsKey.isEmpty ? const <String>[] : labelsKey.split('\n');
    if (_label != null && !labels.contains(_label)) _label = null;

    final prefs = ref.watch(uiPrefsProvider);
    final sort = _Sort.values.asNameMap()[prefs.transferSort] ?? _Sort.added;
    final ascending = prefs.transferSort == null
        ? false
        : prefs.transferAscending;
    final view = _View(_filter, _label, _query.toLowerCase(), sort, ascending);

    final byId = ref.read(torrentsProvider).byId;
    _selected.removeWhere((id) => !byId.containsKey(id));
    final selection = [for (final id in _selected) ?byId[id]];
    void selectAll() => setState(
      () => _selected.addAll(
        view.apply(ref.read(torrentsProvider)).map((t) => t.id),
      ),
    );

    final header = _selected.isNotEmpty
        ? _SelectionBar(
            torrents: selection,
            onSelectAll: selectAll,
            onClear: () => setState(_selected.clear),
          )
        : PageHeader(
            title: 'Transferts',
            subtitle: const _SpeedPills(),
            actions: [
              SortMenu<_Sort>(
                options: _Sort.values,
                selected: sort,
                ascending: ascending,
                label: (s) => s.label,
                ascendingByDefault: (s) => s.ascendingByDefault,
                onChanged: (s, asc) => ref
                    .read(uiPrefsProvider.notifier)
                    .setTransferSort(s.name, asc),
              ),
              IconButton(
                tooltip: 'Statistiques',
                icon: const Icon(Icons.insights_rounded),
                onPressed: configured
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const StatsPage()),
                      )
                    : null,
              ),
              PopupMenuButton<String>(
                tooltip: 'Ajouter',
                enabled: configured,
                icon: const Icon(Icons.add_rounded),
                onSelected: (v) => v == 'file'
                    ? pickAndAddTorrentFiles(context, ref)
                    : _addDialog(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'file',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.upload_file_rounded),
                      title: Text('Fichier .torrent depuis cet appareil'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'link',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.add_link_rounded),
                      title: Text('Lien magnet ou URL'),
                    ),
                  ),
                ],
              ),
              PopupMenuButton<String>(
                tooltip: 'Plus',
                enabled: configured,
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (v) => switch (v) {
                  'cross' => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CrossSeedPage()),
                  ),
                  'start' => _all(
                    'torrent-start',
                    'Tous les torrents démarrés',
                  ),
                  'stop' => _all('torrent-stop', 'Tous les torrents arrêtés'),
                  _ => selectAll(),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'select', child: Text('Sélectionner')),
                  PopupMenuItem(value: 'cross', child: Text('Cross-seed…')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'start', child: Text('Tout démarrer')),
                  PopupMenuItem(value: 'stop', child: Text('Tout arrêter')),
                ],
              ),
            ],
          );

    return Scaffold(
      body: Column(
        children: [
          header,
          if (!configured)
            const Expanded(
              child: EmptyState(
                Icons.dns_outlined,
                'Renseigne l’adresse de ton serveur Transmission\ndans les réglages.',
              ),
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
            const SizedBox(height: 6),
            if (error != null)
              ErrorBanner(error, onRetry: () => notifier.refresh(full: true)),
            Divider(height: 1, color: c.border),
            Expanded(
              child: _TorrentList(
                view: view,
                selected: _selected,
                onToggle: _toggle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Filtres, recherche et tri appliqués à la liste.
class _View {
  const _View(this.filter, this.label, this.query, this.sort, this.ascending);
  final _Filter filter;
  final String? label;
  final String query;
  final _Sort sort;
  final bool ascending;

  List<Torrent> apply(TorrentsState state) {
    int compare(Torrent a, Torrent b) {
      final r = ascending ? sort.compare(a, b) : sort.compare(b, a);
      // À égalité (ex. vitesse nulle), ordre stable par nom.
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    return state.byId.values
        .where(
          (t) =>
              filter.accepts(t) &&
              (label == null || t.labels.contains(label)) &&
              (query.isEmpty || t.name.toLowerCase().contains(query)),
        )
        .toList()
      ..sort(compare);
  }
}

/// Vitesses globales et nombre de torrents (seul bloc de l'en-tête qui suit
/// les rafraîchissements).
class _SpeedPills extends ConsumerWidget {
  const _SpeedPills();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (loaded, down, up, count) = ref.watch(
      torrentsProvider.select(
        (s) => (s.loaded, s.downloadRate, s.uploadRate, s.byId.length),
      ),
    );
    if (!loaded) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          StatPill(
            icon: Icons.south_rounded,
            color: c.download,
            label: formatSpeed(down),
          ),
          StatPill(
            icon: Icons.north_rounded,
            color: c.upload,
            label: formatSpeed(up),
          ),
          StatPill(icon: Icons.layers_outlined, label: '$count'),
        ],
      ),
    );
  }
}

/// Liste des torrents. Une ligne n'est reconstruite que si son torrent a
/// changé (les objets Torrent inchangés sont conservés d'un rafraîchissement
/// à l'autre) ou si la sélection a changé.
class _TorrentList extends ConsumerStatefulWidget {
  const _TorrentList({
    required this.view,
    required this.selected,
    required this.onToggle,
  });

  final _View view;
  final Set<int> selected;
  final void Function(int id) onToggle;

  @override
  ConsumerState<_TorrentList> createState() => _TorrentListState();
}

class _TorrentListState extends ConsumerState<_TorrentList> {
  final _rows = <int, (Torrent, bool, bool, Widget)>{};

  Widget _row(Torrent t) {
    final selected = widget.selected.contains(t.id);
    final selecting = widget.selected.isNotEmpty;
    final cached = _rows[t.id];
    if (cached != null &&
        identical(cached.$1, t) &&
        cached.$2 == selected &&
        cached.$3 == selecting) {
      return cached.$4;
    }
    final row = _TorrentRow(
      key: ValueKey(t.id),
      torrent: t,
      selected: selected,
      selecting: selecting,
      onToggle: () => widget.onToggle(t.id),
    );
    _rows[t.id] = (t, selected, selecting, row);
    return row;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(torrentsProvider);
    if (!state.loaded) {
      return state.error == null
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox();
    }
    final torrents = widget.view.apply(state);
    if (_rows.length > state.byId.length + 50) {
      _rows.removeWhere((id, _) => !state.byId.containsKey(id));
    }
    if (torrents.isEmpty) {
      return const EmptyState(Icons.inbox_outlined, 'Aucun torrent');
    }
    return ListView.builder(
      itemExtent: _TorrentRow.extent(context),
      itemCount: torrents.length,
      itemBuilder: (_, i) => _row(torrents[i]),
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
      child: Row(
        children: [
          IconButton(
            tooltip: 'Annuler la sélection',
            icon: const Icon(Icons.close_rounded),
            onPressed: onClear,
          ),
          Expanded(
            child: Text(
              '${torrents.length} sélectionné(s)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
              context,
              ref,
              (c) => c.action('torrent-start', ids),
            ),
          ),
          IconButton(
            tooltip: 'Arrêter',
            icon: const Icon(Icons.pause_rounded),
            onPressed: () => runTorrentAction(
              context,
              ref,
              (c) => c.action('torrent-stop', ids),
            ),
          ),
          TorrentMenu(
            torrents: torrents,
            exclude: const {TorrentAction.start, TorrentAction.stop},
            onRemoved: onClear,
          ),
        ],
      ),
    );
  }
}

class _TorrentRow extends ConsumerWidget {
  const _TorrentRow({
    super.key,
    required this.torrent,
    required this.selected,
    required this.selecting,
    required this.onToggle,
  });

  final Torrent torrent;
  final bool selected;
  final bool selecting;
  final VoidCallback onToggle;

  /// Hauteur de ligne : 64 px, plus si la police du système est agrandie
  /// (titre 13 / étiquette 10,5 + 4, infos 11,5, interligne 1,25 ; barre 3,
  /// espacements 10, marges 14).
  static double extent(BuildContext context) {
    final s = MediaQuery.textScalerOf(context).scale(100) / 100;
    return math.max(64, 29 + (10.5 * 1.3 + 11.5 * 1.25) * s + 4);
  }

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
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TorrentDetailPage(id: t.id, name: t.name),
              ),
            ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 7, 4, 7),
        decoration: BoxDecoration(
          color: selected ? c.accent.withValues(alpha: 0.12) : null,
          border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
        ),
        child: Row(
          children: [
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
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      if (t.bandwidthPriority ==
                          TransmissionClient.priorityHigh)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.keyboard_double_arrow_up_rounded,
                            size: 14,
                            color: c.warning,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Étiquettes : peuvent rétrécir et se couper, pour ne
                      // jamais pousser le pourcentage hors de la ligne.
                      if (t.labels.isNotEmpty)
                        Flexible(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            child: Row(
                              children: [
                                for (final l in t.labels.take(2))
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Tag(l, color: c.info),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        formatPercent(progress),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontFeatures: mono,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // Coins arrondis dessinés par la barre (pas de découpe).
                  LinearProgressIndicator(
                    value: progress,
                    color: color,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.hasError ? t.errorString : meta.join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.25,
                            color: t.hasError ? c.danger : c.muted,
                          ),
                        ),
                      ),
                      // Le texte reste en couleur de texte : seule la flèche
                      // porte la couleur de la série.
                      if (t.rateDownload > 0) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.south_rounded, size: 12, color: c.download),
                        Text(
                          formatSpeed(t.rateDownload),
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.25,
                            color: c.text,
                            fontFeatures: mono,
                          ),
                        ),
                      ],
                      if (t.rateUpload > 0) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.north_rounded, size: 12, color: c.upload),
                        Text(
                          formatSpeed(t.rateUpload),
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.25,
                            color: c.text,
                            fontFeatures: mono,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (!selecting)
              IconButton(
                icon: Icon(
                  t.isStopped ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 22,
                ),
                onPressed: () => runTorrentAction(
                  context,
                  ref,
                  (c) => c.action(
                    t.isStopped ? 'torrent-start' : 'torrent-stop',
                    [t.id],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
