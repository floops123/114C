import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tmdb.dart';
import '../api/tracker.dart';
import '../state/catalog.dart';
import '../state/wishlist.dart';
import 'content_art.dart';
import 'disk_page.dart';
import 'on_disk.dart';
import 'releases_page.dart';
import 'theme.dart';
import 'widgets.dart';
import 'wishlist_page.dart';

/// Ce qu'on peut lire pour un groupe : par sa fiche TMDB (notre base,
/// Jellyfin), sinon par l'une de ses sorties.
Playable? playableForGroup(WidgetRef ref, ReleaseGroup g, TmdbTitle? tmdb) {
  if (tmdb != null) {
    if (localForTmdb(ref, tmdb) case final local?) {
      return Playable(
          isSeries: local.isSeries,
          label: 'SUR LE DISQUE',
          description: 'Sur le disque',
          play: (context) => playLocal(context, local));
    }
  }
  for (final r in g.releases) {
    if (playableFor(ref, r) case final p?) return p;
  }
  return null;
}

/// Tops des trackers : les sorties de tous les trackers configurés,
/// regroupées par film ou série et illustrées par TMDB. On télécharge la
/// version de son choix, ou on lit le titre s'il est déjà sur le disque.
class TrackersPage extends ConsumerStatefulWidget {
  const TrackersPage({super.key});

  @override
  ConsumerState<TrackersPage> createState() => _TrackersPageState();
}

class _TrackersPageState extends ConsumerState<TrackersPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final trackers = ref.watch(trackersProvider);
    final state = ref.watch(topTrackersProvider);
    final notifier = ref.read(topTrackersProvider.notifier);
    final kind = ref.watch(topKindProvider);
    final filter = ref.watch(trackersDiskFilterProvider);
    final matches = ref.watch(tmdbMatchProvider);

    final groups = [
      for (final g in sortedGroups(state))
        if (kind == TopKind.all || (kind == TopKind.series) == (g.type == TmdbType.tv))
          g,
    ];
    final shown = [
      for (final g in groups)
        if (passesDiskFilter(filter,
            onDisk: playableForGroup(ref, g, matches[g.key]) != null,
            available: true))
          g,
    ];

    final Widget body;
    if (trackers.isEmpty) {
      body = const EmptyState(
          Icons.dns_outlined, 'Configure au moins un tracker dans Réglages.');
    } else if (shown.isEmpty && state.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (shown.isEmpty) {
      body = EmptyState(Icons.search_off_rounded,
          state.hasMore ? 'Rien pour ce filtre dans les sorties chargées.' : 'Aucun résultat.',
          action: state.hasMore
              ? OutlinedButton(
                  onPressed: notifier.loadMore, child: const Text('Charger plus'))
              : null);
    } else {
      body = RefreshIndicator(
        onRefresh: notifier.reload,
        child: NotificationListener<ScrollNotification>(
          // Pages suivantes un peu avant d'atteindre le bas.
          onNotification: (n) {
            if (n.metrics.extentAfter < 800 && state.hasMore && !state.loading) {
              notifier.loadMore();
            }
            return false;
          },
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              mainAxisSpacing: 16,
              crossAxisSpacing: 12,
              childAspectRatio: 0.5,
            ),
            itemCount: shown.length + (state.loading ? 1 : 0),
            itemBuilder: (_, i) => i >= shown.length
                ? const Center(
                    child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : GroupCard(group: shown[i]),
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          title: 'Trackers',
          subtitle: groups.isEmpty
              ? null
              : Text(
                  '${groups.length} titres · ${state.releases.length} sorties · '
                  '${trackers.length} tracker${trackers.length > 1 ? 's' : ''}',
                  style: TextStyle(color: c.muted, fontSize: 12.5)),
          actions: [
            SortMenu<TopSort>(
              options: TopSort.values,
              selected: state.sort,
              ascending: false,
              label: (s) => s.label,
              icon: (s) => switch (s) {
                TopSort.date => Icons.schedule_rounded,
                TopSort.seeders => Icons.trending_up_rounded,
              },
              ascendingByDefault: (_) => false,
              onChanged: (s, _) => notifier.configure(sort: s),
            ),
            IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: notifier.reload,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (q) => notifier.configure(query: q.trim()),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              hintText: 'Chercher sur tous les trackers',
              suffixIcon: state.query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        _search.clear();
                        notifier.configure(query: '');
                      },
                    ),
            ),
          ),
        ),
        ChipRow<TopKind>(
          items: TopKind.values,
          selected: kind,
          label: (k) => k.label,
          icon: (k) => switch (k) {
            TopKind.all => Icons.apps_rounded,
            TopKind.movies => ContentKind.movie.icon,
            TopKind.series => ContentKind.series.icon,
          },
          onSelected: ref.read(topKindProvider.notifier).set,
        ),
        const SizedBox(height: 6),
        DiskFilterChips(provider: trackersDiskFilterProvider),
        const SizedBox(height: 8),
        if (filter == DiskFilter.onDisk) const LibraryStatus(),
        for (final MapEntry(:key, :value) in state.errors.entries)
          ErrorBanner('${key.label} : $value', onRetry: notifier.reload),
        Divider(height: 1, color: c.border),
        Expanded(child: body),
      ]),
    );
  }
}

/// Affiche d'un titre des trackers : fiche TMDB (affiche, titre français),
/// trackers et meilleure qualité, ▶ s'il est sur le disque, sinon ⬇.
class GroupCard extends ConsumerWidget {
  const GroupCard({super.key, required this.group});
  final ReleaseGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final g = group;
    final tmdb = ref.watch(tmdbMatchProvider.select((m) => m[g.key]));
    if (!ref.read(tmdbMatchProvider).containsKey(g.key)) {
      final notifier = ref.read(tmdbMatchProvider.notifier);
      Future.microtask(() => notifier.request(g));
    }
    final playable = playableForGroup(ref, g, tmdb);
    final title = tmdb?.title ?? g.title;
    final year = tmdb?.year ?? g.year;
    final series = g.type == TmdbType.tv;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => tmdb != null
          ? openTitle(context, tmdb)
          : openGroupVersions(context, g, null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(fit: StackFit.expand, children: [
            Poster(tmdb?.posterUrl ?? g.posterUrl,
                radius: 8,
                fallback: ContentArt(
                    series ? ContentKind.series : ContentKind.movie)),
            Positioned(
              left: 5,
              top: 5,
              right: 5,
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                Tag(series ? 'Série' : 'Film',
                    solid: true, color: series ? c.info : null),
                if (g.bestResolution case final res?) Tag(res, solid: true),
              ]),
            ),
            Positioned(
              right: 5,
              bottom: 5,
              child: playable != null
                  ? RoundAction(
                      icon: Icons.play_arrow_rounded,
                      color: c.success,
                      tooltip: playable.isSeries ? 'Épisodes' : 'Lire',
                      onTap: () => playable.play(context),
                    )
                  : RoundAction(
                      icon: Icons.download_rounded,
                      color: c.download,
                      tooltip: 'Choisir une version à télécharger',
                      onTap: () => openGroupVersions(context, g, tmdb),
                    ),
            ),
          ]),
        ),
        const SizedBox(height: 5),
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w600)),
        Text(
            [
              ?year?.toString(),
              '${g.releases.length} version${g.releases.length > 1 ? 's' : ''}',
            ].join(' · '),
            maxLines: 1,
            style: TextStyle(fontSize: 11.5, height: 1.3, color: c.muted)),
        Text(
            [
              g.trackers.map((t) => t.label).join(', '),
              '▲ ${g.maxSeeders}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, height: 1.3, color: c.muted)),
      ]),
    );
  }
}

void openGroupVersions(BuildContext context, ReleaseGroup g, TmdbTitle? tmdb) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupVersionsPage(group: g, tmdb: tmdb)));

/// Les versions d'un titre, par tracker, les meilleures d'abord (profil
/// C411, puis seeders) ; chacune se télécharge ou se lit.
class GroupVersionsPage extends ConsumerWidget {
  const GroupVersionsPage({super.key, required this.group, this.tmdb});
  final ReleaseGroup group;
  final TmdbTitle? tmdb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final g = group;
    final t = tmdb ?? ref.watch(tmdbMatchProvider.select((m) => m[g.key]));
    final playable = playableForGroup(ref, g, t);
    final byTracker = <Tracker, List<Release>>{};
    for (final r in g.releases) {
      (byTracker[r.tracker] ??= []).add(r);
    }
    final rows = <Object>[
      for (final MapEntry(key: tracker, value: list) in byTracker.entries) ...[
        (tracker, list.length),
        for (final (_, group) in sortWish(list, WishSort.profile, false)) ...group,
      ],
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t?.title ?? g.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
              [
                ?(t?.year ?? g.year)?.toString(),
                '${g.releases.length} version${g.releases.length > 1 ? 's' : ''}',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: c.muted)),
        ]),
        actions: [
          if (t != null)
            IconButton(
              tooltip: 'Fiche',
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => openTitle(context, t),
            ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: rows.length + (playable != null ? 1 : 0),
        itemBuilder: (context, i) {
          if (playable != null) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  Icon(Icons.dns_rounded, color: c.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(playable.description,
                        style: TextStyle(
                            color: c.success, fontWeight: FontWeight.w600)),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: c.success, foregroundColor: Colors.white),
                    onPressed: () => playable.play(context),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(playable.isSeries ? 'Épisodes' : 'Lire'),
                  ),
                ]),
              );
            }
            i--;
          }
          return switch (rows[i]) {
            (final Tracker tracker, final int count) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('${tracker.label} ($count)',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            final Release r => SizedBox(
                height: ReleaseRow.extent(context),
                child: ReleaseRow(release: r),
              ),
            _ => const SizedBox.shrink(),
          };
        },
      ),
    );
  }
}
