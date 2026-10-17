import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/transmission.dart';
import '../core/format.dart';
import '../state/torrents.dart';
import 'widgets.dart';

class TorrentDetailPage extends ConsumerWidget {
  const TorrentDetailPage({super.key, required this.id, required this.name});
  final int id;
  final String name;

  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function(TransmissionClient c) action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(torrentsProvider.notifier).run(action);
      ref.invalidate(torrentDetailProvider(id));
    } on TransmissionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    var deleteData = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Supprimer le torrent ?'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: deleteData,
            onChanged: (v) => setState(() => deleteData = v ?? false),
            title: const Text('Supprimer aussi les fichiers téléchargés'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Supprimer')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    await _act(context, ref, (c) => c.remove([id], deleteData: deleteData));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(torrentDetailProvider(id));
    final json = detail.value;
    final t = json == null ? null : Torrent(json);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t?.name ?? name, overflow: TextOverflow.ellipsis),
          actions: [
            if (t != null)
              IconButton(
                tooltip: t.isStopped ? 'Démarrer' : 'Arrêter',
                icon: Icon(t.isStopped ? Icons.play_arrow : Icons.pause),
                onPressed: () => _act(context, ref, (c) => c.action(
                    t.isStopped ? 'torrent-start' : 'torrent-stop', [id])),
              ),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'remove'
                  ? _confirmRemove(context, ref)
                  : _act(context, ref, (c) => c.action(v, [id])),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'torrent-verify', child: Text('Vérifier')),
                PopupMenuItem(
                    value: 'torrent-reannounce', child: Text('Réannoncer')),
                PopupMenuItem(value: 'remove', child: Text('Supprimer…')),
              ],
            ),
          ],
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Infos'),
            Tab(text: 'Fichiers'),
            Tab(text: 'Pairs'),
            Tab(text: 'Trackers'),
          ]),
        ),
        body: switch (detail) {
          AsyncError(:final error) when json == null =>
            EmptyState(Icons.error_outline, '$error'),
          _ when json == null && detail.isLoading =>
            const Center(child: CircularProgressIndicator()),
          _ when json == null =>
            const EmptyState(Icons.delete_outline, 'Ce torrent n’existe plus'),
          _ => TabBarView(children: [
              _InfoTab(json),
              _FilesTab(id, json),
              _PeersTab(json),
              _TrackersTab(json),
            ]),
        },
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  const _InfoTab(this.json);
  final Map<String, dynamic> json;

  @override
  Widget build(BuildContext context) {
    final t = Torrent(json);
    int i(String k) => (json[k] as num?)?.toInt() ?? 0;
    String date(String k) => i(k) > 0 ? formatDate(fromEpoch(i(k))) : '—';

    final rows = <(String, String)>[
      ('État', t.hasError ? '${t.statusLabel} — ${t.errorString}' : t.statusLabel),
      ('Progression', formatPercent(t.percentDone)),
      ('Taille', formatBytes(t.totalSize)),
      ('Vitesse', '↓ ${formatSpeed(t.rateDownload)}  ↑ ${formatSpeed(t.rateUpload)}'),
      if (t.isDownloading) ('Temps restant', formatDuration(t.eta)),
      ('Téléchargé', formatBytes(i('downloadedEver'))),
      ('Envoyé', formatBytes(i('uploadedEver'))),
      ('Ratio', formatRatio(t.ratio)),
      ('Corrompu', formatBytes(i('corruptEver'))),
      ('Pairs', '${t.peersConnected} connectés · ${t.peersSendingToUs} envoient · ${t.peersGettingFromUs} reçoivent'),
      ('Pièces', '${i('pieceCount')} × ${formatBytes(i('pieceSize'))}'),
      ('Dossier', json['downloadDir'] as String? ?? ''),
      ('Ajouté', date('addedDate')),
      ('Terminé', date('doneDate')),
      ('Dernière activité', date('activityDate')),
      ('Temps en téléchargement', formatDuration(i('secondsDownloading'))),
      ('Temps en partage', formatDuration(i('secondsSeeding'))),
      ('Privé', json['isPrivate'] == true ? 'Oui' : 'Non'),
      ('Hash', t.hash),
      if ((json['comment'] as String? ?? '').isNotEmpty)
        ('Commentaire', json['comment'] as String),
    ];

    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      LinearProgressIndicator(value: t.percentDone, minHeight: 6),
      const SizedBox(height: 12),
      for (final (label, value) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 180,
                child: Text(label, style: theme.textTheme.bodySmall)),
            Expanded(child: SelectableText(value)),
          ]),
        ),
    ]);
  }
}

class _FilesTab extends ConsumerWidget {
  const _FilesTab(this.id, this.json);
  final int id;
  final Map<String, dynamic> json;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = (json['files'] as List? ?? const []).cast<Map>();
    final stats = (json['fileStats'] as List? ?? const []).cast<Map>();
    final order = List.generate(files.length, (i) => i)
      ..sort((a, b) =>
          (files[a]['name'] as String).compareTo(files[b]['name'] as String));

    return ListView.builder(
      itemCount: order.length,
      itemBuilder: (context, n) {
        final i = order[n];
        final f = files[i];
        final length = (f['length'] as num).toInt();
        final done = (f['bytesCompleted'] as num).toInt();
        final wanted = i < stats.length ? stats[i]['wanted'] == true : true;
        return CheckboxListTile(
          dense: true,
          value: wanted,
          onChanged: (v) async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await ref
                  .read(transmissionProvider)
                  ?.setFilesWanted(id, [i], v ?? true);
              ref.invalidate(torrentDetailProvider(id));
            } on TransmissionException catch (e) {
              messenger.showSnackBar(SnackBar(content: Text(e.message)));
            }
          },
          title: Text(f['name'] as String,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${formatBytes(done)} / ${formatBytes(length)} · ${formatPercent(length == 0 ? 1 : done / length)}'),
        );
      },
    );
  }
}

class _PeersTab extends StatelessWidget {
  const _PeersTab(this.json);
  final Map<String, dynamic> json;

  @override
  Widget build(BuildContext context) {
    final peers = (json['peers'] as List? ?? const []).cast<Map>();
    if (peers.isEmpty) {
      return const EmptyState(Icons.people_outline, 'Aucun pair connecté');
    }
    return ListView.builder(
      itemCount: peers.length,
      itemBuilder: (_, i) {
        final p = peers[i];
        // rateToClient = ce que l'on reçoit du pair, rateToPeer = ce qu'on lui envoie.
        return ListTile(
          dense: true,
          title: Text('${p['address']}  ·  ${p['clientName']}'),
          subtitle: Text(
              '${formatPercent((p['progress'] as num).toDouble())}  ·  '
              '↓ ${formatSpeed(p['rateToClient'] as num)}  ↑ ${formatSpeed(p['rateToPeer'] as num)}'
              '  ·  ${p['flagStr']}'),
        );
      },
    );
  }
}

class _TrackersTab extends StatelessWidget {
  const _TrackersTab(this.json);
  final Map<String, dynamic> json;

  @override
  Widget build(BuildContext context) {
    final trackers = (json['trackerStats'] as List? ?? const []).cast<Map>();
    return ListView.builder(
      itemCount: trackers.length,
      itemBuilder: (_, i) {
        final tr = trackers[i];
        final last = (tr['lastAnnounceTime'] as num?)?.toInt() ?? 0;
        // L'URL d'annonce contient le passkey : on n'affiche que l'hôte.
        return ListTile(
          dense: true,
          title: Text(tr['host'] as String? ?? ''),
          subtitle: Text(
              '${tr['lastAnnounceResult'] ?? ''}'
              '${last > 0 ? ' · ${formatAgo(fromEpoch(last))}' : ''}\n'
              'Seeders ${tr['seederCount']} · Leechers ${tr['leecherCount']} · Téléchargés ${tr['downloadCount']}'),
          isThreeLine: true,
        );
      },
    );
  }
}
