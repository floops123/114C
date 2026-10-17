import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/transmission.dart';
import '../core/format.dart';
import '../state/speed_history.dart';
import '../state/torrents.dart';
import 'charts.dart';
import 'theme.dart';
import 'torrent_detail_page.dart';
import 'widgets.dart';

enum _Metric {
  uploaded('Envoyé'),
  downloaded('Reçu'),
  ratio('Ratio'),
  uploadRate('Vitesse d’envoi'),
  downloadRate('Vitesse de réception');

  const _Metric(this.label);
  final String label;

  double value(Torrent t) => switch (this) {
        uploaded => t.uploadedEver.toDouble(),
        downloaded => t.downloadedEver.toDouble(),
        ratio => t.ratio < 0 ? 0 : t.ratio,
        uploadRate => t.rateUpload.toDouble(),
        downloadRate => t.rateDownload.toDouble(),
      };

  String display(Torrent t) => switch (this) {
        uploaded => formatBytes(t.uploadedEver),
        downloaded => formatBytes(t.downloadedEver),
        ratio => formatRatio(t.ratio),
        uploadRate => formatSpeed(t.rateUpload),
        downloadRate => formatSpeed(t.rateDownload),
      };

  /// Couleur de la série : envoi ou réception ; le ratio relève de l'envoi.
  Color color(AppColors c) => switch (this) {
        downloaded || downloadRate => c.download,
        _ => c.upload,
      };
}

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  Duration _window = const Duration(minutes: 15);
  _Metric _metric = _Metric.uploaded;
  int _limit = 10;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final history = ref.watch(speedHistoryProvider);
    final torrents = ref.watch(torrentsProvider);
    final stats = ref.watch(sessionStatsProvider).value;
    final current = (stats?['current-stats'] as Map?)?.cast<String, dynamic>();
    final total = (stats?['cumulative-stats'] as Map?)?.cast<String, dynamic>();
    int n(Map<String, dynamic>? m, String k) => (m?[k] as num?)?.toInt() ?? 0;

    final since = history.global.isEmpty
        ? null
        : DateTime.now().difference(history.global.first.time).inSeconds;

    final ranked = torrents.byId.values
        .where((t) => _metric.value(t) > 0)
        .toList()
      ..sort((a, b) => _metric.value(b).compareTo(_metric.value(a)));

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            // Chiffres clés : des nombres, pas des graphiques.
            Wrap(spacing: 10, runSpacing: 10, children: [
              _StatTile('Réception', formatSpeed(torrents.downloadRate),
                  mark: c.download),
              _StatTile('Envoi', formatSpeed(torrents.uploadRate),
                  mark: c.upload),
              if (total != null) ...[
                _StatTile('Envoyé au total', formatBytes(n(total, 'uploadedBytes'))),
                _StatTile('Reçu au total', formatBytes(n(total, 'downloadedBytes'))),
                _StatTile(
                    'Ratio global',
                    n(total, 'downloadedBytes') == 0
                        ? '—'
                        : formatRatio(n(total, 'uploadedBytes') /
                            n(total, 'downloadedBytes'))),
              ],
              if (current != null)
                _StatTile('Cette session',
                    '↑ ${formatBytes(n(current, 'uploadedBytes'))}  ↓ ${formatBytes(n(current, 'downloadedBytes'))}'),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Text('Vitesse globale',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final minutes in const [5, 15, 30])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text('$minutes min'),
                    selected: _window.inMinutes == minutes,
                    onSelected: (_) => setState(
                        () => _window = Duration(minutes: minutes)),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            Text(
              since == null
                  ? 'Mesures enregistrées par l’application pendant qu’elle est ouverte.'
                  : 'Mesures enregistrées par l’application depuis ${formatDuration(since)}.',
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SpeedChart(
                    samples: history.global, window: _window, height: 220),
              ),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: Text('Par torrent',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Text('${ranked.length} torrent(s)',
                  style: TextStyle(color: c.muted, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            ChipRow<_Metric>(
              items: _Metric.values,
              selected: _metric,
              label: (m) => m.label,
              onSelected: (m) => setState(() => _metric = m),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: ranked.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Aucune donnée pour ce critère',
                            style: TextStyle(color: c.muted)),
                      )
                    : Column(children: [
                        BarList(
                          color: _metric.color(c),
                          items: [
                            for (final t in ranked.take(_limit))
                              BarItem(
                                t.name,
                                _metric.value(t),
                                _metric.display(t),
                                onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => TorrentDetailPage(
                                            id: t.id, name: t.name))),
                              ),
                          ],
                        ),
                        if (ranked.length > _limit)
                          TextButton(
                            onPressed: () => setState(() => _limit += 15),
                            child: Text(
                                'Afficher plus (${ranked.length - _limit} restants)'),
                          ),
                      ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value, {this.mark});
  final String label;
  final String value;

  /// Repère de couleur de la série concernée (le texte reste neutre).
  final Color? mark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (mark != null) ...[LineKey(mark!), const SizedBox(width: 6)],
          Text(label, style: TextStyle(color: c.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: c.text, fontSize: 20, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
