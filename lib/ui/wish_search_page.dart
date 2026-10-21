import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tmdb.dart';
import '../api/tracker.dart';
import '../core/preferences.dart';
import '../core/release_profile.dart';
import '../state/wishlist.dart';
import 'releases_page.dart';
import 'theme.dart';
import 'widgets.dart';
import 'wishlist_page.dart';

/// Recherche manuelle d'un souhait : un onglet par tracker configuré, avec le
/// nombre de résultats.
class WishSearchPage extends ConsumerWidget {
  const WishSearchPage({super.key, required this.title, this.initialTracker});
  final TmdbTitle title;

  /// Onglet ouvert d'abord (sinon le premier tracker).
  final Tracker? initialTracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackers = ref.watch(trackersProvider).keys.toList();
    final c = context.colors;
    final t = title;

    final appBar = AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(titleDateLabel(t),
              style: TextStyle(fontSize: 12, color: c.muted)),
        ],
      ),
      actions: [
        Builder(builder: (context) {
          final (sort, ascending) = ref.watch(wishSortProvider);
          return SortMenu<WishSort>(
            options: WishSort.values,
            selected: sort,
            ascending: ascending,
            label: (s) => s.label,
            icon: (s) => switch (s) {
              WishSort.relevance => Icons.auto_awesome_rounded,
              WishSort.quality => Icons.hd_rounded,
              WishSort.profile => Icons.workspace_premium_rounded,
              WishSort.size => Icons.storage_rounded,
              WishSort.seeders => Icons.trending_up_rounded,
              WishSort.date => Icons.event_rounded,
            },
            ascendingByDefault: (s) => s.ascendingByDefault,
            onChanged: ref.read(wishSortProvider.notifier).set,
          );
        }),
        Builder(builder: (context) {
          final grid = ref.watch(uiPrefsProvider.select((p) => p.releasesGrid));
          return IconButton(
            tooltip: grid ? 'Affichage liste' : 'Affichage grille',
            icon: Icon(grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
            onPressed: () =>
                ref.read(uiPrefsProvider.notifier).setReleasesGrid(!grid),
          );
        }),
        IconButton(
          tooltip: 'Fiche',
          icon: const Icon(Icons.info_outline_rounded),
          onPressed: () => openTitle(context, t),
        ),
        IconButton(
          tooltip: 'Relancer la recherche',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () {
            for (final tr in trackers) {
              ref.invalidate(wishSearchProvider((tr, t)));
            }
          },
        ),
      ],
      bottom: trackers.isEmpty
          ? null
          : TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final tr in trackers) _TrackerTab(tracker: tr, title: t),
              ],
            ),
    );

    if (trackers.isEmpty) {
      return Scaffold(
        appBar: appBar,
        body: const EmptyState(
            Icons.dns_outlined, 'Configure au moins un tracker dans Réglages.'),
      );
    }
    return DefaultTabController(
      length: trackers.length,
      initialIndex: math.max(0, trackers.indexOf(initialTracker ?? trackers.first)),
      child: Scaffold(
        appBar: appBar,
        body: TabBarView(children: [
          for (final tr in trackers) _TrackerResults(tracker: tr, title: t),
        ]),
      ),
    );
  }
}

/// Onglet : nom du tracker et nombre de résultats (ou chargement).
class _TrackerTab extends ConsumerWidget {
  const _TrackerTab({required this.tracker, required this.title});
  final Tracker tracker;
  final TmdbTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(wishSearchProvider((tracker, title)));
    return Tab(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(tracker.label),
        const SizedBox(width: 6),
        if (results.isLoading)
          const SizedBox.square(
              dimension: 12, child: CircularProgressIndicator(strokeWidth: 2))
        else if (results.hasError)
          Icon(Icons.error_outline_rounded,
              size: 16, color: context.colors.danger)
        else
          Badge(
            label: Text('${results.value?.length ?? 0}'),
            backgroundColor: (results.value?.isEmpty ?? true)
                ? context.colors.muted
                : context.colors.accent,
          ),
      ]),
    );
  }
}

class _TrackerResults extends ConsumerWidget {
  const _TrackerResults({required this.tracker, required this.title});
  final Tracker tracker;
  final TmdbTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(wishSearchProvider((tracker, title)));
    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(
        Icons.error_outline_rounded,
        '$e',
        action: OutlinedButton(
          onPressed: () => ref.invalidate(wishSearchProvider((tracker, title))),
          child: const Text('Réessayer'),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(Icons.search_off_rounded,
              'Rien sur ${tracker.label} pour l’instant.');
        }
        final (sort, ascending) = ref.watch(wishSortProvider);
        final grid = ref.watch(uiPrefsProvider.select((p) => p.releasesGrid));
        final groups = sortWish(items, sort, ascending);
        // Par groupe : intertitre, puis ses sorties en grille ou en liste
        // (construites à l'affichage).
        return LayoutBuilder(builder: (context, constraints) {
          return CustomScrollView(slivers: [
            for (final (header, group) in groups) ...[
              if (header != null)
                SliverToBoxAdapter(
                  child: _GroupHeader('$header (${group.length})',
                      subtitle: _profileByLabel[header]?.description),
                ),
              if (grid)
                releaseGrid(context, constraints.maxWidth, group.length,
                    (context, i) => releaseGridItem(context, group[i]))
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  sliver: SliverFixedExtentList(
                    itemExtent: ReleaseRow.extent(context),
                    delegate: SliverChildBuilderDelegate(
                        (context, i) => ReleaseRow(release: group[i]),
                        childCount: group.length),
                  ),
                ),
              if (grid) const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ]);
        });
      },
    );
  }
}

final _profileByLabel = {for (final p in C411Profile.values) p.label: p};

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text, {this.subtitle});
  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
          color: c.surfaceAlt,
          border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        if (subtitle != null)
          Text(subtitle!, style: TextStyle(fontSize: 11.5, color: c.muted)),
      ]),
    );
  }
}
