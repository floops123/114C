import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/transmission.dart';
import '../core/format.dart';
import '../state/torrents.dart';
import 'downloads_page.dart';
import 'theme.dart';
import 'torrent_actions.dart';
import 'widgets.dart';

class TorrentDetailPage extends ConsumerWidget {
  const TorrentDetailPage({super.key, required this.id, required this.name});
  final int id;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(torrentDetailProvider(id));
    final json = detail.value;
    final t = json == null ? null : Torrent(json);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t?.name ?? name, overflow: TextOverflow.ellipsis),
          actions: [
            if (t != null) ...[
              IconButton(
                tooltip: t.isStopped ? 'Démarrer' : 'Arrêter',
                icon: Icon(t.isStopped
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded),
                onPressed: () async {
                  await runTorrentAction(
                      context,
                      ref,
                      (c) => c.action(
                          t.isStopped ? 'torrent-start' : 'torrent-stop', [id]));
                  ref.invalidate(torrentDetailProvider(id));
                },
              ),
              TorrentMenu(
                torrents: [t],
                magnetLink: json!['magnetLink'] as String?,
                exclude: const {TorrentAction.start, TorrentAction.stop},
                onRemoved: () => Navigator.of(context).maybePop(),
              ),
            ],
          ],
          bottom: const TabBar(
            isScrollable: true,
            padding: EdgeInsets.symmetric(horizontal: 8),
            tabs: [
              Tab(text: 'Infos'),
              Tab(text: 'Fichiers'),
              Tab(text: 'Pairs'),
              Tab(text: 'Trackers'),
              Tab(text: 'Options'),
            ],
          ),
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
              _TrackersTab(id, json),
              _OptionsTab(id, json),
            ]),
        },
      ),
    );
  }
}

int _int(Map<String, dynamic> json, String k) =>
    (json[k] as num?)?.toInt() ?? 0;

class _InfoTab extends StatelessWidget {
  const _InfoTab(this.json);
  final Map<String, dynamic> json;

  @override
  Widget build(BuildContext context) {
    final t = Torrent(json);
    int i(String k) => _int(json, k);
    String date(String k) => i(k) > 0 ? formatDate(fromEpoch(i(k))) : '—';

    final c = context.colors;
    final color = torrentColor(t, c);
    final progress = t.isChecking ? t.recheckProgress : t.percentDone;
    final peersFrom = (json['peersFrom'] as Map?)?.cast<String, dynamic>();
    final webseeds = (json['webseeds'] as List? ?? const []).cast<String>();

    final transfer = <(String, String)>[
      ('Taille', formatBytes(t.totalSize)),
      if (t.sizeWhenDone != t.totalSize)
        ('Sélectionné', formatBytes(t.sizeWhenDone)),
      ('Vérifié', formatBytes(i('haveValid'))),
      if (i('haveUnchecked') > 0)
        ('Non vérifié', formatBytes(i('haveUnchecked'))),
      if (t.leftUntilDone > 0) ...[
        ('Restant', formatBytes(t.leftUntilDone)),
        ('Disponible chez les pairs', formatBytes(i('desiredAvailable'))),
      ],
      if (t.isDownloading) ('Temps restant', formatDuration(t.eta)),
      if (t.isSeeding && json.containsKey('etaIdle') && i('etaIdle') >= 0)
        ('Arrêt pour inactivité dans', formatDuration(i('etaIdle'))),
      ('Téléchargé', formatBytes(i('downloadedEver'))),
      ('Envoyé', formatBytes(i('uploadedEver'))),
      ('Ratio', formatRatio(t.ratio)),
      ('Corrompu', formatBytes(i('corruptEver'))),
      ('Pairs',
          '${t.peersConnected} connectés · ${t.peersSendingToUs} envoient · ${t.peersGettingFromUs} reçoivent'),
      if (webseeds.isNotEmpty)
        ('Webseeds', '${t.webseedsSendingToUs} / ${webseeds.length} actifs'),
    ];

    final details = <(String, String)>[
      ('Dossier', t.downloadDir),
      if (json['torrentFile'] != null)
        ('Fichier .torrent', '${json['torrentFile']}'),
      ('Fichiers',
          '${json['file-count'] ?? (json['files'] as List?)?.length ?? 0}'),
      if ((json['primary-mime-type'] as String? ?? '').isNotEmpty)
        ('Type', '${json['primary-mime-type']}'),
      ('Pièces', '${i('pieceCount')} × ${formatBytes(i('pieceSize'))}'),
      if (t.labels.isNotEmpty) ('Étiquettes', t.labels.join(', ')),
      if ((json['group'] as String? ?? '').isNotEmpty)
        ('Groupe', '${json['group']}'),
      ('Ajouté', date('addedDate')),
      ('Démarré', date('startDate')),
      ('Terminé', date('doneDate')),
      ('Dernière activité', date('activityDate')),
      if (i('editDate') > 0) ('Modifié', date('editDate')),
      ('En téléchargement', formatDuration(i('secondsDownloading'))),
      ('En partage', formatDuration(i('secondsSeeding'))),
      ('Privé', json['isPrivate'] == true ? 'Oui' : 'Non'),
      ('Créé par', '${json['creator'] ?? '—'}'),
      ('Créé le', date('dateCreated')),
      ('Hash', t.hash),
      if ((json['comment'] as String? ?? '').isNotEmpty)
        ('Commentaire', json['comment'] as String),
    ];

    const sources = {
      'fromTracker': 'Tracker',
      'fromDht': 'DHT',
      'fromPex': 'PEX',
      'fromLpd': 'Réseau local',
      'fromIncoming': 'Entrants',
      'fromLtep': 'LTEP',
      'fromCache': 'Cache',
    };

    return ListView(padding: const EdgeInsets.all(16), children: [
      Section(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(formatPercent(progress),
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  color: color)),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                [
                  t.statusLabel,
                  if (t.isQueued) 'n° ${t.queuePosition + 1} dans la file',
                  if (t.isStalled) 'bloqué',
                ].join(' · '),
                style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
              value: progress, color: color, minHeight: 6),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          StatPill(
              icon: Icons.south_rounded,
              color: c.accent,
              label: formatSpeed(t.rateDownload)),
          StatPill(
              icon: Icons.north_rounded,
              color: c.success,
              label: formatSpeed(t.rateUpload)),
          StatPill(icon: Icons.people_outline, label: '${t.peersConnected}'),
          StatPill(icon: Icons.balance_rounded, label: formatRatio(t.ratio)),
        ]),
        if (t.hasError) ...[
          const SizedBox(height: 12),
          Text(t.errorString, style: TextStyle(color: c.danger)),
        ],
      ]),
      if (json['pieces'] is String && i('pieceCount') > 0) ...[
        const SizedBox(height: 12),
        Section(title: 'Pièces', children: [
          PiecesMap(
            bits: base64Decode(json['pieces'] as String),
            count: i('pieceCount'),
            color: color,
          ),
        ]),
      ],
      const SizedBox(height: 12),
      Section(title: 'Transfert', children: [
        for (final (label, value) in transfer) InfoRow(label, value),
      ]),
      if (peersFrom != null && peersFrom.values.any((v) => v != 0)) ...[
        const SizedBox(height: 12),
        Section(title: 'Origine des pairs', children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final MapEntry(:key, :value) in sources.entries)
              if (_int(peersFrom, key) > 0)
                Tag('${_int(peersFrom, key)} · $value', color: c.accent),
          ]),
        ]),
      ],
      const SizedBox(height: 12),
      Section(title: 'Détails', children: [
        for (final (label, value) in details) InfoRow(label, value),
      ]),
    ]);
  }
}

/// Carte des pièces : chaque case regroupe plusieurs pièces quand il y en a
/// beaucoup, et son opacité reflète la proportion déjà téléchargée.
class PiecesMap extends StatelessWidget {
  const PiecesMap(
      {super.key, required this.bits, required this.count, required this.color});
  final Uint8List bits;
  final int count;
  final Color color;

  static const cell = 8.0, gap = 2.0, maxRows = 12;

  @override
  Widget build(BuildContext context) {
    final have = [
      for (var i = 0; i < count; i++)
        (i >> 3) < bits.length && bits[i >> 3] & (0x80 >> (i & 7)) != 0,
    ];
    final done = have.where((h) => h).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, constraints) {
        final columns =
            (constraints.maxWidth / (cell + gap)).floor().clamp(1, 1000);
        final cells = count.clamp(1, columns * maxRows);
        final rows = (cells / columns).ceil();
        return CustomPaint(
          size: Size(constraints.maxWidth, rows * (cell + gap)),
          painter: _PiecesPainter(
            have: have,
            cells: cells,
            columns: columns,
            color: color,
            empty: context.colors.surfaceAlt,
          ),
        );
      }),
      const SizedBox(height: 8),
      Text('$done / $count pièces',
          style: TextStyle(color: context.colors.muted, fontSize: 12)),
    ]);
  }
}

class _PiecesPainter extends CustomPainter {
  _PiecesPainter({
    required this.have,
    required this.cells,
    required this.columns,
    required this.color,
    required this.empty,
  });

  final List<bool> have;
  final int cells;
  final int columns;
  final Color color;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = PiecesMap.cell, gap = PiecesMap.gap;
    final paint = Paint();
    final perCell = have.length / cells;
    for (var i = 0; i < cells; i++) {
      final from = (i * perCell).floor();
      final to = ((i + 1) * perCell).ceil().clamp(from + 1, have.length);
      var n = 0;
      for (var p = from; p < to; p++) {
        if (have[p]) n++;
      }
      final ratio = n / (to - from);
      paint.color =
          ratio == 0 ? empty : color.withValues(alpha: 0.25 + 0.75 * ratio);
      final x = (i % columns) * (cell + gap);
      final y = (i ~/ columns) * (cell + gap);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, cell, cell), const Radius.circular(2)),
          paint);
    }
  }

  @override
  bool shouldRepaint(_PiecesPainter old) =>
      old.cells != cells ||
      old.columns != columns ||
      old.color != color ||
      !_same(old.have, have);

  static bool _same(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _FilesTab extends ConsumerWidget {
  const _FilesTab(this.id, this.json);
  final int id;
  final Map<String, dynamic> json;

  Future<void> _run(BuildContext context, WidgetRef ref,
      Future<void> Function(TransmissionClient c) action) async {
    await runTorrentAction(context, ref, action);
    ref.invalidate(torrentDetailProvider(id));
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, String path) async {
    final current = path.split('/').last;
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Renommer')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || name == current) return;
    if (!context.mounted) return;
    await _run(context, ref, (c) => c.renamePath(id, path, name.trim()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final files = (json['files'] as List? ?? const []).cast<Map>();
    final stats = (json['fileStats'] as List? ?? const []).cast<Map>();
    final order = List.generate(files.length, (i) => i)
      ..sort((a, b) =>
          (files[a]['name'] as String).compareTo(files[b]['name'] as String));
    // `wanted` vaut true/false, ou 0/1 selon les versions.
    bool wanted(int i) =>
        i >= stats.length ||
        (stats[i]['wanted'] != false && stats[i]['wanted'] != 0);
    int priority(int i) =>
        i < stats.length ? (stats[i]['priority'] as num?)?.toInt() ?? 0 : 0;
    final wantedCount =
        List.generate(files.length, wanted).where((w) => w).length;
    final rootName = Torrent(json).name;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Row(children: [
          Expanded(
            child: Text('$wantedCount / ${files.length} fichiers sélectionnés',
                style: TextStyle(color: c.muted, fontSize: 13)),
          ),
          // Une liste vide signifie « tous les fichiers » pour Transmission.
          TextButton(
            onPressed: () => _run(context, ref,
                (cl) => cl.torrentSet([id], {'files-wanted': <int>[]})),
            child: const Text('Tout'),
          ),
          TextButton(
            onPressed: () => _run(context, ref,
                (cl) => cl.torrentSet([id], {'files-unwanted': <int>[]})),
            child: const Text('Rien'),
          ),
          if (files.length > 1)
            IconButton(
              tooltip: 'Renommer le dossier',
              icon: const Icon(Icons.drive_file_rename_outline, size: 20),
              onPressed: () => _rename(context, ref, rootName),
            ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: order.length,
          itemBuilder: (context, n) {
            final i = order[n];
            final f = files[i];
            final path = f['name'] as String;
            final length = (f['length'] as num).toInt();
            final done = (f['bytesCompleted'] as num).toInt();
            final slash = path.lastIndexOf('/');
            final p = priority(i);
            return ListTile(
              dense: true,
              leading: Checkbox(
                value: wanted(i),
                onChanged: (v) => _run(context, ref,
                    (cl) => cl.setFilesWanted(id, [i], v ?? true)),
              ),
              title: Text(path.substring(slash + 1),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  if (slash > 0) path.substring(0, slash),
                  '${formatBytes(done)} / ${formatBytes(length)} · '
                      '${formatPercent(length == 0 ? 1 : done / length)}',
                ].join('\n'),
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
              trailing: PopupMenuButton<String>(
                tooltip: 'Priorité, renommer',
                icon: Icon(
                  switch (p) {
                    TransmissionClient.priorityHigh =>
                      Icons.keyboard_double_arrow_up_rounded,
                    TransmissionClient.priorityLow =>
                      Icons.keyboard_double_arrow_down_rounded,
                    _ => Icons.more_horiz_rounded,
                  },
                  color: switch (p) {
                    TransmissionClient.priorityHigh => c.warning,
                    TransmissionClient.priorityLow => c.info,
                    _ => c.muted,
                  },
                ),
                onSelected: (v) => v == 'rename'
                    ? _rename(context, ref, path)
                    : _run(context, ref,
                        (cl) => cl.setFilesPriority(id, [i], int.parse(v))),
                itemBuilder: (_) => [
                  for (final (value, label) in priorityLabels)
                    CheckedPopupMenuItem(
                      value: '$value',
                      checked: p == value,
                      child: Text('Priorité ${label.toLowerCase()}'),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'rename', child: Text('Renommer…')),
                ],
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _PeersTab extends StatelessWidget {
  const _PeersTab(this.json);
  final Map<String, dynamic> json;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    num rate(Map p) => (p['rateToClient'] as num) + (p['rateToPeer'] as num);
    final peers = (json['peers'] as List? ?? const []).cast<Map>().toList()
      ..sort((a, b) => rate(b).compareTo(rate(a)));
    if (peers.isEmpty) {
      return const EmptyState(Icons.people_outline, 'Aucun pair connecté');
    }
    return ListView.builder(
      itemCount: peers.length,
      itemBuilder: (_, i) {
        final p = peers[i];
        final progress = (p['progress'] as num).toDouble();
        // rateToClient = ce que l'on reçoit du pair, rateToPeer = ce qu'on lui envoie.
        return ListTile(
          dense: true,
          title: Row(children: [
            Expanded(
              child: Text('${p['address']}:${p['port'] ?? ''}',
                  overflow: TextOverflow.ellipsis),
            ),
            if (p['isEncrypted'] == true)
              Tooltip(
                  message: 'Chiffré',
                  child: Icon(Icons.lock_outline, size: 14, color: c.success)),
            if (p['isUTP'] == true)
              const Padding(
                  padding: EdgeInsets.only(left: 4), child: Tag('µTP')),
            if (p['isIncoming'] == true)
              const Padding(
                  padding: EdgeInsets.only(left: 4), child: Tag('entrant')),
          ]),
          subtitle:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${p['clientName']}  ·  ${formatPercent(progress)}  ·  '
              '↓ ${formatSpeed(p['rateToClient'] as num)}  '
              '↑ ${formatSpeed(p['rateToPeer'] as num)}  ·  ${p['flagStr']}',
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: progress, minHeight: 2),
            ),
          ]),
        );
      },
    );
  }
}

class _TrackersTab extends ConsumerWidget {
  const _TrackersTab(this.id, this.json);
  final int id;
  final Map<String, dynamic> json;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final controller =
        TextEditingController(text: json['trackerList'] as String? ?? '');
    final list = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trackers'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            minLines: 6,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
                helperText: 'Une URL d’annonce par ligne, '
                    'une ligne vide entre deux paliers'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    controller.dispose();
    if (list == null || !context.mounted) return;
    await runTorrentAction(
        context, ref, (c) => c.torrentSet([id], {'trackerList': list.trim()}));
    ref.invalidate(torrentDetailProvider(id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final trackers = (json['trackerStats'] as List? ?? const []).cast<Map>();
    String when(Object? epoch, {bool future = false}) {
      final s = (epoch as num?)?.toInt() ?? 0;
      if (s <= 0) return '—';
      final d = fromEpoch(s);
      if (!future) return formatAgo(d);
      final diff = d.difference(DateTime.now()).inSeconds;
      return diff <= 0 ? 'imminente' : 'dans ${formatDuration(diff)}';
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
          child: Text('${trackers.length} tracker(s)',
              style: TextStyle(color: c.muted)),
        ),
        if (json.containsKey('trackerList'))
          OutlinedButton.icon(
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Modifier'),
          ),
      ]),
      for (final tr in trackers) ...[
        const SizedBox(height: 12),
        Section(children: [
          Row(children: [
            Expanded(
              // L'URL d'annonce contient le passkey : on n'affiche que l'hôte.
              child: Text('${tr['sitename'] ?? tr['host']}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Tag('palier ${(tr['tier'] as num? ?? 0).toInt() + 1}'),
            if (tr['isBackup'] == true)
              const Padding(
                  padding: EdgeInsets.only(left: 4), child: Tag('secours')),
          ]),
          const SizedBox(height: 8),
          InfoRow(
            'Dernière annonce',
            '${when(tr['lastAnnounceTime'])} · ${tr['lastAnnounceResult'] ?? ''}',
            valueColor: tr['hasAnnounced'] == true &&
                    tr['lastAnnounceSucceeded'] == false
                ? c.danger
                : null,
          ),
          if (tr['lastAnnouncePeerCount'] != null)
            InfoRow('Pairs reçus', '${tr['lastAnnouncePeerCount']}'),
          InfoRow('Prochaine annonce',
              when(tr['nextAnnounceTime'], future: true)),
          InfoRow('Dernier scrape',
              '${when(tr['lastScrapeTime'])} · ${tr['lastScrapeResult'] ?? ''}'),
          InfoRow('Seeders · Leechers · Téléchargés',
              '${tr['seederCount']} · ${tr['leecherCount']} · ${tr['downloadCount']}'),
        ]),
      ],
    ]);
  }
}

/// Réglages propres au torrent (`torrent-set`). Les valeurs sont figées à
/// l'ouverture de l'onglet pour ne pas être écrasées par le rafraîchissement.
class _OptionsTab extends ConsumerStatefulWidget {
  const _OptionsTab(this.id, this.json);
  final int id;
  final Map<String, dynamic> json;

  @override
  ConsumerState<_OptionsTab> createState() => _OptionsTabState();
}

class _OptionsTabState extends ConsumerState<_OptionsTab> {
  static const _keys = [
    'bandwidthPriority', 'honorsSessionLimits', 'downloadLimited',
    'downloadLimit', 'uploadLimited', 'uploadLimit', 'seedRatioMode',
    'seedRatioLimit', 'seedIdleMode', 'seedIdleLimit', 'peer-limit', 'group',
    'sequentialDownload',
  ];
  static const _numbers = [
    'downloadLimit', 'uploadLimit', 'seedRatioLimit', 'seedIdleLimit',
    'peer-limit',
  ];

  late Map<String, dynamic> _original;
  late Map<String, dynamic> _values;
  final _text = <String, TextEditingController>{};
  List<String>? _groups;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reset(widget.json);
    _loadGroups();
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _reset(Map<String, dynamic> json) {
    _original = {
      for (final k in _keys)
        if (json.containsKey(k)) k: json[k],
    };
    _values = {..._original};
    for (final k in _numbers) {
      if (!_original.containsKey(k)) continue;
      final v = _original[k] as num;
      final c = _text.putIfAbsent(
          k, () => TextEditingController()..addListener(_refresh));
      c.text = k == 'seedRatioLimit'
          ? '${v.toDouble()}'.replaceAll('.', ',')
          : '${v.toInt()}';
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await ref.read(transmissionProvider)?.groupGet();
      if (mounted && groups != null) {
        setState(() => _groups = [for (final g in groups) '${g['name']}']);
      }
    } on TransmissionException {
      // Serveur < 4.0 : pas de groupes de bande passante.
    }
  }

  Map<String, dynamic> get _changes {
    final out = <String, dynamic>{};
    for (final k in _original.keys) {
      dynamic v = _values[k];
      final text = _text[k];
      if (text != null) {
        v = k == 'seedRatioLimit'
            ? double.tryParse(text.text.trim().replaceAll(',', '.'))
            : int.tryParse(text.text.trim());
        if (v == null) continue;
      }
      final before = _original[k];
      final changed = v is num && before is num
          ? v.toDouble() != before.toDouble()
          : v != before;
      if (changed) out[k] = v;
    }
    return out;
  }

  Future<void> _save() async {
    final changes = _changes;
    if (changes.isEmpty) return;
    setState(() => _saving = true);
    final ok = await runTorrentAction(
        context, ref, (c) => c.torrentSet([widget.id], changes),
        success: 'Options du torrent enregistrées');
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _reset({..._original, ...changes});
    });
    ref.invalidate(torrentDetailProvider(widget.id));
  }

  Widget _switch(String key, String label) {
    if (!_values.containsKey(key)) return const SizedBox.shrink();
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      value: _values[key] == true,
      onChanged: (v) => setState(() => _values[key] = v),
    );
  }

  Widget _number(String key, String label,
      {String? suffix, bool enabled = true}) {
    final c = _text[key];
    if (c == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      ),
    );
  }

  /// Mode de limite : 0 = réglage global, 1 = propre au torrent, 2 = illimité.
  Widget _mode(String key, String label) {
    if (!_values.containsKey(key)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Global')),
            ButtonSegment(value: 1, label: Text('Personnalisé')),
            ButtonSegment(value: 2, label: Text('Illimité')),
          ],
          selected: {(_values[key] as num).toInt()},
          onSelectionChanged: (s) => setState(() => _values[key] = s.first),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final changes = _changes.length;
    final group = _values['group'] as String?;
    final groups = _groups;

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (_values.containsKey('bandwidthPriority')) ...[
        Section(title: 'Priorité', children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final (value, label) in priorityLabels.reversed)
                ButtonSegment(value: value, label: Text(label)),
            ],
            selected: {(_values['bandwidthPriority'] as num).toInt()},
            onSelectionChanged: (s) =>
                setState(() => _values['bandwidthPriority'] = s.first),
          ),
          _switch('sequentialDownload', 'Téléchargement séquentiel'),
        ]),
        const SizedBox(height: 12),
      ],
      Section(title: 'Vitesse', children: [
        _switch('honorsSessionLimits', 'Respecter les limites globales'),
        _switch('downloadLimited', 'Limiter la réception'),
        _number('downloadLimit', 'Réception max',
            suffix: 'ko/s', enabled: _values['downloadLimited'] == true),
        _switch('uploadLimited', 'Limiter l’envoi'),
        _number('uploadLimit', 'Envoi max',
            suffix: 'ko/s', enabled: _values['uploadLimited'] == true),
        if (groups != null && groups.isNotEmpty && _values.containsKey('group'))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: DropdownButtonFormField<String>(
              initialValue: groups.contains(group) ? group : '',
              decoration:
                  const InputDecoration(labelText: 'Groupe de bande passante'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Aucun')),
                for (final g in groups)
                  DropdownMenuItem(value: g, child: Text(g)),
              ],
              onChanged: (v) => setState(() => _values['group'] = v ?? ''),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      Section(title: 'Partage', children: [
        _mode('seedRatioMode', 'Arrêt au ratio'),
        _number('seedRatioLimit', 'Ratio',
            enabled: _values['seedRatioMode'] == 1),
        _mode('seedIdleMode', 'Arrêt après inactivité'),
        _number('seedIdleLimit', 'Inactivité',
            suffix: 'min', enabled: _values['seedIdleMode'] == 1),
      ]),
      const SizedBox(height: 12),
      Section(title: 'Connexions', children: [
        _number('peer-limit', 'Pairs max'),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: Text(
            changes == 0 ? 'Aucune modification' : '$changes modification(s)',
            style: TextStyle(color: c.muted),
          ),
        ),
        TextButton(
          onPressed: changes == 0 || _saving
              ? null
              : () => setState(() => _reset(_original)),
          child: const Text('Annuler'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: changes == 0 || _saving ? null : _save,
          child: const Text('Enregistrer'),
        ),
      ]),
    ]);
  }
}
