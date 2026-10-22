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
        child: LayoutBuilder(builder: (context, box) {
          // PC : le compte et les badges à gauche, les missions à droite.
          final wide = box.maxWidth >= 1100;
          final left = [
            if (account != null) _AccountSection(account: account),
            if (account == null && !state.loading)
              EmptyState(Icons.shield_outlined,
                  'Aucune donnée. Appuie sur « Actualiser ».'),
            if (state.badges.isNotEmpty) _BadgesSection(items: state.badges),
          ];
          final right = [
            if (state.missions.isNotEmpty)
              _MissionsSection(items: state.missions),
          ];
          return ListView(
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
              if (wide && right.isNotEmpty)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                  const SizedBox(width: 16),
                  Expanded(flex: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
                ])
              else ...[
                ...left.take(left.length - (state.badges.isNotEmpty ? 1 : 0)),
                ...right,
                if (state.badges.isNotEmpty) left.last,
              ],
            ],
          );
        }),
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
    final a = account;
    Color ratioColor(double r) => r < 1 ? c.danger : r < 2 ? c.warning : c.success;
    final stats = <_Stat>[
      if (a.uploaded != null) _Stat(Icons.north_rounded, c.upload, 'Upload', formatBytes(a.uploaded!)),
      if (a.downloaded != null) _Stat(Icons.south_rounded, c.download, 'Download', formatBytes(a.downloaded!)),
      if (a.ratio != null) _Stat(Icons.balance_rounded, ratioColor(a.ratio!), 'Ratio', a.ratio!.toStringAsFixed(2).replaceAll('.', ',')),
      if (a.credits != null) _Stat(Icons.savings_rounded, c.accent, 'Crédits', frInt(a.credits!)),
      if (a.buffer != null && a.buffer != a.credits)
        _Stat(Icons.shield_rounded, c.info, 'Tampon', formatBytes(a.buffer!)),
      if (a.seedtimeCumulativeHours != null)
        _Stat(Icons.schedule_rounded, c.success, 'Seedtime cumulé', '${frInt(a.seedtimeCumulativeHours!)} h')
      else if (a.seedtimeHours != null)
        _Stat(Icons.schedule_rounded, c.success, 'Seedtime', '${frInt(a.seedtimeHours!)} h'),
      if (a.uploadsCount != null) _Stat(Icons.cloud_upload_rounded, c.upload, 'Uploads', '${a.uploadsCount}'),
      if (a.invites != null) _Stat(Icons.mail_rounded, c.muted, 'Invitations', '${a.invites}'),
      if (a.hnrCount != null)
        _Stat(Icons.warning_amber_rounded, a.hnrCount! > 0 ? c.danger : c.muted, 'H&R', '${a.hnrCount}'),
    ];
    final name = a.username ?? '';
    if (name.isEmpty && stats.isEmpty && a.badges.isEmpty) {
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
      child: Panel(
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(Icons.person_rounded, color: c.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(name.isEmpty ? 'Mon compte' : name,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  if (a.userClass != null && a.userClass!.isNotEmpty)
                    Tag(a.userClass!.replaceAll('_', ' ').toUpperCase(), color: c.accent),
                  if (a.freeleechGlobal == true) Tag('FREELEECH GLOBAL', color: c.success),
                ]),
              ),
            ]),
            if (a.badges.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final b in a.badges)
                  Chip(
                    avatar: Icon(Icons.emoji_events_rounded, size: 16, color: c.warning),
                    label: Text(b.replaceAll('-', ' ')),
                    visualDensity: VisualDensity.compact,
                  ),
              ]),
            ],
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, box) {
                // Tuiles de même largeur, 160 px au moins, rangées équilibrées
                // (9 chiffres : 3 × 3 plutôt que 4 + 4 + 1).
                final most = (box.maxWidth / 160).floor().clamp(2, 5);
                final rows = (stats.length / most).ceil();
                final perRow = (stats.length / rows).ceil().clamp(2, most);
                final width = (box.maxWidth - (perRow - 1) * 10) / perRow;
                return Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final t in stats) SizedBox(width: width, child: t),
                ]);
              }),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Entier avec espaces de milliers (« 2 644 »).
String frInt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '\u202f');

/// Tuile d'un chiffre du compte : pastille colorée, valeur, libellé.
class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.color, this.label, this.value);
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.muted)),
          ]),
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
        LayoutBuilder(builder: (context, box) {
          // Assez large : une grille de cartes plutôt qu'une longue liste.
          final perRow = (box.maxWidth / 340).floor();
          if (perRow < 2) {
            return Panel(
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
            );
          }
          final width = (box.maxWidth - (perRow - 1) * 10) / perRow;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final m in sorted)
              SizedBox(
                width: width,
                child: Panel(radius: 14, child: _MissionTile(mission: m, last: true)),
              ),
          ]);
        }),
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
                ? _formatProgress(mission.progress!, mission.goalValue!)
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

  /// « progression / cible ». Une cible en heures pleines est une durée en
  /// secondes : la progression est alors convertie elle aussi (« 1 h 30 / 2 h »).
  String _formatProgress(num progress, int goal) {
    if (goal >= 3600 && goal % 3600 == 0) {
      return '${_formatDuration(progress.toInt())} / ${_formatDuration(goal)}';
    }
    return '${frInt(progress.toInt())} / ${frInt(goal)}';
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
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