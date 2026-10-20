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
            if (state.missions.isNotEmpty)
              _MissionsSection(items: state.missions),
            if (state.badges.isNotEmpty)
              _BadgesSection(items: state.badges),
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
        ('Pseudo',
            account.userClass == null || account.userClass!.isEmpty
                ? account.username!
                : '${account.username!} · ${account.userClass}'),
      if (account.ratio != null) ('Ratio', account.ratio!.toStringAsFixed(2)),
      if (account.uploaded != null) ('Upload', formatBytes(account.uploaded!)),
      if (account.downloaded != null)
        ('Download', formatBytes(account.downloaded!)),
      if (account.credits != null)
        ('Crédits', formatBytes(account.credits!)),
      if (account.buffer != null && account.buffer != account.credits)
        ('Tampon', formatBytes(account.buffer!)),
      if (account.invites != null)
        ('Invitations', '${account.invites}'),
      if (account.uploadsCount != null)
        ('Uploads', '${account.uploadsCount}'),
      if (account.seedtimeCumulativeHours != null)
        ('Seedtime cumulé', '${account.seedtimeCumulativeHours} h'),
      if (account.seedtimeCumulativeHours == null &&
          account.seedtimeHours != null)
        ('Seedtime', '${account.seedtimeHours} h'),
      if (account.hnrCount != null) ('H&R', '${account.hnrCount}'),
      if (account.freeleechGlobal == true)
        ('Freeleech', 'Global activé'),
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
    // Tri : non terminées d'abord, puis par période (quotidien > hebdo >
    // mensuel) puis par reward décroissant.
    final sorted = [...items]..sort((a, b) {
        if (a.completed != b.completed) return a.completed ? 1 : -1;
        final pa = a.period.index, pb = b.period.index;
        if (pa != pb) return pa.compareTo(pb);
        return (b.rewardCredits ?? 0).compareTo(a.rewardCredits ?? 0);
      });
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
              for (var i = 0; i < sorted.length; i++)
                _MissionTile(
                  mission: sorted[i],
                  last: i == sorted.length - 1,
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
        Row(children: [
          Expanded(
            child: Text(
              mission.title.isEmpty ? '(sans titre)' : mission.title,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
          _PeriodChip(period: mission.period),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: c.border,
            valueColor: AlwaysStoppedAnimation(
              mission.completed || fraction >= 1 ? c.success : c.accent,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text(
            mission.progress != null && mission.goalValue != null
                ? '${mission.progress} / ${_formatGoal(mission.goalValue!)}'
                : '${(fraction * 100).toStringAsFixed(0)} %',
            style: TextStyle(color: c.muted, fontSize: 11.5),
          ),
          const Spacer(),
          if (mission.rewardCredits != null)
            Text(
              '+${mission.rewardCredits} crédit${mission.rewardCredits! > 1 ? 's' : ''}',
              style: TextStyle(
                  color: c.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
        ]),
      ]),
    );
  }

  /// Formate la cible : les durées sont en secondes, on les convertit en
  /// heures lisibles.
  String _formatGoal(int n) {
    if (n >= 3600 && n % 3600 == 0) {
      final h = n ~/ 3600;
      return '$h h';
    }
    return '$n';
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.period});
  final DraupnirrMissionPeriod period;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.border,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        period.label,
        style: TextStyle(
            color: c.text,
            fontSize: 10.5,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _BadgesSection extends StatelessWidget {
  const _BadgesSection({required this.items});
  final List<DraupnirrBadge> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final earned = items.where((b) => b.earned).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
              'Badges ($earned / ${items.length})',
              style: TextStyle(
                  color: c.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ),
        Panel(
          radius: 14,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++)
                  _BadgeTile(
                    badge: items[i],
                    last: i == items.length - 1,
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.last});
  final DraupnirrBadge badge;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = badge.earned ? c.accent : c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
          badge.earned
              ? Icons.emoji_events_rounded
              : Icons.emoji_events_outlined,
          size: 22,
          color: color,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              badge.name.isEmpty ? badge.slug : badge.name,
              style: TextStyle(
                  color: badge.earned ? c.text : c.muted,
                  fontSize: 13,
                  fontWeight:
                      badge.earned ? FontWeight.w600 : FontWeight.w400),
            ),
            if (badge.description != null && badge.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(badge.description!,
                    style: TextStyle(color: c.muted, fontSize: 12)),
              ),
          ]),
        ),
      ]),
    );
  }
}