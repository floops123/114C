import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/transmission.dart';
import '../core/format.dart';
import '../state/torrents.dart';
import 'torrent_detail_page.dart';
import 'widgets.dart';

enum _Filter {
  all('Tous'),
  active('Actifs'),
  downloading('En cours'),
  seeding('Partage'),
  stopped('Arrêtés'),
  error('Erreurs');

  const _Filter(this.label);
  final String label;

  bool accepts(Torrent t) => switch (this) {
        all => true,
        active => t.isActive,
        downloading => t.isDownloading,
        seeding => t.isSeeding,
        stopped => t.isStopped,
        error => t.hasError,
      };
}

enum _Sort {
  added('Date d’ajout'),
  name('Nom'),
  progress('Progression'),
  download('Vitesse ↓'),
  upload('Vitesse ↑'),
  ratio('Ratio'),
  size('Taille');

  const _Sort(this.label);
  final String label;

  int compare(Torrent a, Torrent b) => switch (this) {
        added => b.addedDate.compareTo(a.addedDate),
        name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        progress => a.percentDone.compareTo(b.percentDone),
        download => b.rateDownload.compareTo(a.rateDownload),
        upload => b.rateUpload.compareTo(a.rateUpload),
        ratio => b.ratio.compareTo(a.ratio),
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
  String _query = '';

  Future<void> _addDialog() async {
    final controller = TextEditingController();
    final link = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter un torrent'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Lien magnet ou URL du .torrent'),
          onSubmitted: (v) => Navigator.pop(context, v),
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
    );
    controller.dispose();
    if (link == null || link.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      var added = false;
      await ref.read(torrentsProvider.notifier).run(
          (c) async => added = await c.addTorrent(filename: link.trim()));
      messenger.showSnackBar(SnackBar(
          content: Text(added ? 'Torrent ajouté' : 'Déjà présent')));
    } on TransmissionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(transmissionProvider) != null;
    final state = ref.watch(torrentsProvider);
    final notifier = ref.read(torrentsProvider.notifier);
    final theme = Theme.of(context);

    final query = _query.toLowerCase();
    final torrents = state.byId.values
        .where((t) =>
            _filter.accepts(t) &&
            (query.isEmpty || t.name.toLowerCase().contains(query)))
        .toList()
      ..sort(_sort.compare);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Téléchargements'),
          if (state.loaded)
            Text(
              '↓ ${formatSpeed(state.downloadRate)}   ↑ ${formatSpeed(state.uploadRate)}'
              '   ·   ${state.byId.length} torrents',
              style: theme.textTheme.bodySmall,
            ),
        ]),
        actions: [
          PopupMenuButton<_Sort>(
            tooltip: 'Trier',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => [
              for (final s in _Sort.values)
                PopupMenuItem(value: s, child: Text(s.label)),
            ],
          ),
          IconButton(
            tooltip: 'Ajouter',
            icon: const Icon(Icons.add_link),
            onPressed: configured ? _addDialog : null,
          ),
        ],
      ),
      body: !configured
          ? const EmptyState(Icons.dns_outlined,
              'Renseigne l’adresse de ton serveur Transmission dans les réglages.')
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.filter_list),
                    hintText: 'Filtrer par nom',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final f in _Filter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(f.label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              if (state.error != null)
                ErrorBanner(state.error!,
                    onRetry: () => notifier.refresh(full: true)),
              Expanded(
                child: !state.loaded
                    ? (state.error == null
                        ? const Center(child: CircularProgressIndicator())
                        : const SizedBox())
                    : torrents.isEmpty
                        ? const EmptyState(Icons.inbox_outlined, 'Aucun torrent')
                        : ListView.builder(
                            itemExtent: 80,
                            itemCount: torrents.length,
                            itemBuilder: (_, i) =>
                                _TorrentTile(torrent: torrents[i]),
                          ),
              ),
            ]),
    );
  }
}

class _TorrentTile extends ConsumerWidget {
  const _TorrentTile({required this.torrent});
  final Torrent torrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = torrent;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (IconData icon, Color color) = t.hasError
        ? (Icons.error, scheme.error)
        : t.isDownloading
            ? (Icons.arrow_downward, scheme.primary)
            : t.isSeeding
                ? (Icons.arrow_upward, Colors.green)
                : t.isChecking
                    ? (Icons.sync, scheme.tertiary)
                    : (Icons.pause, scheme.outline);

    final parts = <String>[
      t.statusLabel,
      formatPercent(t.isChecking ? t.recheckProgress : t.percentDone),
      if (t.percentDone < 1)
        '${formatBytes(t.sizeWhenDone - t.leftUntilDone)} / ${formatBytes(t.sizeWhenDone)}'
      else
        formatBytes(t.sizeWhenDone),
      if (t.rateDownload > 0) '↓ ${formatSpeed(t.rateDownload)}',
      if (t.rateUpload > 0) '↑ ${formatSpeed(t.rateUpload)}',
      if (t.isDownloading && t.eta >= 0) formatDuration(t.eta),
      'ratio ${formatRatio(t.ratio)}',
    ];

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TorrentDetailPage(id: t.id, name: t.name))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: t.isChecking ? t.recheckProgress : t.percentDone,
                  color: color,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 6),
                Text(
                  t.hasError ? t.errorString : parts.join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: t.hasError ? scheme.error : scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: t.isStopped ? 'Démarrer' : 'Arrêter',
            icon: Icon(t.isStopped ? Icons.play_arrow : Icons.pause),
            onPressed: () => ref.read(torrentsProvider.notifier).run((c) =>
                c.action(t.isStopped ? 'torrent-start' : 'torrent-stop', [t.id])),
          ),
        ]),
      ),
    );
  }
}
