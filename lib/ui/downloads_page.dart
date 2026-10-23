import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/content_kind.dart';
import '../api/transmission.dart';
import '../core/preferences.dart';
import '../core/format.dart';
import '../state/torrents.dart';
import 'cross_seed_page.dart';
import 'organize_page.dart';
import 'reseed_page.dart';
import 'revive_page.dart';
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

/// Icône de l'état d'un torrent (pastille de la ligne).
IconData torrentIcon(Torrent t) {
  if (t.hasError) return Icons.error_rounded;
  if (t.needsMetadata) return Icons.hourglass_top_rounded;
  if (t.isChecking) return Icons.sync_rounded;
  if (t.isQueued) return Icons.schedule_rounded;
  if (t.isDownloading) return Icons.south_rounded;
  if (t.isSeeding) return Icons.north_rounded;
  if (t.isComplete) return Icons.check_rounded;
  return Icons.pause_rounded;
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

  IconData get icon => switch (this) {
    all => Icons.apps_rounded,
    active => Icons.bolt_rounded,
    downloading => Icons.south_rounded,
    seeding => Icons.north_rounded,
    complete => Icons.check_circle_outline_rounded,
    queued => Icons.schedule_rounded,
    stopped => Icons.pause_circle_outline_rounded,
    stalled => Icons.hourglass_empty_rounded,
    error => Icons.error_outline_rounded,
  };

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

  IconData get icon => switch (this) {
    added => Icons.event_rounded,
    name => Icons.sort_by_alpha_rounded,
    status => Icons.flag_rounded,
    queue => Icons.format_list_numbered_rounded,
    progress => Icons.donut_large_rounded,
    eta => Icons.timer_outlined,
    download => Icons.south_rounded,
    upload => Icons.north_rounded,
    peers => Icons.people_alt_rounded,
    ratio => Icons.balance_rounded,
    uploaded => Icons.cloud_upload_outlined,
    size => Icons.storage_rounded,
  };

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
    // Sans tracker, la catégorie est devinée d'après le nom (`dn` d'un
    // lien magnet ; rien pour une simple URL de .torrent).
    final name = Uri.tryParse(link.trim())?.queryParameters['dn'] ?? '';
    final kind = ContentKind.ofName(name);
    var added = false;
    final ok = await runTorrentAction(context, ref, (c) async {
      added = await c.addTorrent(
          filename: link.trim(), options: await c.categorized(options, kind));
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
    final view = _View(_filter, _label, _query.toLowerCase(), sort, ascending,
        prefs.transferLimit);

    final byId = ref.read(torrentsProvider).byId;
    _selected.removeWhere((id) => !byId.containsKey(id));
    final selection = [for (final id in _selected) ?byId[id]];
    void selectAll() => setState(
      () => _selected.addAll(
        view.shown(view.apply(ref.read(torrentsProvider))).map((t) => t.id),
      ),
    );

    final table = MediaQuery.sizeOf(context).width >= _tableWidth;
    final search = TextField(
      onChanged: (v) => setState(() => _query = v),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search_rounded, size: 20),
        hintText: 'Filtrer par nom',
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
            subtitle: const _Summary(),
            actions: [
              SortMenu<_Sort>(
                options: _Sort.values,
                selected: sort,
                ascending: ascending,
                label: (s) => s.label,
                icon: (s) => s.icon,
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
                  'revive' => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RevivePage()),
                  ),
                  'reseed' => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReseedPage()),
                  ),
                  'organize' => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OrganizePage()),
                  ),
                  'start' => _all(
                    'torrent-start',
                    'Tous les torrents démarrés',
                  ),
                  'stop' => _all('torrent-stop', 'Tous les torrents arrêtés'),
                  _ => selectAll(),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'select', child: Text('Sélectionner')),
                  const PopupMenuItem(value: 'cross', child: Text('Cross-seed…')),
                  const PopupMenuItem(
                      value: 'revive', child: Text('Sans seeder…')),
                  // Un dossier de l'appareil : version de bureau.
                  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
                    const PopupMenuItem(value: 'reseed', child: Text('Reseed…')),
                  const PopupMenuItem(
                      value: 'organize', child: Text('Ranger par catégorie…')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'start', child: Text('Tout démarrer')),
                  const PopupMenuItem(value: 'stop', child: Text('Tout arrêter')),
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
          else if (table) ...[
            // PC : recherche, étiquette et états sur une seule ligne.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
              child: Row(children: [
                SizedBox(width: 300, child: search),
                if (labels.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _LabelMenu(
                    labels: labels,
                    selected: _label,
                    onSelected: (l) => setState(() => _label = l),
                  ),
                ],
                const SizedBox(width: 4),
                Expanded(
                  child: _FilterChips(
                    selected: _filter,
                    onSelected: (f) => setState(() => _filter = f),
                  ),
                ),
                const _ListOptions(),
              ]),
            ),
            if (error != null)
              ErrorBanner(error, onRetry: () => notifier.refresh(full: true)),
            Expanded(
              child: _TorrentList(
                view: view,
                selected: _selected,
                onToggle: _toggle,
                table: true,
                onSort: (s) => ref.read(uiPrefsProvider.notifier).setTransferSort(
                    s.name, s == sort ? !ascending : s.ascendingByDefault),
                onSelectAll: (all) => all ? selectAll() : setState(_selected.clear),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: search,
            ),
            _FilterChips(
              selected: _filter,
              onSelected: (f) => setState(() => _filter = f),
            ),
            if (labels.isNotEmpty) ...[
              const SizedBox(height: 4),
              ChipRow<String?>(
                items: [null, ...labels],
                selected: _label,
                label: (l) => l ?? 'Toutes étiquettes',
                icon: (l) => l == null ? Icons.label_outline_rounded : Icons.label_rounded,
                onSelected: (l) => setState(() => _label = l),
              ),
            ],
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 2, 8, 0),
              child: Align(alignment: Alignment.centerLeft, child: _ListOptions()),
            ),
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
  const _View(this.filter, this.label, this.query, this.sort, this.ascending,
      this.limit);
  final _Filter filter;
  final String? label;
  final String query;
  final _Sort sort;
  final bool ascending;

  /// Torrents affichés au plus ; 0 : tous.
  final int limit;

  /// Les premiers de [all] (déjà filtrés et triés), dans la limite.
  List<Torrent> shown(List<Torrent> all) =>
      limit > 0 && all.length > limit ? all.sublist(0, limit) : all;

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

/// En-tête : réception, envoi et nombre de torrents, en tuiles lisibles
/// (seul bloc de l'en-tête qui suit les rafraîchissements).
class _Summary extends ConsumerWidget {
  const _Summary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (loaded, down, up, count, active) = ref.watch(
      torrentsProvider.select(
        (s) => (
          s.loaded,
          s.downloadRate,
          s.uploadRate,
          s.byId.length,
          s.byId.values.where((t) => t.isActive).length,
        ),
      ),
    );
    if (!loaded) return const SizedBox.shrink();
    final c = context.colors;
    final tiles = [
      _StatTile(
          icon: Icons.south_rounded,
          color: c.download,
          value: formatSpeed(down),
          label: 'Réception'),
      _StatTile(
          icon: Icons.north_rounded,
          color: c.upload,
          value: formatSpeed(up),
          label: 'Envoi'),
      _StatTile(
          icon: Icons.layers_rounded,
          color: c.accent,
          value: '$count',
          label: active == 0 ? 'Torrents' : '$active actif${active > 1 ? 's' : ''}'),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 8),
      child: Row(children: [
        for (final (i, t) in tiles.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          wide ? SizedBox(width: 190, child: t) : Expanded(child: t),
        ],
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.icon,
      required this.color,
      required this.value,
      required this.label});
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Téléphone : petite icône près du libellé, toute la largeur pour la
    // valeur ; PC : pastille ronde à gauche.
    final compact = MediaQuery.sizeOf(context).width < 720;
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()])),
      Row(children: [
        if (compact) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
        ],
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: c.muted)),
        ),
      ]),
    ]);
    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 10, 8, compact ? 6 : 10, 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: compact
          ? text
          : Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(child: text),
            ]),
    );
  }
}

/// Filtres d'état avec icône et nombre ; les filtres vides sont masqués (sauf
/// « Tous » et celui choisi).
class _FilterChips extends ConsumerWidget {
  const _FilterChips({required this.selected, required this.onSelected});
  final _Filter selected;
  final ValueChanged<_Filter> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Clé texte : ne reconstruit que si un compte change.
    final key = ref.watch(torrentsProvider.select((s) => [
          for (final f in _Filter.values)
            s.byId.values.where(f.accepts).length,
        ].join(',')));
    final counts = [for (final n in key.split(',')) int.parse(n)];
    final shown = [
      for (final (i, f) in _Filter.values.indexed)
        if (f == _Filter.all || f == selected || counts[i] > 0) f,
    ];
    return ChipRow<_Filter>(
      items: shown,
      selected: selected,
      label: (f) => '${f.label} (${counts[f.index]})',
      icon: (f) => f.icon,
      onSelected: onSelected,
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
    this.table = false,
    this.onSort,
    this.onSelectAll,
  });

  final _View view;
  final Set<int> selected;
  final void Function(int id) onToggle;

  /// PC : tableau dense, colonnes triables ([onSort]), case « tout »
  /// ([onSelectAll]).
  final bool table;
  final ValueChanged<_Sort>? onSort;
  final ValueChanged<bool>? onSelectAll;

  @override
  ConsumerState<_TorrentList> createState() => _TorrentListState();
}

class _TorrentListState extends ConsumerState<_TorrentList> {
  final _rows = <int, (Torrent, bool, bool, Widget)>{};
  final _tableRows = <int, (Torrent, bool, bool, int, Widget)>{};

  Widget _tableRow(Torrent t, List<_Column> columns) {
    final selected = widget.selected.contains(t.id);
    final selecting = widget.selected.isNotEmpty;
    final cached = _tableRows[t.id];
    if (cached != null &&
        identical(cached.$1, t) &&
        cached.$2 == selected &&
        cached.$3 == selecting &&
        cached.$4 == columns.length) {
      return cached.$5;
    }
    final row = _TableRow(
      key: ValueKey(t.id),
      torrent: t,
      columns: columns,
      selected: selected,
      selecting: selecting,
      onToggle: () => widget.onToggle(t.id),
    );
    _tableRows[t.id] = (t, selected, selecting, columns.length, row);
    return row;
  }

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
    final all = widget.view.apply(state);
    final torrents = widget.view.shown(all);
    final hidden = all.length - torrents.length;
    if (_rows.length > state.byId.length + 50) {
      _rows.removeWhere((id, _) => !state.byId.containsKey(id));
    }
    if (_tableRows.length > state.byId.length + 50) {
      _tableRows.removeWhere((id, _) => !state.byId.containsKey(id));
    }
    if (torrents.isEmpty) {
      return const EmptyState(Icons.inbox_outlined, 'Aucun torrent');
    }
    if (widget.table) {
      return LayoutBuilder(builder: (context, box) {
        final columns = _Column.shown(box.maxWidth);
        final shown = torrents.where((t) => widget.selected.contains(t.id)).length;
        return Column(children: [
          _TableHeader(
            columns: columns,
            sort: widget.view.sort,
            ascending: widget.view.ascending,
            onSort: widget.onSort ?? (_) {},
            allSelected: shown == torrents.length,
            someSelected: shown > 0,
            onSelectAll: widget.onSelectAll ?? (_) {},
          ),
          Expanded(
            child: ListView.builder(
              itemExtent: _TableRow.extent(context),
              itemCount: torrents.length,
              itemBuilder: (_, i) => _tableRow(torrents[i], columns),
            ),
          ),
          if (hidden > 0) _HiddenNotice(shown: torrents.length, total: all.length),
        ]);
      });
    }
    return Column(children: [
      Expanded(
        child: ListView.builder(
          itemExtent: _TorrentRow.extent(context),
          itemCount: torrents.length,
          itemBuilder: (_, i) => _row(torrents[i]),
        ),
      ),
      if (hidden > 0) _HiddenNotice(shown: torrents.length, total: all.length),
    ]);
  }
}

/// Actualisation automatique et nombre de torrents affichés.
class _ListOptions extends ConsumerWidget {
  const _ListOptions();

  static const limits = [50, 100, 200, 500, 1000, 0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(uiPrefsProvider);
    final notifier = ref.read(uiPrefsProvider.notifier);
    final c = context.colors;
    final small = TextStyle(fontSize: 12.5, color: c.muted);
    // Wrap : sur téléphone, la limite passe à la ligne si besoin.
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      Tooltip(
        message: 'Relire Transmission toutes les 2 secondes',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => notifier.setAutoRefresh(!prefs.autoRefresh),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(
              value: prefs.autoRefresh,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => notifier.setAutoRefresh(v ?? true),
            ),
            Text('Actualisation auto', style: small),
            const SizedBox(width: 4),
          ]),
        ),
      ),
      if (!prefs.autoRefresh)
        IconButton(
          tooltip: 'Actualiser',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.refresh_rounded, size: 20),
          onPressed: () => ref.read(torrentsProvider.notifier).refresh(full: true),
        ),
      const SizedBox(width: 12),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Afficher', style: small),
        const SizedBox(width: 6),
        DropdownButton<int>(
          value: limits.contains(prefs.transferLimit) ? prefs.transferLimit : 0,
          isDense: true,
          underline: const SizedBox(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 12.5, color: c.text, fontWeight: FontWeight.w600),
          items: [
            for (final n in limits)
              DropdownMenuItem(value: n, child: Text(n == 0 ? 'Tout' : '$n')),
          ],
          onChanged: (n) => notifier.setTransferLimit(n ?? 0),
        ),
      ]),
    ]);
  }
}

/// Pied de liste quand la limite masque des torrents.
class _HiddenNotice extends ConsumerWidget {
  const _HiddenNotice({required this.shown, required this.total});
  final int shown;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(children: [
          Expanded(
            child: Text('$shown affichés sur $total',
                style: TextStyle(fontSize: 12.5, color: c.muted)),
          ),
          TextButton(
            onPressed: () => ref.read(uiPrefsProvider.notifier).setTransferLimit(0),
            child: const Text('Tout afficher'),
          ),
        ]),
      ),
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

  static const _line = 1.3;

  /// Hauteur d'une carte, d'après la taille du texte du système : marges 10,
  /// rembourrage 24, nom 13,5, barre et pourcentage 12, infos 12,
  /// espacements 12.
  static double extent(BuildContext context) {
    final s = MediaQuery.textScalerOf(context);
    return math.max(
        90,
        10 + 24 + s.scale(13.5) * _line + 6 +
            math.max(8, s.scale(12) * _line) + 6 +
            // Ligne d'infos : texte, ou étiquettes (sur téléphone).
            math.max(s.scale(12) * _line, s.scale(10.5) * 1.3 + 4) + 2);
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
    const mono = [FontFeature.tabularFigures()];
    final small = TextStyle(fontSize: 12, height: _line, color: c.muted);

    Widget info(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: c.muted),
            const SizedBox(width: 4),
            Text(text, style: small.copyWith(fontFeatures: mono)),
          ]),
        );
    Widget speed(IconData icon, Color tone, int rate) => Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: tone),
            const SizedBox(width: 2),
            Text(formatSpeed(rate),
                style: TextStyle(
                    fontSize: 12,
                    height: _line,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                    fontFeatures: mono)),
          ]),
        );

    final status = t.needsMetadata
        ? 'Métadonnées'
        : [
            t.statusLabel,
            if (t.isQueued) 'n° ${t.queuePosition + 1}',
            if (t.isStalled) 'bloqué',
          ].join(' · ');
    // Écran étroit : les vitesses en tête de la ligne d'infos (les derniers
    // éléments masqués si besoin) plutôt qu'à part, où elles ne tiendraient pas.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final speeds = [
      if (t.rateDownload > 0)
        speed(Icons.south_rounded, c.download, t.rateDownload),
      if (t.rateUpload > 0) speed(Icons.north_rounded, c.upload, t.rateUpload),
    ];
    final details = OneLineRow(children: [
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Text(status,
            style: small.copyWith(color: color, fontWeight: FontWeight.w700)),
      ),
      if (narrow) ...[
        for (final w in speeds)
          Padding(padding: const EdgeInsets.only(right: 12), child: w),
        for (final l in t.labels.take(2))
          Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tag(l, color: c.info)),
      ],
      info(
          Icons.storage_rounded,
          t.percentDone < 1
              ? '${formatBytes(t.sizeWhenDone - t.leftUntilDone)} / ${formatBytes(t.sizeWhenDone)}'
              : formatBytes(t.sizeWhenDone)),
      if (t.isDownloading && t.eta >= 0)
        info(Icons.timer_outlined, formatDuration(t.eta)),
      info(Icons.balance_rounded, formatRatio(t.ratio)),
      if (t.peersConnected > 0)
        info(Icons.people_alt_rounded, '${t.peersConnected}'),
    ]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Material(
        color: selected ? c.accent.withValues(alpha: 0.10) : c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? c.accent : c.border),
        ),
        child: InkWell(
          onLongPress: onToggle,
          onTap: selecting
              ? onToggle
              : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TorrentDetailPage(id: t.id, name: t.name),
                  ),
                ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: selected ? c.accent : c.muted,
                  ),
                ),
              // Pastille d'état.
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(torrentIcon(t), size: 20, color: color),
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
                              size: 16, color: c.warning),
                        ),
                      Expanded(
                        child: Text(t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5,
                                height: _line,
                                fontWeight: FontWeight.w700)),
                      ),
                      // Étiquettes : peuvent rétrécir et se couper (sur
                      // téléphone, dans la ligne d'infos).
                      if (t.labels.isNotEmpty && !narrow)
                        Flexible(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            child: Row(children: [
                              for (final l in t.labels.take(2))
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Tag(l, color: c.info),
                                ),
                            ]),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: progress,
                          color: color,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      // Largeur fixe (barres alignées d'une ligne à l'autre),
                      // proportionnelle au texte ; jamais sur deux lignes.
                      SizedBox(
                        width: MediaQuery.textScalerOf(context).scale(56),
                        child: Text(formatPercent(progress),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                                fontSize: 12,
                                height: _line,
                                fontWeight: FontWeight.w800,
                                color: color,
                                fontFeatures: mono)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: t.hasError
                            ? Text(t.errorString,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: small.copyWith(color: c.danger))
                            // Une ligne : ce qui ne tient pas est masqué.
                            : details,
                      ),
                      if (!narrow) ...speeds,
                    ]),
                  ],
                ),
              ),
              if (!selecting) ...[
                const SizedBox(width: 6),
                Material(
                  color: c.surfaceAlt,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => runTorrentAction(
                      context,
                      ref,
                      (c) => c.action(
                        t.isStopped ? 'torrent-start' : 'torrent-stop',
                        [t.id],
                      ),
                    ),
                    child: Tooltip(
                      message: t.isStopped ? 'Démarrer' : 'Mettre en pause',
                      child: SizedBox.square(
                        dimension: 40,
                        child: Icon(
                            t.isStopped
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            size: 22,
                            color: c.text),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PC : un tableau dense, colonnes triables, boutons d'action sur chaque ligne.

/// Largeur d'écran à partir de laquelle la liste devient un tableau.
const _tableWidth = 1000.0;

/// Colonnes du tableau (le nom prend le reste). [minWidth] : largeur de
/// liste en dessous de laquelle la colonne disparaît.
enum _Column {
  status('État', 120, _Sort.status),
  progress('Progression', 150, _Sort.progress),
  size('Taille', 86, _Sort.size, numeric: true),
  down('Réception', 84, _Sort.download, numeric: true),
  up('Envoi', 84, _Sort.upload, numeric: true),
  eta('Reste', 70, _Sort.eta, numeric: true, minWidth: 1250),
  ratio('Ratio', 58, _Sort.ratio, numeric: true),
  uploaded('Envoyé', 84, _Sort.uploaded, numeric: true, minWidth: 1450),
  peers('Pairs', 52, _Sort.peers, numeric: true, minWidth: 1150);

  const _Column(this.label, this.width, this.sort, {this.numeric = false, this.minWidth = 0});
  final String label;
  final double width;
  final _Sort sort;
  final bool numeric;
  final double minWidth;

  static List<_Column> shown(double width) => [
        for (final c in values)
          if (width >= c.minWidth) c,
      ];
}

/// Boutons d'action d'une ligne : démarrer ou arrêter, vérifier,
/// étiquettes, supprimer, et le reste dans « ⋮ ».
const _actionsWidth = 5 * 32.0 + 8;

/// En-tête du tableau : case « tout », titres de colonnes (clic : tri).
class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.columns,
    required this.sort,
    required this.ascending,
    required this.onSort,
    required this.allSelected,
    required this.someSelected,
    required this.onSelectAll,
  });

  final List<_Column> columns;
  final _Sort sort;
  final bool ascending;
  final ValueChanged<_Sort> onSort;
  final bool allSelected;
  final bool someSelected;
  final ValueChanged<bool> onSelectAll;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget title(String label, _Sort s, {bool numeric = false}) {
      final on = s == sort;
      return InkWell(
        onTap: () => onSort(s),
        child: Row(
          mainAxisAlignment: numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: on ? c.text : c.muted)),
            ),
            if (on)
              Icon(ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  size: 13, color: c.text),
          ],
        ),
      );
    }

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(children: [
        SizedBox(
          width: 32,
          child: Checkbox(
            tristate: true,
            value: allSelected ? true : (someSelected ? null : false),
            onChanged: (_) => onSelectAll(!allSelected),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 28),
        Expanded(child: title('Nom', _Sort.name)),
        for (final col in columns)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: SizedBox(width: col.width, child: title(col.label, col.sort, numeric: col.numeric)),
          ),
        const SizedBox(width: _actionsWidth),
      ]),
    );
  }
}

/// Une ligne du tableau.
class _TableRow extends ConsumerWidget {
  const _TableRow({
    super.key,
    required this.torrent,
    required this.columns,
    required this.selected,
    required this.selecting,
    required this.onToggle,
  });

  final Torrent torrent;
  final List<_Column> columns;
  final bool selected;
  final bool selecting;
  final VoidCallback onToggle;

  static double extent(BuildContext context) =>
      math.max(42, MediaQuery.textScalerOf(context).scale(13.5) * 1.3 + 22);

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
    const mono = [FontFeature.tabularFigures()];
    final small = TextStyle(fontSize: 12.5, color: c.muted, fontFeatures: mono);
    final strong = small.copyWith(color: c.text, fontWeight: FontWeight.w600);

    Widget cell(_Column col) {
      final Widget child = switch (col) {
        _Column.status => Text(
            t.needsMetadata
                ? 'Métadonnées'
                : [
                    t.statusLabel,
                    if (t.isQueued) 'n° ${t.queuePosition + 1}',
                    if (t.isStalled) 'bloqué',
                  ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: small.copyWith(color: color, fontWeight: FontWeight.w700)),
        _Column.progress => Row(children: [
            Expanded(
              child: LinearProgressIndicator(
                  value: progress, color: color, minHeight: 5, borderRadius: BorderRadius.circular(3)),
            ),
            SizedBox(
              width: 46,
              child: Text(formatPercent(progress),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: small.copyWith(color: color, fontWeight: FontWeight.w700)),
            ),
          ]),
        // Taille totale : la part reçue est dans la progression.
        _Column.size => Text(formatBytes(t.sizeWhenDone), maxLines: 1, style: small),
        _Column.down => t.rateDownload > 0
            ? Text(formatSpeed(t.rateDownload), maxLines: 1, style: strong.copyWith(color: c.download))
            : Text('—', style: small),
        _Column.up => t.rateUpload > 0
            ? Text(formatSpeed(t.rateUpload), maxLines: 1, style: strong.copyWith(color: c.upload))
            : Text('—', style: small),
        _Column.eta => Text(t.isDownloading && t.eta >= 0 ? formatDuration(t.eta) : '—', maxLines: 1, style: small),
        _Column.ratio => Text(formatRatio(t.ratio), maxLines: 1, style: small),
        _Column.uploaded => Text(formatBytes(t.uploadedEver), maxLines: 1, style: small),
        _Column.peers => Text(t.peersConnected > 0 ? '${t.peersConnected}' : '—', maxLines: 1, style: small),
      };
      return Padding(
        padding: const EdgeInsets.only(left: 12),
        child: SizedBox(
          width: col.width,
          child: Align(alignment: col.numeric ? Alignment.centerRight : Alignment.centerLeft, child: child),
        ),
      );
    }

    Widget action(IconData icon, String tip, VoidCallback onTap, {Color? tone}) => SizedBox.square(
          dimension: 32,
          child: IconButton(
            tooltip: tip,
            padding: EdgeInsets.zero,
            iconSize: 18,
            color: tone ?? c.muted,
            onPressed: onTap,
            icon: Icon(icon),
          ),
        );

    return Material(
      color: selected ? c.accent.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onLongPress: onToggle,
        onTap: selecting
            ? onToggle
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => TorrentDetailPage(id: t.id, name: t.name)),
                ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.6)))),
          child: Row(children: [
            SizedBox(
              width: 32,
              child: Checkbox(
                value: selected,
                onChanged: (_) => onToggle(),
                visualDensity: VisualDensity.compact,
              ),
            ),
            SizedBox(width: 28, child: Icon(torrentIcon(t), size: 18, color: color)),
            Expanded(
              child: Row(children: [
                if (t.bandwidthPriority == TransmissionClient.priorityHigh)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.keyboard_double_arrow_up_rounded, size: 15, color: c.warning),
                  ),
                Flexible(
                  child: Tooltip(
                    message: t.hasError ? '${t.name}\n${t.errorString}' : t.name,
                    waitDuration: const Duration(milliseconds: 600),
                    child: Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: t.hasError ? c.danger : null)),
                  ),
                ),
                for (final l in t.labels.take(2))
                  Padding(padding: const EdgeInsets.only(left: 6), child: Tag(l, color: c.info)),
              ]),
            ),
            for (final col in columns) cell(col),
            const SizedBox(width: 8),
            action(
              t.isStopped ? Icons.play_arrow_rounded : Icons.pause_rounded,
              t.isStopped ? 'Démarrer' : 'Mettre en pause',
              () => runTorrentAction(
                  context, ref, (c) => c.action(t.isStopped ? 'torrent-start' : 'torrent-stop', [t.id])),
              tone: c.text,
            ),
            action(Icons.fact_check_outlined, 'Vérifier les données',
                () => handleTorrentAction(context, ref, TorrentAction.verify, [t])),
            action(Icons.label_outline_rounded, 'Étiquettes…',
                () => handleTorrentAction(context, ref, TorrentAction.labels, [t])),
            action(Icons.delete_outline_rounded, 'Supprimer…',
                () => handleTorrentAction(context, ref, TorrentAction.remove, [t]),
                tone: c.danger),
            SizedBox.square(
              dimension: 32,
              child: TorrentMenu(
                torrents: [t],
                compact: true,
                exclude: const {
                  TorrentAction.start,
                  TorrentAction.stop,
                  TorrentAction.verify,
                  TorrentAction.labels,
                  TorrentAction.remove,
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Filtre d'étiquette en menu (PC), à côté de la recherche.
class _LabelMenu extends StatelessWidget {
  const _LabelMenu({required this.labels, required this.selected, required this.onSelected});
  final List<String> labels;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<String?>(
      tooltip: 'Étiquette',
      onSelected: onSelected,
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: null, checked: selected == null, child: const Text('Toutes étiquettes')),
        for (final l in labels) CheckedPopupMenuItem(value: l, checked: selected == l, child: Text(l)),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected == null ? c.surfaceAlt : c.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.label_outline_rounded, size: 18, color: selected == null ? c.muted : c.accent),
          const SizedBox(width: 6),
          Text(selected ?? 'Étiquettes', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Icon(Icons.arrow_drop_down_rounded, color: c.muted),
        ]),
      ),
    );
  }
}
