
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/jellyfin.dart';
import '../api/tmdb.dart';
import '../api/tracker.dart';
import '../core/format.dart';
import '../core/settings.dart';
import '../state/catalog.dart';
import '../state/media_library.dart';
import '../state/wishlist.dart';
import 'disk_page.dart';
import 'on_disk.dart';
import 'theme.dart';
import 'title_detail_page.dart';
import 'widgets.dart';
import 'wish_search_page.dart';

enum _Mode { list, discover }

/// Liste de souhaits : recherche TMDB, page Découvrir (rangées par catégorie,
/// genres) et recherche manuelle d'un souhait sur les trackers.
class WishlistPage extends ConsumerStatefulWidget {
  const WishlistPage({super.key});

  @override
  ConsumerState<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends ConsumerState<WishlistPage> {
  final _search = TextEditingController();
  String _query = '';
  _Mode? _mode;

  @override
  void initState() {
    super.initState();
    // Dates françaises des films de la liste, relues une fois par jour.
    Future.microtask(() {
      if (!mounted) return;
      final wishes = ref.read(wishlistProvider.notifier);
      wishes.refreshDates();
      wishes.refreshRatings();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _submit(String v) => setState(() => _query = v.trim());

  void _clear() {
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final wishes = ref.watch(wishlistProvider);
    final c = context.colors;
    // Liste vide : on ouvre sur Découvrir.
    final mode = _mode ?? (wishes.isEmpty ? _Mode.discover : _Mode.list);

    final Widget body;
    if (_query.isNotEmpty) {
      body = _SearchResults(query: _query);
    } else if (mode == _Mode.discover) {
      body = const _Discover();

    } else if (wishes.isEmpty) {
      body = const EmptyState(
        Icons.bookmark_border_rounded,
        'Cherche un film ou une série ci-dessus, ou parcours Découvrir, pour '
        'les ajouter à ta liste.',
      );
    } else {
      final (:items, :checking) =
          filterTitles(ref, [for (final w in wishes) w.title]);
      body = items.isEmpty
          ? EmptyState(Icons.filter_alt_off_rounded,
              checking ? 'Vérification sur les trackers…' : 'Aucun souhait pour ce filtre.')
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) => _TitleTile(title: items[i], wished: true),
            );
    }

    return Scaffold(
      body: Column(children: [
        PageHeader(
          title: 'Films & séries',
          subtitle: wishes.isEmpty
              ? null
              : Text('${wishes.length} dans la liste',
                  style: TextStyle(color: c.muted, fontSize: 12.5)),
        ),
        // Ma liste / Découvrir : bien visible, au-dessus de la recherche. Une
        // recherche en cours s'affiche à la place des deux.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: _ModeSwitch(
                selected: _query.isEmpty ? mode : null,
                count: wishes.length,
                onSelected: (m) {
                  if (_query.isNotEmpty) _clear();
                  setState(() => _mode = m);
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: _submit,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              hintText: 'Chercher un film ou une série sur TMDB',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: _clear,
                    ),
            ),
          ),
        ),
        DiskFilterChips(provider: tmdbDiskFilterProvider),
        const SizedBox(height: 8),
        Divider(height: 1, color: c.border),
        // Filtre « Sur le disque » : on affiche le statut et le bouton
        // « Actualiser » dans les deux modes (Découvrir et Ma liste),
        // pour que l'utilisateur voie l'état de la base et puisse la
        // reparcourir manuellement.
        if (ref.watch(tmdbDiskFilterProvider) == DiskFilter.onDisk)
          const LibraryStatus(),
        Expanded(child: body),
      ]),
    );
  }
}

/// Titre déjà chez soi : dans notre base, sinon dans l'index Jellyfin (déjà
/// chargé : aucune requête par affiche).
bool tmdbOnDisk(WidgetRef ref, TmdbTitle t) =>
    localForTmdb(ref, t) != null ||
    ref.watch(jellyfinLibraryProvider.select((l) => l.value?.find(t) != null));

/// Titres que laisse passer le filtre de la vue TMDB. Pour « À
/// télécharger », la disponibilité des titres pas encore vérifiés est
/// demandée ; [checking] : il en reste en cours.
({List<TmdbTitle> items, bool checking}) filterTitles(
    WidgetRef ref, List<TmdbTitle> items) {
  final filter = ref.watch(tmdbDiskFilterProvider);
  if (filter == DiskFilter.all) return (items: items, checking: false);
  final availability = ref.watch(availabilityProvider);
  final notifier = ref.read(availabilityProvider.notifier);
  var checking = false;
  final kept = <TmdbTitle>[];
  for (final t in items) {
    final onDisk = tmdbOnDisk(ref, t);
    final known = availability[t.key];
    if (filter == DiskFilter.toDownload && !onDisk && known == null &&
        !(t.type == TmdbType.movie && t.upcoming)) {
      checking = true;
      Future.microtask(() => notifier.request(t));
    }
    if (passesDiskFilter(filter, onDisk: onDisk, available: known?.any)) {
      kept.add(t);
    }
  }
  return (items: kept, checking: checking);
}

/// Pastille d'une affiche TMDB : ▶ si le titre est déjà chez soi, sinon ⬇
/// s'il est sur au moins un tracker (vérifié à l'affichage, mémorisé).
class AvailabilityBadge extends ConsumerWidget {
  const AvailabilityBadge({super.key, required this.title, this.size = 30});
  final TmdbTitle title;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = title;
    final local = localForTmdb(ref, t);
    final jellyfin =
        ref.watch(jellyfinLibraryProvider.select((l) => l.value?.find(t)));
    if (local != null || jellyfin != null) {
      final series = local?.isSeries ?? jellyfin!.isSeries;
      return RoundAction(
        icon: Icons.play_arrow_rounded,
        color: c.success,
        tooltip: series ? 'Épisodes' : 'Lire',
        size: size,
        onTap: () => local != null
            ? playLocal(context, local)
            : playOnJellyfin(context, jellyfin!),
      );
    }
    final known = ref.watch(availabilityProvider.select((m) => m[t.key]));
    if (known == null) {
      final notifier = ref.read(availabilityProvider.notifier);
      Future.microtask(() => notifier.request(t));
      return const SizedBox.shrink();
    }
    if (!known.any) return const SizedBox.shrink();
    return RoundAction(
      icon: Icons.download_rounded,
      color: c.download,
      tooltip: 'Télécharger (${known.trackers.map((t) => t.label).join(', ')})',
      size: size,
      onTap: () => openWishSearch(context, t),
    );
  }
}

/// Filtre « Tout / Sur le disque / À télécharger » d'une vue.
class DiskFilterChips extends ConsumerWidget {
  const DiskFilterChips({super.key, required this.provider});
  final NotifierProvider<DiskFilterNotifier, DiskFilter> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ChipRow<DiskFilter>(
        items: DiskFilter.values,
        selected: ref.watch(provider),
        label: (f) => f.label,
        icon: (f) => switch (f) {
          DiskFilter.all => Icons.apps_rounded,
          DiskFilter.onDisk => Icons.dns_rounded,
          DiskFilter.toDownload => Icons.download_rounded,
        },
        onSelected: ref.read(provider.notifier).set,
      );
}

/// Deux boutons : « Découvrir », décoré (dégradé, sous-titre) pour qu'on le
/// remarque, et « Ma liste », sobre, avec le nombre de souhaits. Le bouton du
/// mode affiché est marqué ; [selected] null : aucun (recherche en cours).
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch(
      {required this.selected, required this.count, required this.onSelected});
  final _Mode? selected;
  final int count;
  final ValueChanged<_Mode> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final discover = selected == _Mode.discover;
    final list = selected == _Mode.list;
    final shape = BorderRadius.circular(14);

    final discoverButton = FeatureButton(
      leading: const Icon(Icons.explore_rounded),
      title: 'Découvrir',
      subtitle: 'Films et séries, sorties en France',
      colors: [c.accent, c.download],
      selected: discover,
      onTap: () => onSelected(_Mode.discover),
    );

    // Même hauteur que « Découvrir » (titre + sous-titre).
    final listButton = SizedBox(
      height: 56,
      child: (list ? FilledButton.icon : OutlinedButton.icon)(
        onPressed: () => onSelected(_Mode.list),
        style: (list ? FilledButton.styleFrom : OutlinedButton.styleFrom)(
          shape: RoundedRectangleBorder(borderRadius: shape),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        icon: const Icon(Icons.bookmarks_rounded, size: 20),
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          const Flexible(
            child: Text('Ma liste',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: list ? c.onAccent.withValues(alpha: 0.18) : c.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );

    return Row(children: [
      Flexible(child: discoverButton),
      const SizedBox(width: 10),
      listButton,
    ]);
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(tmdbSearchProvider(query)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState(
              Icons.cloud_off_rounded,
              '$e',
              action: OutlinedButton(
                onPressed: () => ref.invalidate(tmdbSearchProvider(query)),
                child: const Text('Réessayer'),
              ),
            ),
            data: (all) {
              final (items: titles, :checking) = filterTitles(ref, all);
              return titles.isEmpty
                  ? EmptyState(
                      Icons.search_off_rounded,
                      checking
                          ? 'Vérification sur les trackers…'
                          : 'Aucun résultat.')
                  : ListView.builder(
                      itemCount: titles.length,
                      itemBuilder: (_, i) => _TitleTile(title: titles[i]),
                    );
            },
          );
}

/// Rangées d'affiches par catégorie, puis les genres (façon Seerr).
class _Discover extends ConsumerWidget {
  const _Discover();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(tmdbProvider) == null) {
      return const EmptyState(Icons.key_rounded,
          'Ajoute une clé TMDB dans Réglages pour découvrir les sorties.');
    }
    final onDisk = ref.watch(tmdbDiskFilterProvider) == DiskFilter.onDisk;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Filtre « Sur le disque » : on remet la vidéothèque devant les
        // rangées TMDB. (Le statut et le bouton « Actualiser » sont gérés
        // par le parent, pour rester visibles en mode « Ma liste » aussi.)
        if (onDisk) const _LibraryRow(),
        for (final feed in TmdbFeed.discover()) _FeedRow(feed: feed),
        for (final type in TmdbType.values) _GenreRow(type: type),
      ],
    );
  }
}

/// « Ta vidéothèque » : tous les titres de notre base, les derniers arrivés
/// d'abord.
class _LibraryRow extends ConsumerWidget {
  const _LibraryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final titles = [...ref.watch(mediaLibraryProvider).library.titles]
      ..sort((a, b) =>
          (b.added ?? DateTime(0)).compareTo(a.added ?? DateTime(0)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Ta vidéothèque (${titles.length})',
          icon: Icons.video_library_outlined),
      SizedBox(
        height: PosterCard.height(context),
        child: titles.isEmpty
            ? Center(
                child: Text(
                    ref.watch(settingsProvider.select((s) => s.value?.hasFtp ?? false))
                        ? 'Aucun fichier vidéo trouvé pour le moment.'
                        : 'Renseigne l’accès FTP dans les Réglages.',
                    style: TextStyle(color: c.muted)))
            : posterCarousel(
                titles.length,
                (i) => SizedBox(
                    width: PosterCard.width,
                    child: LocalTitleCard(title: titles[i]))),
      ),
    ]);
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.onMore, this.icon});
  final String text;
  final VoidCallback? onMore;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: context.colors.muted),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          if (onMore != null)
            TextButton(onPressed: onMore, child: const Text('Tout voir')),
        ]),
      );
}

/// Rangée horizontale de cartes, utilisable à la molette et à la souris.
Widget posterCarousel(int count, Widget Function(int i) item) => HorizontalScroller(
      builder: (controller) => ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => item(i),
      ),
    );

void _openFeed(BuildContext context, TmdbFeed feed) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => FeedPage(feed: feed)));

class _FeedRow extends ConsumerWidget {
  const _FeedRow({required this.feed});
  final TmdbFeed feed;


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titles = ref.watch(tmdbFeedProvider(feed));
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(feed.label, onMore: () => _openFeed(context, feed)),
        SizedBox(
          height: PosterCard.height(context),
          child: titles.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: TextButton.icon(
                onPressed: () => ref.invalidate(tmdbFeedProvider(feed)),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('$e', style: TextStyle(color: c.danger)),
              ),
            ),
            data: (all) {
              final (:items, :checking) = filterTitles(ref, all);
              return items.isEmpty
                  ? Center(
                      child: Text(
                          checking
                              ? 'Vérification sur les trackers…'
                              : 'Rien pour l’instant.',
                          style: TextStyle(color: c.muted)))
                  : posterCarousel(
                      items.length, (i) => PosterCard(title: items[i]));
            },
          ),
        ),
      ],
    );
  }
}

class _GenreRow extends ConsumerWidget {
  const _GenreRow({required this.type});
  final TmdbType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(tmdbGenresProvider(type)).value ?? const [];
    if (genres.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(type == TmdbType.movie
            ? 'Films par genre'
            : 'Séries par genre'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final g in genres)
              ActionChip(
                label: Text(g.name),
                onPressed: () =>
                    _openFeed(context, TmdbFeed.genre(g, type)),
              ),
          ]),
        ),
      ],
    );
  }
}

/// Affiche, titre et date ; marque-page si le titre est dans la liste.
class PosterCard extends ConsumerWidget {
  const PosterCard({super.key, required this.title, this.expand = false});
  final TmdbTitle title;

  /// Remplit la largeur de la grille plutôt que la largeur fixe des rangées.
  final bool expand;

  static const width = 112.0;
  static const _line = 1.3;

  /// Hauteur d'une carte : affiche 2:3, titre et année sur une ligne chacun,
  /// d'après la taille de texte du système (agrandie sur Android).
  static double height(BuildContext context) {
    final s = MediaQuery.textScalerOf(context);
    return width * 1.5 + 5 + (s.scale(12.5) + s.scale(11.5)) * _line + 4;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = title;
    final inList =
        ref.watch(wishlistProvider.select((l) => l.any((i) => i.title == t)));
    final card = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => openTitle(context, t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(fit: StackFit.expand, children: [
              Poster(t.posterUrl, radius: 8),
              Positioned(
                left: 5,
                top: 5,
                child: Tag(t.type.label,
                    solid: true,
                    color: t.type == TmdbType.movie ? null : c.info),
              ),
              if (inList)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Icon(Icons.bookmark_rounded, color: c.accent, size: 22),
                ),
              Positioned(right: 5, bottom: 5, child: AvailabilityBadge(title: t)),
            ]),
          ),
          const SizedBox(height: 5),
          Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, height: _line, fontWeight: FontWeight.w600)),
          Builder(builder: (context) {
            final style = TextStyle(fontSize: 11.5, height: _line, color: c.muted);
            return Text.rich(
              TextSpan(children: [
                TextSpan(text: t.year?.toString() ?? '—'),
                if (t.rating case final r?) ...[
                  const TextSpan(text: '  '),
                  ratingSpan(context, r, style),
                ],
              ]),
              maxLines: 1,
              style: style,
            );
          }),
        ],
      ),
    );
    return expand ? card : SizedBox(width: width, child: card);
  }
}

/// Liste complète d'une rangée ou d'un genre, chargée page par page.
class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key, required this.feed});
  final TmdbFeed feed;

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  final _items = <TmdbTitle>[];
  var _page = 0;
  var _totalPages = 1;
  var _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    final api = ref.read(tmdbProvider);
    if (api == null || _loading || _page >= _totalPages) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.feed(widget.feed, page: _page + 1);
      if (!mounted) return;
      final known = {for (final t in _items) t.key};
      setState(() {
        _items.addAll(r.items.where((t) => known.add(t.key)));
        _page++;
        // TMDB plafonne à 500 pages.
        _totalPages = r.totalPages.clamp(1, 500);
      });
    } on TmdbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = filterTitles(ref, _items).items;
    return Scaffold(
      appBar: AppBar(title: Text(widget.feed.label)),
      body: Column(children: [
        DiskFilterChips(provider: tmdbDiskFilterProvider),
        if (_error != null) ErrorBanner(_error!, onRetry: _more),
        Expanded(
          child: _items.isEmpty && _loading
              ? const Center(child: CircularProgressIndicator())
              : NotificationListener<ScrollNotification>(
                  // Page suivante un peu avant d'atteindre le bas.
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 600) _more();
                    return false;
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 150,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.52,
                    ),
                    itemCount: shown.length,
                    itemBuilder: (_, i) =>
                        PosterCard(title: shown[i], expand: true),
                  ),
                ),
        ),
      ]),
    );
  }
}

String dayLabel(DateTime d) => formatDate(d).substring(0, 10);

/// Date la plus utile : pour un film, la sortie française en salles à venir,
/// sinon la VOD française ; à défaut la date mondiale.
String titleDateLabel(TmdbTitle t) {
  final now = DateTime.now();
  final f = t.french;
  if (t.type == TmdbType.movie && f != null && !f.isEmpty) {
    if (f.cinema != null && f.cinema!.isAfter(now)) {
      return 'Au cinéma le ${dayLabel(f.cinema!)}';
    }
    if (f.digital != null) {
      return f.digital!.isAfter(now)
          ? 'En VOD le ${dayLabel(f.digital!)}'
          : 'En VOD depuis le ${dayLabel(f.digital!)}';
    }
    if (f.cinema != null) return 'Sorti au cinéma le ${dayLabel(f.cinema!)}';
  }
  final d = t.date;
  if (d == null) return 'Date inconnue';
  return switch ((t.type, d.isAfter(now))) {
    (TmdbType.movie, true) => 'Sortie le ${dayLabel(d)}',
    (TmdbType.movie, false) => 'Sorti le ${dayLabel(d)}',
    (TmdbType.tv, true) => 'Début le ${dayLabel(d)}',
    (TmdbType.tv, false) => 'Depuis le ${dayLabel(d)}',
  };
}

/// Ouvre la fiche complète d'un titre.
void openTitle(BuildContext context, TmdbTitle t) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => TitleDetailPage(title: t)));

void openWishSearch(BuildContext context, TmdbTitle t, [Tracker? tracker]) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WishSearchPage(title: t, initialTracker: tracker)));

/// Ligne de la liste ou d'une recherche TMDB. [wished] : ligne de la liste
/// (recherche sur les trackers et retrait) plutôt qu'un résultat.
class _TitleTile extends ConsumerWidget {
  const _TitleTile({required this.title, this.wished = false});
  final TmdbTitle title;
  final bool wished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = title;
    final inList =
        ref.watch(wishlistProvider.select((l) => l.any((i) => i.title == t)));
    final notifier = ref.read(wishlistProvider.notifier);

    // Carte, comme les transferts et les notifications.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
        child: InkWell(
          onTap: () => openTitle(context, t),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
            child: Row(children: [
              Poster(t.posterUrl, width: 56, height: 84, radius: 8),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [t.title, if (t.year != null) '(${t.year})'].join(' '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    if (t.originalTitle != null && t.originalTitle != t.title)
                      Text(t.originalTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.muted)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Tag(t.type.label,
                            color: t.type == TmdbType.movie ? c.accent : c.info),
                        Text(titleDateLabel(t),
                            style: TextStyle(
                                fontSize: 12,
                                color: t.upcoming ? c.text : c.muted)),
                        if (t.rating case final r?)
                          Text.rich(ratingSpan(context, r, const TextStyle(fontSize: 12))),
                        if (wished) OwnedTags(title: t),
                      ],
                    ),
                    if (!wished && t.overview != null) ...[
                      const SizedBox(height: 4),
                      Text(t.overview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.muted)),
                    ],
                  ],
                ),
              ),
              AvailabilityBadge(title: t),
              const SizedBox(width: 4),
              if (wished) ...[
                IconButton(
                  tooltip: 'Chercher sur les trackers',
                  icon: const Icon(Icons.travel_explore_rounded),
                  onPressed: () => openWishSearch(context, t),
                ),
                IconButton(
                  tooltip: 'Retirer de la liste',
                  icon: const Icon(Icons.bookmark_remove_outlined),
                  onPressed: () => notifier.remove(t),
                ),
              ] else
                IconButton(
                  tooltip: inList ? 'Retirer de la liste' : 'Ajouter à la liste',
                  icon: Icon(
                      inList
                          ? Icons.bookmark_added_rounded
                          : Icons.bookmark_add_outlined,
                      color: inList ? c.accent : null),
                  onPressed: () => notifier.toggle(t),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
