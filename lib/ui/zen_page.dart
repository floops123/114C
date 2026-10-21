import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../core/format.dart';
import '../core/zen.dart';
import '../state/c411_overview.dart';
import '../state/cross_seed.dart';
import '../state/palliative.dart';
import '../state/zen_opportunities.dart';
import '../state/zen_portfolio.dart';
import 'c411_account.dart';
import 'charts.dart';
import 'cross_seed_page.dart';
import 'revive_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Rendement Zen (classe Swarm Keeper) : ce que rapporte chaque torrent
/// partagé, et ce qu'il serait rentable d'ajouter.
class ZenPage extends StatelessWidget {
  const ZenPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Rendement Zen'),
            bottom: const TabBar(
              tabAlignment: TabAlignment.fill,
              tabs: [Tab(text: 'Portefeuille'), Tab(text: 'Opportunités')],
            ),
          ),
          body: const TabBarView(children: [_PortfolioTab(), _OpportunitiesTab()]),
        ),
      );
}

/// Taille en Go comme le site (base 1024), sans décimale inutile.
String _gb(int bytes) => formatBytes(bytes).replaceFirst(RegExp(r',0+ '), ' ');
String _days(double d) => d < 1 ? '< 1 j' : '${d.floor()} j';

/// Bloc à intitulé.
class _Card extends StatelessWidget {
  const _Card({required this.title, this.icon, this.trailing, required this.children});
  final String title;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Panel(
      radius: 16,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: c.muted), const SizedBox(width: 6)],
            Expanded(
              child: Text(title.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11, letterSpacing: .7, fontWeight: FontWeight.w700, color: c.muted)),
            ),
            ?trailing,
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.detail});
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 130),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: c.muted)),
        Text(value,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
        if (detail != null) Text(detail!, style: TextStyle(fontSize: 11.5, color: c.muted)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Portefeuille

enum _HoldingSort {
  best('Plus rentables'),
  worst('Moins rentables'),
  next('Prochains paliers');

  const _HoldingSort(this.label);
  final String label;
}

class _PortfolioTab extends ConsumerStatefulWidget {
  const _PortfolioTab();

  @override
  ConsumerState<_PortfolioTab> createState() => _PortfolioTabState();
}

class _PortfolioTabState extends ConsumerState<_PortfolioTab> {
  _HoldingSort _sort = _HoldingSort.best;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(zenPortfolioProvider);
    final overview = ref.watch(c411OverviewProvider).value;
    return switch (async) {
      AsyncValue(:final error?) when async.value == null => Center(
          child: ErrorBanner('Transmission : $error',
              onRetry: () => ref.invalidate(zenPortfolioProvider))),
      AsyncValue(value: null) when async.isLoading =>
        const Center(child: CircularProgressIndicator()),
      AsyncValue(value: null) => const EmptyState(
          Icons.settings_rounded, 'Configure Transmission dans les Réglages.'),
      AsyncValue(:final value?) => () {
          final p = value;
          final holdings = switch (_sort) {
            _HoldingSort.best => p.holdings,
            _HoldingSort.worst => [...p.seeding]..sort((a, b) => a.perDay.compareTo(b.perDay)),
            _HoldingSort.next => p.upcoming(days: 30),
          };
          final latest = overview?.history?.latest;
          final forecast = overview?.forecast;
          final upcoming = p.upcoming();
          final upcomingGain = upcoming.fold(0.0, (n, h) {
            final s = h.estimate.nextStep!;
            return n + h.estimate.weight * s.gain * (1 + p.bonus) / zenScale;
          });
          final header = <Widget>[
            _Card(
              title: 'Estimation pour une journée complète',
              icon: Icons.calculate_rounded,
              trailing: IconButton(
                tooltip: 'Relire Transmission',
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: () => ref.invalidate(zenPortfolioProvider),
              ),
              children: [
                Wrap(spacing: 24, runSpacing: 12, children: [
                  _Stat('Zen par jour', frNumber(p.perDay, 1),
                      detail: [
                        if (latest != null) 'versé cette nuit : ${latest.paid}',
                        if (forecast?.projected != null) 'site ce soir : ≈ ${forecast!.projected}',
                      ].join(' · ')),
                  _Stat('Torrents C411 en partage', frNumber(p.seeding.length),
                      detail: '${p.holdings.length - p.seeding.length} à l’arrêt'),
                  _Stat('Note moyenne', frNumber(p.averageNote, 2),
                      detail: latest == null ? null : 'site : ${frNumber(latest.contribution, 2)}'),
                  _Stat('Coefficient de poids', frNumber(p.averageWeight, 2),
                      detail: latest == null ? null : 'site : ${frNumber(latest.weight, 2)}'),
                  _Stat('Bonus',
                      '+${frNumber(p.bonus * 100, (p.bonus * 100) % 1 == 0 ? 0 : 1)} %'),
                ]),
                const SizedBox(height: 10),
                Text(
                  'Calcul local (taille, seeders et durée de seed de Transmission). '
                  'L’écart avec le site vient surtout de la part de la journée partagée '
                  'et des seeders, comptés différemment.',
                  style: TextStyle(fontSize: 11.5, color: c.muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Card(title: 'Arbre de progression', icon: Icons.park_rounded, children: [
              _Progress('Note au moins 1,50 (+1 %)', p.atThreeQuarters, 100),
              // Le prochain palier à 2,00 pas encore atteint (ou le dernier).
              if ([
                for (final s in progressionSteps)
                  if (s.$2 >= 1 && p.atMax < s.$1) s,
              ].firstOrNull ?? progressionSteps.last case (final count, _, final points))
                _Progress('Note à 2,00 (+${frNumber(points * 100)} %)', p.atMax, count),
              const SizedBox(height: 4),
              Text('Bonus de l’arbre atteint : +${frNumber(p.treeBonusNow * 100)} %.'
                  ' La note monte avec la durée de seed : garder ses torrents paie.',
                  style: TextStyle(fontSize: 11.5, color: c.muted)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              if (upcoming.isNotEmpty)
                _Hint(c.success, Icons.trending_up_rounded,
                    '${upcoming.length} torrent${upcoming.length > 1 ? 's' : ''} passent un palier de '
                    'durée cette semaine : ≈ +${frNumber(upcomingGain, 2)} Zen/j.'),
              if (p.crowded.isNotEmpty)
                _Hint(c.warning, Icons.groups_rounded,
                    '${p.crowded.length} torrent${p.crowded.length > 1 ? 's' : ''} à la note de base : '
                    'trop de seeders pour leur taille.'),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: SegmentedButton<_HoldingSort>(
                  showSelectedIcon: false,
                  segments: [
                    for (final s in _HoldingSort.values) ButtonSegment(value: s, label: Text(s.label)),
                  ],
                  selected: {_sort},
                  onSelectionChanged: (s) => setState(() => _sort = s.first),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ];
          return RefreshIndicator(
            onRefresh: () => ref.refresh(zenPortfolioProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: header.length + holdings.length,
              itemBuilder: (_, i) => i < header.length
                  ? header[i]
                  : _HoldingRow(holding: holdings[i - header.length], bonus: p.bonus),
            ),
          );
        }(),
    };
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.label, this.have, this.need);
  final String label;
  final int have;
  final int need;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = have >= need;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
          Text('${frNumber(have)} / $need',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: done ? c.success : c.muted,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 4),
        Meter(value: have / need, color: done ? c.success : c.accent),
      ]),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.color, this.icon, this.text);
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Color.lerp(color, c.surface, 0.88),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Color.lerp(color, c.surface, 0.55)!),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ]),
      ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({required this.holding, required this.bonus});
  final ZenHolding holding;
  final double bonus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = holding.estimate;
    final step = e.nextStep;
    final small = TextStyle(fontSize: 11.5, color: c.muted);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(holding.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: holding.seeding ? null : c.muted)),
            const SizedBox(height: 3),
            Text(
              [
                _gb(e.bytes),
                '${holding.seedersKnown ? e.seeders : '?'} seeder${e.seeders > 1 ? 's' : ''}',
                'seedé ${_days(e.seedDays)}',
                'note ${frNumber(e.note, 2)}',
                'poids ${frNumber(e.weight, 2)}',
              ].join(' · '),
              style: small,
            ),
            if (step != null || e.crowded || !holding.seeding)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  if (!holding.seeding) Tag('À L’ARRÊT', color: c.danger),
                  if (e.crowded) Tag('TROP SEEDÉ', color: c.warning),
                  if (step != null)
                    Tag('+${frNumber(step.gain, 2)} DANS ${step.inDays.ceil()} J', color: c.success),
                ]),
              ),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(frNumber(holding.perDay, 3),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
          Text('Zen/j', style: small),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Opportunités

class _OpportunitiesTab extends ConsumerWidget {
  const _OpportunitiesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final state = ref.watch(zenOpportunitiesProvider);
    final notifier = ref.read(zenOpportunitiesProvider.notifier);
    final overview = ref.watch(c411OverviewProvider).value;
    final bonusBp = overview?.forecast?.today.bonusBp ?? overview?.history?.latest?.bonusBp;
    final bonus = bonusBp == null ? 0.25 : bonusBp / 10000;

    // Sans téléchargement : cross-seed vers C411 et réanimations à prime.
    final crossSeed = [
      for (final i in ref.watch(crossSeedProvider).items)
        if (i.target == Tracker.c411 && i.status == CrossSeedStatus.match && i.candidate != null)
          (i, estimateZen(bytes: i.candidate!.size, seeders: i.candidate!.seeders, bonus: bonus, joining: true)),
    ];
    final revivals = [
      for (final i in ref.watch(palliativeProvider).items)
        if (i.best != null && i.status == PalliativeStatus.available)
          (i, estimateZen(bytes: i.release.size, seeders: i.release.seeders, bonus: bonus, joining: true)),
    ];
    final free = <Widget>[
      _Card(title: 'Sans rien télécharger de plus', icon: Icons.bolt_rounded, children: [
        _FreeLine(
          title: 'Cross-seed vers C411',
          detail: crossSeed.isEmpty
              ? 'Lance l’analyse du cross-seed : les sorties C411 dont tu as déjà les fichiers.'
              : '${crossSeed.length} sortie${crossSeed.length > 1 ? 's' : ''} déjà sur ton disque',
          gain: crossSeed.isEmpty
              ? null
              : '+${frNumber(crossSeed.fold(0.0, (n, e) => n + e.$2.perDay), 2)} Zen/j',
          action: 'Cross-seed',
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const CrossSeedPage())),
        ),
        const Divider(height: 20),
        _FreeLine(
          title: 'Réanimations à prime',
          detail: revivals.isEmpty
              ? 'Lance « Soins palliatif » : les sorties C411 sans seeder disponibles ailleurs.'
              : '${revivals.length} réanimation${revivals.length > 1 ? 's' : ''} possible${revivals.length > 1 ? 's' : ''} '
                  '· prime totale ${revivals.fold(0, (n, e) => n + e.$1.release.bountyZen)} Zen '
                  '(+ bonus du gardien) après 72 h de partage',
          gain: revivals.isEmpty
              ? null
              : '+${frNumber(revivals.fold(0.0, (n, e) => n + e.$2.perDay), 2)} Zen/j',
          action: 'Soins palliatif',
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const RevivePage(palliative: true))),
        ),
      ]),
      const SizedBox(height: 12),
    ];

    final limits = state.limits;
    final controls = _Card(
      title: 'À télécharger puis partager',
      icon: Icons.download_rounded,
      children: [
        Text(
          'Sorties C411 avec 1 à 50 seeders, chacune estimée en te comptant parmi '
          'les seeders. Classement selon ce qui te limite (le nombre de torrents, '
          'ou la place disque), ou par note : ta note moyenne est ton indicateur '
          'de contribution, et l’arbre de progression compte les torrents bien notés.',
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<ZenRanking>(
            showSelectedIcon: false,
            segments: [for (final r in ZenRanking.values) ButtonSegment(value: r, label: Text(r.label))],
            selected: {state.ranking},
            onSelectionChanged: (s) => notifier.setRanking(s.first),
          ),
          _Choice<int?>(
            label: 'Torrents',
            value: limits.count,
            options: const [10, 25, 50, 100, null],
            text: (v) => v == null ? 'Tous' : '$v',
            onChanged: (v) => notifier.setLimits(limits.copyWith(count: () => v)),
          ),
          _Choice<double?>(
            label: 'Disque',
            value: limits.diskGb,
            options: const [50, 100, 250, 500, null],
            text: (v) => v == null ? 'Sans limite' : '${v.round()} Go',
            onChanged: (v) => notifier.setLimits(limits.copyWith(diskGb: () => v)),
          ),
          FilterChip(
            label: Text(state.ratioBudget == null
                ? 'Budget de ratio'
                : 'Budget de ratio (${_gb(state.ratioBudget!)})'),
            selected: limits.useRatio,
            onSelected: (v) => notifier.setLimits(limits.copyWith(useRatio: v)),
          ),
          FilterChip(
            label: const Text('Freeleech seulement'),
            selected: limits.freeleechOnly,
            onSelected: (v) => notifier.setLimits(limits.copyWith(freeleechOnly: v)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          if (state.scanning) ...[
            const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Expanded(child: Text('${frNumber(state.scanned)} sorties examinées…', style: TextStyle(color: c.muted))),
            TextButton(onPressed: notifier.stop, child: const Text('Stopper')),
          ] else ...[
            FilledButton.icon(
              onPressed: notifier.scan,
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              label: Text(state.searched ? 'Relancer' : 'Chercher'),
            ),
            const SizedBox(width: 12),
            if (state.searched)
              Expanded(
                child: Text('${state.items.length} trouvées sur ${frNumber(state.scanned)} examinées',
                    style: TextStyle(color: c.muted, fontSize: 12.5)),
              ),
          ],
        ]),
        if (state.ratioBudget != null && limits.useRatio)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Marge de téléchargement : ${_gb(state.ratioBudget!)} hors freeleech avant le '
              'blocage (upload, crédit compris, ÷ ratio minimum − download ; sans compter '
              'ton envoi à venir).',
              style: TextStyle(fontSize: 11.5, color: c.muted),
            ),
          ),
      ],
    );

    final header = <Widget>[
      ...free,
      controls,
      if (state.error != null) ...[const SizedBox(height: 8), ErrorBanner(state.error!)],
      const SizedBox(height: 8),
    ];
    final items = state.items;
    return Column(children: [
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: header.length + items.length,
          itemBuilder: (_, i) => i < header.length
              ? header[i]
              : _OpportunityRow(
                  item: items[i - header.length],
                  ranking: state.ranking,
                  onToggle: (v) => notifier.toggle(items[i - header.length].key, v),
                ),
        ),
      ),
      if (state.selected.isNotEmpty || state.sending)
        DecoratedBox(
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(children: [
                Expanded(
                  child: Text(
                    '${state.selected.length} sélectionnée${state.selected.length > 1 ? 's' : ''} · '
                    '${_gb(state.selectedSize)} · +${frNumber(state.selectedPerDay, 2)} Zen/j'
                    '${state.selectedRatioCost > 0 ? ' · ${_gb(state.selectedRatioCost)} sur le ratio' : ''}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: state.sending
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final added = await notifier.send();
                          messenger.showSnackBar(SnackBar(
                              content: Text('$added torrent${added > 1 ? 's' : ''} ajouté${added > 1 ? 's' : ''} à Transmission')));
                        },
                  icon: state.sending
                      ? SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent))
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(state.sending ? 'Ajout ${state.sent + 1} / ${state.toSend}…' : 'Ajouter'),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }
}

class _FreeLine extends StatelessWidget {
  const _FreeLine({
    required this.title,
    required this.detail,
    required this.action,
    required this.onTap,
    this.gain,
  });
  final String title;
  final String detail;
  final String? gain;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          Text(detail, style: TextStyle(fontSize: 12, color: c.muted)),
        ]),
      ),
      if (gain != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(gain!, style: TextStyle(fontWeight: FontWeight.w800, color: c.success)),
        ),
      OutlinedButton(onPressed: onTap, child: Text(action)),
    ]);
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.text,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<T> options;
  final String Function(T) text;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label ', style: TextStyle(fontSize: 12.5, color: c.muted)),
      DropdownButton<T>(
        value: value,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: [for (final o in options) DropdownMenuItem(value: o, child: Text(text(o)))],
        onChanged: (v) => onChanged(v as T),
      ),
    ]);
  }
}

class _OpportunityRow extends StatelessWidget {
  const _OpportunityRow({required this.item, required this.ranking, required this.onToggle});
  final ZenOpportunity item;
  final ZenRanking ranking;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = item.release;
    final e = item.estimate;
    final small = TextStyle(fontSize: 11.5, color: c.muted);
    final on = item.selected && !item.done;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: on ? c.accent.withValues(alpha: 0.07) : c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: item.done
                  ? c.success.withValues(alpha: 0.5)
                  : on
                      ? c.accent.withValues(alpha: 0.45)
                      : c.border),
        ),
        child: InkWell(
          onTap: item.done ? null : () => onToggle(!item.selected),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
            child: Row(children: [
              Checkbox(
                value: item.done ? true : item.selected,
                onChanged: item.done ? null : (v) => onToggle(v ?? false),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.title ?? r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (item.done) Tag('AJOUTÉ', color: c.success),
                    if (item.freeleech) Tag('FREELEECH', color: c.success),
                    if (r.subcategory.isNotEmpty) Tag(r.subcategory),
                    Text('${_gb(r.size)} · ${r.seeders} seeder${r.seeders > 1 ? 's' : ''} (+ toi) · '
                        'note ${frNumber(e.note, 2)} · poids ${frNumber(e.weight, 2)}',
                        style: small),
                  ]),
                  if (item.detail != null)
                    Text(item.detail!, style: small.copyWith(color: c.danger)),
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  switch (ranking) {
                    ZenRanking.perGb => frNumber(e.perGb, 3),
                    ZenRanking.perTorrent => frNumber(e.perDay, 2),
                    ZenRanking.note => frNumber(e.note, 2),
                  },
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                Text(
                    switch (ranking) {
                      ZenRanking.perGb => 'Zen/j/Go',
                      ZenRanking.perTorrent => 'Zen/j',
                      ZenRanking.note => 'note · ${frNumber(e.perDay, 2)} Zen/j',
                    },
                    style: small),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Bouton d'accès, pour la page C411.
class ZenPageButton extends StatelessWidget {
  const ZenPageButton({super.key});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ZenPage())),
          icon: const Icon(Icons.savings_rounded, size: 18),
          label: const Text('Rendement Zen : mon portefeuille, les opportunités'),
        ),
      );
}
