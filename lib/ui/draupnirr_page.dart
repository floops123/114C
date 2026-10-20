import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/draupnirr.dart';
import '../core/format.dart';
import '../state/draupnirr.dart';
import 'theme.dart';
import 'widgets.dart';

/// Onglet « Draupnirr » : compte, missions en cours, badges.
/// N'apparaît dans la barre principale que si la clé API est saisie.
class DraupnirrPage extends ConsumerWidget {
  const DraupnirrPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(draupnirrProvider);
    final notifier = ref.read(draupnirrProvider.notifier);
    final api = ref.watch(draupnirrApiProvider);
    if (api == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Draupnirr')),
        body: EmptyState(
          Icons.shield_outlined,
          'Configure la clé API Draupnirr dans les Réglages.',
        ),
      );
    }
    final c = context.colors;
    final account = state.account;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draupnirr'),
        actions: [
          if (state.loading)
            TextButton.icon(
              onPressed: null,
              icon: const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              label: const Text('Actualisation…'),
            )
          else
            TextButton.icon(
              onPressed: notifier.refresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Actualiser'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ErrorBanner(state.error!,
                    onRetry: () => notifier.refresh()),
              ),
            if (state.loadedAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'À jour ${formatAgo(state.loadedAt!)}',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ),
            if (account != null) _AccountSection(account: account),
            if (account == null && !state.loading)
              EmptyState(Icons.shield_outlined,
                  'Aucune donnée. Appuie sur « Actualiser ».'),
            if (state.badges.isNotEmpty)
              _BadgesSection(items: state.badges),
            if (state.missions.isNotEmpty)
              _MissionsSection(items: state.missions),
          ],
        ),
      ),
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.account});
  final DraupnirrAccount account;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tiles = <(String, String)>[
      if (account.username != null && account.username!.isNotEmpty)
        ('Pseudo', account.username!),
      if (account.ratio != null) ('Ratio', account.ratio!.toStringAsFixed(2)),
      if (account.uploaded != null) ('Upload', formatBytes(account.uploaded!)),
      if (account.downloaded != null)
        ('Download', formatBytes(account.downloaded!)),
      if (account.credits != null)
        ('Crédits', formatBytes(account.credits!)),
      if (account.seedtimeHours != null)
        ('Seedtime', '${account.seedtimeHours} h'),
      if (account.hnrCount != null) ('H&R', '${account.hnrCount}'),
      if (account.badges.isNotEmpty)
        ('Badges', account.badges.join(', ')),
    ];
    if (tiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          'Compte présent, mais aucune donnée n’a été reconnue dans la réponse.',
          style: TextStyle(color: c.muted, fontSize: 12.5),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text('Compte',
              style: TextStyle(
                  color: c.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ),
        Panel(
          radius: 14,
          child: Column(children: [
            for (var i = 0; i < tiles.length; i++)
              _Tile(
                label: tiles[i].$1,
                value: tiles[i].$2,
                last: i == tiles.length - 1,
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.last});
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(color: c.muted, fontSize: 13)),
        ),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _MissionsSection extends StatelessWidget {
  const _MissionsSection({required this.items});
  final List<DraupnirrMission> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text('Missions',
              style: TextStyle(
                  color: c.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ),
        Panel(
          radius: 14,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++)
                _MissionTile(
                  mission: items[i],
                  last: i == items.length - 1,
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _MissionTile extends StatelessWidget {
  const _MissionTile({required this.mission, required this.last});
  final DraupnirrMission mission;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fraction = mission.fraction;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(mission.title.isEmpty ? '(sans titre)' : mission.title,
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600)),
        if (mission.description != null && mission.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(mission.description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.muted, fontSize: 12)),
          ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: c.border,
            valueColor: AlwaysStoppedAnimation(
              fraction >= 1 ? c.success : c.accent,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text(
            mission.current != null && mission.target != null
                ? '${mission.current} / ${mission.target}'
                : '${(fraction * 100).toStringAsFixed(0)} %',
            style: TextStyle(color: c.muted, fontSize: 11.5),
          ),
          if (mission.reward != null && mission.reward!.isNotEmpty) ...[
            const Spacer(),
            Flexible(
              child: Text(
                '→ ${mission.reward!}',
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.muted,
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _BadgesSection extends StatelessWidget {
  const _BadgesSection({required this.items});
  final List<DraupnirrBadge> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final earned = items.where((b) => b.earned).toList();
    if (earned.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text('Badges (${earned.length})',
              style: TextStyle(
                  color: c.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ),
        Panel(
          radius: 14,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in earned) Chip(label: Text(b.name)),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}