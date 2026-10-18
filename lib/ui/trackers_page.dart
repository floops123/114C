import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tmdb.dart';
import '../api/tracker.dart';
import '../core/format.dart';
import '../core/preferences.dart';
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
    final category = ref.watch(categoryFilterProvider);
    final filter = ref.watch(trackersDiskFilterProvider);
    final matches = ref.watch(tmdbMatchProvider);
    final only = ref.watch(trackerFilterProvider);
    final grid = ref.watch(uiPrefsProvider.select((p) => p.releasesGrid));

    // Titres par tracker, pour les pastilles du filtre.
    final perTracker = <Tracker, int>{};
    final all = groupReleases(state.releases);
    for (final g in all) {
      for (final t in g.trackers) {
        perTracker[t] = (perTracker[t] ?? 0) + 1;
      }
    }

    // Catégories présentes (avec leur nombre), avant le filtre de catégorie.
    final ofTracker = sortedGroups(state, only: only);
    final perCategory = <ContentKind, int>{};
    for (final g in ofTracker) {
      final k = groupKind(g);
      perCategory[k] = (perCategory[k] ?? 0) + 1;
    }
    final groups = [
      for (final g in ofTracker)
        if (category == null || groupKind(g).name == category) g,
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
          child: () {
            const loader = Center(
                child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)));
            final count = shown.length + (state.loading ? 1 : 0);
            return grid
                ? GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 170,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.5,
                    ),
                    itemCount: count,
                    itemBuilder: (_, i) =>
                        i >= shown.length ? loader : GroupCard(group: shown[i]),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemExtent: GroupTile.extent(context),
                    itemCount: count,
                    itemBuilder: (_, i) =>
                        i >= shown.length ? loader : GroupTile(group: shown[i]),
                  );
          }(),
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
              tooltip: grid ? 'Affichage liste' : 'Affichage grille',
              icon: Icon(grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
              onPressed: () =>
                  ref.read(uiPrefsProvider.notifier).setReleasesGrid(!grid),
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
        // Trackers, avec leur nombre de titres.
        if (trackers.length > 1) ...[
          ChipRow<Tracker?>(
            items: [null, ...trackers.keys],
            selected: only,
            label: (t) => t == null
                ? 'Tous les trackers (${all.length})'
                : '${t.label} (${perTracker[t] ?? 0})',
            icon: (t) => t == null ? Icons.hub_rounded : Icons.dns_rounded,
            onSelected: ref.read(trackerFilterProvider.notifier).set,
          ),
          const SizedBox(height: 6),
        ],
        _FilterBar(counts: perCategory, total: ofTracker.length),
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

/// Catégorie de contenu d'un titre, commune à tous les trackers : d'après la
/// sortie qui a une fiche (C411), sinon la première.
ContentKind groupKind(ReleaseGroup g) => ContentKind.of(
    g.releases.firstWhere((r) => r.mediaKind != null, orElse: () => g.releases.first));

/// Nom d'une catégorie dans les filtres.
String categoryLabel(ContentKind k) => switch (k) {
      ContentKind.movie => 'Films',
      ContentKind.series => 'Séries',
      ContentKind.documentary => 'Documentaires',
      ContentKind.animation => 'Animation',
      ContentKind.music => 'Musique',
      ContentKind.book => 'Livres',
      ContentKind.game => 'Jeux vidéo',
      ContentKind.software => 'Logiciels',
      ContentKind.adult => 'Adulte',
      ContentKind.other => 'Autres',
    };

/// Étiquette de catégorie sur une affiche ou une carte.
Widget categoryTag(AppColors c, ContentKind k, {bool solid = false}) => Tag(k.label,
    solid: solid,
    color: switch (k) {
      ContentKind.series => c.info,
      ContentKind.movie => solid ? null : c.accent,
      _ => k.colors(c).first,
    });

/// Catégories présentes (avec leur nombre), puis Sur le disque / À
/// télécharger, sur une seule rangée : la catégorie se choisit parmi elles,
/// le disque s'active et se désactive.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.counts, required this.total});
  final Map<ContentKind, int> counts;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final category = ref.watch(categoryFilterProvider);
    final disk = ref.watch(trackersDiskFilterProvider);
    Widget chip(String label, IconData icon, bool on, VoidCallback onTap) =>
        Center(
          child: ChoiceChip(
            avatar: Icon(icon, size: 16, color: on ? c.onAccent : c.muted),
            label: Text(label),
            selected: on,
            onSelected: (_) => onTap(),
          ),
        );
    final categories = ref.read(categoryFilterProvider.notifier);
    final disks = ref.read(trackersDiskFilterProvider.notifier);
    final items = [
      chip('Tout ($total)', Icons.apps_rounded, category == null,
          () => categories.set(null)),
      for (final k in ContentKind.values)
        if (counts[k] != null || category == k.name)
          chip('${categoryLabel(k)} (${counts[k] ?? 0})', k.icon,
              category == k.name, () => categories.set(k.name)),
      Center(
          child: SizedBox(
              height: 22, child: VerticalDivider(width: 9, color: c.border))),
      for (final f in [DiskFilter.onDisk, DiskFilter.toDownload])
        chip(
            f.label,
            f == DiskFilter.onDisk ? Icons.dns_rounded : Icons.download_rounded,
            disk == f,
            () => disks.set(disk == f ? DiskFilter.all : f)),
    ];
    return SizedBox(
      height: 38,
      child: HorizontalScroller(
        builder: (controller) => ListView.separated(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => items[i],
        ),
      ),
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
    final kind = groupKind(g);

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
                fallback: ContentArt(kind)),
            Positioned(
              left: 5,
              top: 5,
              right: 5,
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                categoryTag(c, kind, solid: true),
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
        Builder(builder: (context) {
          final style = TextStyle(fontSize: 11.5, height: 1.3, color: c.muted);
          return Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: [
                ?year?.toString(),
                '${g.releases.length} version${g.releases.length > 1 ? 's' : ''}',
              ].join(' · ')),
              if (tmdb?.rating case final r?) ...[
                const TextSpan(text: ' · '),
                ratingSpan(context, r, style),
              ],
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }),
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

/// Un titre des trackers en liste, dessiné comme un torrent des Transferts :
/// affiche, titre, trackers, qualité · versions · seeders, ▶ ou ⬇.
class GroupTile extends ConsumerWidget {
  const GroupTile({super.key, required this.group});
  final ReleaseGroup group;

  static const _line = 1.3;

  /// Hauteur fixe (liste fluide), d'après la taille du texte du système :
  /// marges 10, rembourrage 20, affiche 75 ou titre 14 + 2 lignes de 12.
  static double extent(BuildContext context) {
    final s = MediaQuery.textScalerOf(context);
    return 10 + 20 + math.max(75, (s.scale(14) + 2 * s.scale(12)) * _line + 10);
  }

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
    final kind = groupKind(g);
    final year = tmdb?.year ?? g.year;
    final small = TextStyle(fontSize: 12, height: _line, color: c.muted);
    Widget info(IconData icon, String text, {Color? color}) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color ?? c.muted),
            const SizedBox(width: 4),
            Text(text,
                style: small.copyWith(
                    color: color, fontWeight: color == null ? null : FontWeight.w700)),
          ]),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: playable != null ? c.success.withValues(alpha: 0.55) : c.border),
        ),
        child: InkWell(
          onTap: () => tmdb != null
              ? openTitle(context, tmdb)
              : openGroupVersions(context, g, null),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(children: [
              Poster(tmdb?.posterUrl ?? g.posterUrl,
                  width: 50,
                  height: 75,
                  radius: 6,
                  fallback: ContentArt(kind, radius: 6)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                            [tmdb?.title ?? g.title, if (year != null) '($year)'].join(' '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, height: _line, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 6),
                      categoryTag(c, kind),
                    ]),
                    const SizedBox(height: 4),
                    Text(g.trackers.map((t) => t.label).join(' · '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                    const SizedBox(height: 4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(children: [
                        if (playable != null)
                          info(Icons.dns_rounded, 'Sur le disque', color: c.success),
                        if (tmdb?.rating case final r?)
                          info(Icons.star_rounded, formatRating(r), color: c.warning),
                        if (g.bestResolution case final res?) info(Icons.hd_rounded, res),
                        info(Icons.layers_rounded,
                            '${g.releases.length} version${g.releases.length > 1 ? 's' : ''}'),
                        info(Icons.arrow_upward_rounded, '${g.maxSeeders}',
                            color: g.maxSeeders > 0 ? c.success : c.danger),
                        info(Icons.schedule_rounded, formatAgo(g.latest)),
                      ]),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              playable != null
                  ? RoundAction(
                      icon: Icons.play_arrow_rounded,
                      color: c.success,
                      tooltip: playable.isSeries ? 'Épisodes' : 'Lire',
                      size: 36,
                      onTap: () => playable.play(context),
                    )
                  : RoundAction(
                      icon: Icons.download_rounded,
                      color: c.download,
                      tooltip: 'Choisir une version à télécharger',
                      size: 36,
                      onTap: () => openGroupVersions(context, g, tmdb),
                    ),
            ]),
          ),
        ),
      ),
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
