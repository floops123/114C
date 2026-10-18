import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/jellyfin.dart';
import '../api/tmdb.dart';
import '../api/transmission.dart';
import '../api/tracker.dart';
import '../core/format.dart';
import '../core/preferences.dart';
import '../core/release_profile.dart';
import '../core/settings.dart';
import '../state/catalog.dart';
import '../state/media_library.dart';
import '../state/wishlist.dart';
import 'disk_page.dart';
import 'on_disk.dart';
import 'releases_page.dart';
import 'series_page.dart';
import 'theme.dart';
import 'widgets.dart';

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
      onTap: () => _openSearch(context, t),
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
        // Filtre « Sur le disque » : tout ce qu'on possède d'abord, rangées
        // TMDB ensuite.
        if (onDisk) ...[const LibraryStatus(), const _LibraryRow()],
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
      _SectionTitle('Ta vidéothèque (${titles.length})',
          icon: Icons.video_library_outlined),
      SizedBox(
        height: _PosterCard.height(context),
        child: titles.isEmpty
            ? Center(
                child: Text(
                    ref.watch(settingsProvider.select((s) => s.value?.hasFtp ?? false))
                        ? 'Aucun fichier vidéo trouvé pour le moment.'
                        : 'Renseigne l’accès FTP dans les Réglages.',
                    style: TextStyle(color: c.muted)))
            : _carousel(
                titles.length,
                (i) => SizedBox(
                    width: _PosterCard.width,
                    child: LocalTitleCard(title: titles[i]))),
      ),
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.onMore, this.icon});
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
Widget _carousel(int count, Widget Function(int i) item) => HorizontalScroller(
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
        _SectionTitle(feed.label, onMore: () => _openFeed(context, feed)),
        SizedBox(
          height: _PosterCard.height(context),
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
                  : _carousel(
                      items.length, (i) => _PosterCard(title: items[i]));
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
        _SectionTitle(type == TmdbType.movie
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
class _PosterCard extends ConsumerWidget {
  const _PosterCard({required this.title, this.expand = false});
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
                        _PosterCard(title: shown[i], expand: true),
                  ),
                ),
        ),
      ]),
    );
  }
}

String _day(DateTime d) => formatDate(d).substring(0, 10);

/// Date la plus utile : pour un film, la sortie française en salles à venir,
/// sinon la VOD française ; à défaut la date mondiale.
String _dateLabel(TmdbTitle t) {
  final now = DateTime.now();
  final f = t.french;
  if (t.type == TmdbType.movie && f != null && !f.isEmpty) {
    if (f.cinema != null && f.cinema!.isAfter(now)) {
      return 'Au cinéma le ${_day(f.cinema!)}';
    }
    if (f.digital != null) {
      return f.digital!.isAfter(now)
          ? 'En VOD le ${_day(f.digital!)}'
          : 'En VOD depuis le ${_day(f.digital!)}';
    }
    if (f.cinema != null) return 'Sorti au cinéma le ${_day(f.cinema!)}';
  }
  final d = t.date;
  if (d == null) return 'Date inconnue';
  return switch ((t.type, d.isAfter(now))) {
    (TmdbType.movie, true) => 'Sortie le ${_day(d)}',
    (TmdbType.movie, false) => 'Sorti le ${_day(d)}',
    (TmdbType.tv, true) => 'Début le ${_day(d)}',
    (TmdbType.tv, false) => 'Depuis le ${_day(d)}',
  };
}

/// Ouvre la fiche complète d'un titre.
void openTitle(BuildContext context, TmdbTitle t) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => TitleDetailPage(title: t)));

void _openSearch(BuildContext context, TmdbTitle t, [Tracker? tracker]) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WishSearchPage(title: t, initialTracker: tracker)));

/// Fiche d'un titre : image de fond, infos, dates françaises, bande-annonce,
/// équipe, distribution, recommandations ; ajout à la liste et recherche sur
/// les trackers.
class TitleDetailPage extends ConsumerWidget {
  const TitleDetailPage({super.key, required this.title});
  final TmdbTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = title;
    final details = ref.watch(tmdbDetailsProvider(t));
    final d = details.value;
    final inList =
        ref.watch(wishlistProvider.select((l) => l.any((i) => i.title == t)));
    final small = TextStyle(fontSize: 12.5, color: c.muted);
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    // Image de fond proportionnée à la largeur ; l'affiche et le titre
    // viennent se poser sur son bas, en fondu (façon Seerr).
    final backdrop = d?.backdropUrl;
    final backdropHeight =
        (MediaQuery.sizeOf(context).width * 0.45).clamp(220.0, 420.0);

    // Déjà chez soi : lecture depuis l'affiche (un seul bouton dans la fiche).
    final local = localForTmdb(ref, t);
    final jellyfin = local == null ? ref.watch(jellyfinItemProvider(t)).value : null;
    final series = local?.isSeries ?? jellyfin?.isSeries ?? false;
    final VoidCallback? play = local != null
        ? () => playLocal(context, local)
        : jellyfin != null
            ? () => playOnJellyfin(context, jellyfin)
            : null;

    String hours(int minutes) => minutes < 60
        ? '$minutes min'
        : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';

    final header = Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16),
          ],
        ),
        child: Stack(alignment: Alignment.center, children: [
          Poster(t.posterUrl, width: 120, height: 180, radius: 10),
          if (play != null)
            RoundAction(
              icon: series ? Icons.video_library_rounded : Icons.play_arrow_rounded,
              color: c.success,
              tooltip: series ? 'Épisodes' : 'Lire',
              size: 52,
              onTap: play,
            ),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            if (t.originalTitle != null && t.originalTitle != t.title)
              Text(t.originalTitle!, style: small),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 6, children: [
              _Meta(t.type == TmdbType.movie
                  ? Icons.movie_outlined
                  : Icons.live_tv_rounded, t.type.label),
              if (t.year != null) _Meta(Icons.calendar_month_outlined, '${t.year}'),
              if (d?.runtime case final r? when r > 0)
                _Meta(Icons.schedule_rounded, hours(r)),
              if (d?.seasons case final s?)
                _Meta(Icons.video_library_outlined,
                    '$s saison${s > 1 ? 's' : ''}'
                    '${d!.episodes == null ? '' : ' · ${d.episodes} ép.'}'),
              if (d?.rating case final r?)
                _Meta(Icons.star_rounded,
                    '${r.toStringAsFixed(1).replaceAll('.', ',')} · ${d!.votes} votes',
                    color: c.warning),
              if (d?.certification case final cert? when cert.isNotEmpty)
                _Meta(Icons.shield_outlined, cert),
              if (d?.status case final s?) _Meta(Icons.info_outline_rounded, s),
              if (d != null && d.networks.isNotEmpty)
                _Meta(Icons.cell_tower_rounded, d.networks.take(2).join(', ')),
            ]),
          ],
        ),
      ),
    ]);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        // Bouton retour lisible sur l'image comme sur le fond uni.
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle),
            child: const BackButton(color: Colors.white),
          ),
        ),
      ),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Stack(children: [
            if (backdrop != null)
              SizedBox(
                height: backdropHeight,
                width: double.infinity,
                child: Stack(fit: StackFit.expand, children: [
                  // Recadrée par le haut : on garde les visages.
                  Poster(backdrop, radius: 0, alignment: Alignment.topCenter),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.35, 1],
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                          Theme.of(context).scaffoldBackgroundColor,
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(16,
                  backdrop == null ? topInset + 8 : backdropHeight - 130, 16, 0),
              child: header,
            ),
          ]),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d != null && d.genres.isNotEmpty) ...[
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final g in d.genres) Tag(g, color: c.accent),
                  ]),
                  const SizedBox(height: 14),
                ],
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: () =>
                        ref.read(wishlistProvider.notifier).toggle(t),
                    icon: Icon(inList
                        ? Icons.bookmark_remove_outlined
                        : Icons.bookmark_add_outlined),
                    label: Text(inList ? 'Retirer de la liste' : 'Ajouter à la liste'),
                  ),
                  if (d?.trailer case final url?)
                    FilledButton.icon(
                      style: _tinted(c, c.danger),
                      onPressed: () =>
                          launchUrl(url, mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.smart_display_rounded),
                      label: const Text('Bande-annonce'),
                    ),
                ]),
                if (details.hasError) ...[
                  const SizedBox(height: 8),
                  ErrorBanner('${details.error}',
                      onRetry: () => ref.invalidate(tmdbDetailsProvider(t))),
                ],
                _InfoBlocks(
                    title: t, dates: d?.french, loading: details.isLoading),
                if (d?.tagline case final tagline?) ...[
                  const SizedBox(height: 16),
                  Text('« $tagline »',
                      style: const TextStyle(
                          fontSize: 14, fontStyle: FontStyle.italic)),
                ],
                if (t.overview != null) ...[
                  const SizedBox(height: 10),
                  Text(t.overview!,
                      style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.5)),
                ],
                if (d != null && (d.directors.isNotEmpty || d.writers.isNotEmpty)) ...[
                  const SizedBox(height: 14),
                  if (d.directors.isNotEmpty)
                    _Credit(
                        Icons.movie_creation_outlined,
                        t.type == TmdbType.movie ? 'Réalisation' : 'Création',
                        d.directors),
                  if (d.writers.isNotEmpty)
                    _Credit(Icons.edit_note_rounded, 'Scénario', d.writers),
                ],
              ],
            ),
          ),
        ),
        if (details.isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        // Série : les épisodes directement dans la fiche, de notre base, sinon
        // de Jellyfin s'il est configuré.
        if (t.type == TmdbType.tv && localForTmdb(ref, t) != null)
          SliverToBoxAdapter(
              child: LocalEpisodesSection(title: localForTmdb(ref, t)!))
        else if (t.type == TmdbType.tv && ref.watch(jellyfinProvider) != null)
          SliverToBoxAdapter(
            child: SeriesEpisodesSection(
              series: ref.watch(jellyfinItemProvider(t)).value,
              loading: ref.watch(jellyfinItemProvider(t)).isLoading,
            ),
          ),
        if (d != null && d.cast.isNotEmpty) ...[
          const SliverToBoxAdapter(
              child: _SectionTitle('Distribution', icon: Icons.groups_outlined)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: _PersonCard.height(context),
              child: _carousel(
                  d.cast.length, (i) => _PersonCard(person: d.cast[i])),
            ),
          ),
        ],
        if (d != null && d.recommendations.isNotEmpty) ...[
          const SliverToBoxAdapter(
              child: _SectionTitle('Recommandations',
                  icon: Icons.recommend_outlined)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: _PosterCard.height(context),
              child: _carousel(d.recommendations.length,
                  (i) => _PosterCard(title: d.recommendations[i])),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}

/// Ce qu'on a déjà : le titre dans Jellyfin, et ses torrents dans
/// Transmission (téléchargés ou en cours). Rien n'est affiché s'il n'y a rien.
/// « Déjà chez toi », « Sorties en France » et « Sur les trackers » : côte à
/// côte sur PC (assez de largeur), les uns sous les autres sinon. Seuls les
/// encadrés qui ont quelque chose à montrer prennent une colonne.
class _InfoBlocks extends ConsumerWidget {
  const _InfoBlocks(
      {required this.title, required this.dates, required this.loading});
  final TmdbTitle title;
  final FrenchDates? dates;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = [
      if (_OwnedBlock.visible(ref, title)) _OwnedBlock(title: title),
      if (title.type == TmdbType.movie)
        _FrenchDatesBlock(title: title, dates: dates, loading: loading),
      if (ref.watch(trackersProvider).isNotEmpty) _TrackersBlock(title: title),
    ];
    if (blocks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 860 || blocks.length < 2) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, b) in blocks.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              b,
            ],
          ]);
        }
        // Côte à côte, tous à la hauteur du plus grand.
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, b) in blocks.indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: b),
            ],
          ]),
        );
      }),
    );
  }
}

class _OwnedBlock extends ConsumerWidget {
  const _OwnedBlock({required this.title});
  final TmdbTitle title;

  /// Quelque chose à montrer : élément Jellyfin, torrents, ou erreur.
  static bool visible(WidgetRef ref, TmdbTitle t) {
    final jellyfin = ref.watch(jellyfinItemProvider(t));
    return localForTmdb(ref, t) != null ||
        jellyfin.value != null ||
        jellyfin.hasError ||
        ref.watch(localTorrentsProvider(t)).isNotEmpty;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final jellyfin = ref.watch(jellyfinItemProvider(title));
    final item = jellyfin.value;
    final torrents = ref.watch(localTorrentsProvider(title));
    final local = localForTmdb(ref, title);
    if (local == null && item == null && torrents.isEmpty && !jellyfin.hasError) {
      return const SizedBox.shrink();
    }
    return _InfoCard(
      icon: Icons.inventory_2_rounded,
      title: 'Déjà chez toi',
      color: c.success,
      children: [
        if (local != null)
          _InfoRow(
            leading: Icon(Icons.dns_rounded, size: 20, color: c.success),
            title: 'Sur le disque',
            subtitle: local.isSeries
                ? '${local.files.length} épisode${local.files.length > 1 ? 's' : ''}'
                    ' · ${local.seasons.length} saison${local.seasons.length > 1 ? 's' : ''}'
                : [
                    for (final f in MediaTitle.best(local.files).take(3))
                      [?f.guess.resolution, formatBytes(f.size)].join(' '),
                  ].join(' · '),
          ),
        if (item != null && local == null)
          _InfoRow(
            leading: Icon(Icons.video_library_rounded, size: 20, color: c.success),
            title: 'Dans la bibliothèque Jellyfin',
            subtitle: [
              item.name,
              if (item.year != null) '${item.year}',
              if (item.played)
                'déjà vu'
              else if (item.progress case final p?)
                'vu à ${(p * 100).round()} %',
            ].join(' · '),
          ),
        if (jellyfin.hasError && local == null)
          _InfoRow(
            leading: Icon(Icons.error_outline_rounded, size: 20, color: c.danger),
            title: 'Jellyfin',
            subtitle: '${jellyfin.error}',
          ),
        for (final torrent in torrents) _LocalTorrent(torrent: torrent),
      ],
    );
  }
}

/// Encadré de la fiche (« Déjà chez toi », « Sorties en France », « Sur les
/// trackers ») : même carte, même en-tête, mêmes marges pour tous.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.children,
  });
  final IconData icon;
  final String title;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Color.lerp(color, c.surface, 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 4),
          ...children,
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Ligne d'un encadré : icône, titre, détail, et à droite une action.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.leading,
    required this.title,
    this.subtitle,
    this.detail,
    this.trailing,
  });
  /// Icône (20 px) ou indicateur de chargement.
  final Widget leading;
  final String title;
  final String? subtitle;

  /// Sous le titre, à la place de [subtitle] (barre de progression…).
  final Widget? detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: Center(child: leading),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.muted)),
            ],
            if (detail != null) ...[const SizedBox(height: 4), detail!],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}

/// Pastilles d'un souhait déjà présent : Jellyfin, Transmission.
class _OwnedTags extends ConsumerWidget {
  const _OwnedTags({required this.title});
  final TmdbTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final inJellyfin = ref.watch(jellyfinItemProvider(title)).value != null;
    final torrents = ref.watch(localTorrentsProvider(title));
    final done = torrents.any((t) => t.percentDone >= 1);
    final progress = torrents.isEmpty
        ? null
        : torrents.map((t) => t.percentDone).reduce(math.max);
    final onDisk = localForTmdb(ref, title) != null;
    return Wrap(spacing: 6, children: [
      if (onDisk) Tag('Sur le disque', color: c.success)
      else if (inJellyfin) Tag('Dans Jellyfin', color: c.success),
      if (done)
        Tag('Téléchargé', color: c.success)
      else if (progress != null)
        Tag('En cours ${formatPercent(progress)}', color: c.info),
    ]);
  }
}

class _LocalTorrent extends StatelessWidget {
  const _LocalTorrent({required this.torrent});
  final Torrent torrent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = torrent.percentDone >= 1;
    return _InfoRow(
      leading: Icon(done ? Icons.download_done_rounded : Icons.downloading_rounded,
          size: 20, color: done ? c.success : c.info),
      title: torrent.name,
      subtitle: done
          ? 'Téléchargé dans Transmission · ${formatBytes(torrent.totalSize)}'
          : null,
      detail: done
          ? null
          : Row(children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: torrent.percentDone,
                  color: c.download,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(formatPercent(torrent.percentDone),
                  style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
    );
  }
}

/// Bouton teinté : fond doux et bord de la couleur, texte et icône francs.
/// Couleurs opaques (mélange avec la surface), sans transparence.
ButtonStyle _tinted(AppColors c, Color color) => FilledButton.styleFrom(
      backgroundColor: Color.lerp(color, c.surface, 0.78),
      foregroundColor: Color.lerp(color, c.text, 0.25),
      side: BorderSide(color: Color.lerp(color, c.surface, 0.45)!),
    );

/// Petite info à icône (durée, note…).
class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text, {this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.colors.muted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 4),
      Text(text,
          style: TextStyle(
              fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// Disponibilité sur chaque tracker : nombre de sorties, meilleure qualité,
/// langues, seeders, freeleech. Lancée d'office pour un titre déjà sorti, à
/// la demande pour un titre à venir (inutile de solliciter les trackers).
class _TrackersBlock extends ConsumerStatefulWidget {
  const _TrackersBlock({required this.title});
  final TmdbTitle title;

  @override
  ConsumerState<_TrackersBlock> createState() => _TrackersBlockState();
}

class _TrackersBlockState extends ConsumerState<_TrackersBlock> {
  late bool _started = !widget.title.upcoming;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final trackers = ref.watch(trackersProvider).keys.toList();
    if (trackers.isEmpty) return const SizedBox.shrink();
    return _InfoCard(
      icon: Icons.travel_explore_rounded,
      title: 'Sur les trackers',
      color: c.download,
      children: [
        if (!_started)
          _InfoRow(
            leading: Icon(Icons.manage_search_rounded, size: 20, color: c.muted),
            title: 'Pas encore sorti',
            subtitle: 'La recherche se lance à la demande.',
            trailing: TextButton(
              onPressed: () => setState(() => _started = true),
              child: const Text('Vérifier la disponibilité'),
            ),
          )
        else
          for (final tr in trackers)
            _TrackerSummary(tracker: tr, title: widget.title),
      ],
    );
  }
}

/// Un tracker dans « Sur les trackers », dessiné comme un torrent des
/// Transferts : pastille d'état colorée, nom, ligne d'état, infos à icônes.
class _TrackerSummary extends ConsumerWidget {
  const _TrackerSummary({required this.tracker, required this.title});
  final Tracker tracker;
  final TmdbTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final results = ref.watch(wishSearchProvider((tracker, title)));
    final items = results.value ?? const <Release>[];
    final small = TextStyle(fontSize: 12, height: 1.3, color: c.muted);
    const mono = [FontFeature.tabularFigures()];

    Widget info(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: c.muted),
            const SizedBox(width: 4),
            Text(text, style: small.copyWith(fontFeatures: mono)),
          ]),
        );

    final Color color;
    final IconData icon;
    final String status;
    final details = <Widget>[];
    final tags = <Widget>[];
    if (results.isLoading) {
      color = c.info;
      icon = Icons.manage_search_rounded;
      status = 'Recherche…';
    } else if (results.hasError) {
      color = c.danger;
      icon = Icons.error_outline_rounded;
      status = '${results.error}';
    } else if (items.isEmpty) {
      color = c.muted;
      icon = Icons.remove_circle_outline_rounded;
      status = 'Rien pour l’instant';
    } else {
      final sum = summarizeReleases(items);
      color = c.success;
      icon = Icons.check_circle_rounded;
      status = '${items.length} sortie${items.length > 1 ? 's' : ''}';
      details.addAll([
        if (sum.bestQuality != null) info(Icons.hd_rounded, sum.bestQuality!),
        if (sum.languages.isNotEmpty)
          info(Icons.translate_rounded, sum.languages.take(3).join('/')),
        info(Icons.arrow_upward_rounded, '${sum.maxSeeders}'),
      ]);
      tags.addAll([
        if (sum.hdr) Tag('HDR', color: c.info),
        if (sum.atmos) Tag('Atmos', color: c.info),
        if (sum.freeleech > 0) Tag('FL ${sum.freeleech}', color: c.success),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
        child: InkWell(
          onTap: () => _openSearch(context, title, tracker),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: Row(children: [
              // Pastille d'état, comme celle d'un torrent.
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: results.isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2, color: color))
                    : Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(tracker.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, height: 1.3, fontWeight: FontWeight.w700)),
                    ),
                    for (final t in tags)
                      Padding(padding: const EdgeInsets.only(left: 4), child: t),
                  ]),
                  const SizedBox(height: 4),
                  // Une ligne, coupée à droite si besoin.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Row(children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(status,
                            maxLines: 1,
                            style: small.copyWith(
                                color: color, fontWeight: FontWeight.w700)),
                      ),
                      ...details,
                    ]),
                  ),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FrenchDatesBlock extends StatelessWidget {
  const _FrenchDatesBlock(
      {required this.title, required this.dates, required this.loading});
  final TmdbTitle title;
  final FrenchDates? dates;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = dates;
    final now = DateTime.now();
    Widget cell(IconData icon, String label, DateTime? d) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 14, color: c.muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: c.muted)),
              ),
            ]),
            Text(d == null ? '—' : _day(d),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: d != null && d.isAfter(now) ? c.accent : c.text)),
          ]),
        );

    return _InfoCard(
      icon: Icons.flag_rounded,
      title: 'Sorties en France',
      color: c.accent,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: loading && f == null
              ? Text('…', style: TextStyle(color: c.muted))
              : f == null || f.isEmpty
                  ? Text(
                      'Pas encore de date en France'
                      '${title.date == null ? '' : ' (sortie mondiale : ${_day(title.date!)})'}',
                      style: TextStyle(fontSize: 12.5, color: c.muted))
                  : Row(children: [
                      cell(Icons.theaters_outlined, 'Cinéma', f.cinema),
                      cell(Icons.ondemand_video_rounded, 'VOD', f.digital),
                      cell(Icons.album_outlined, 'DVD / Blu-ray', f.physical),
                    ]),
        ),
      ],
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit(this.icon, this.label, this.people);
  final IconData icon;
  final String label;
  final List<TmdbPerson> people;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: context.colors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text.rich(TextSpan(children: [
          TextSpan(
              text: '$label : ',
              style: TextStyle(fontSize: 12.5, color: context.colors.muted)),
          TextSpan(
              text: people.take(4).map((p) => p.name).join(', '),
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]))),
        ]),
      );
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person});
  final TmdbPerson person;

  static const _line = 1.3;

  /// Photo, puis nom et rôle sur deux lignes chacun au plus, d'après la
  /// taille de texte du système.
  static double height(BuildContext context) {
    final s = MediaQuery.textScalerOf(context);
    return 110 + 5 + (s.scale(11.5) + s.scale(11)) * _line * 2 + 4;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 88,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        person.photoUrl == null
            ? Container(
                width: 88,
                height: 110,
                decoration: BoxDecoration(
                    color: c.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.person_outline_rounded, color: c.muted),
              )
            : Poster(person.photoUrl, width: 88, height: 110, radius: 8),
        const SizedBox(height: 5),
        Text(person.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11.5, height: _line, fontWeight: FontWeight.w600)),
        if (person.role case final role? when role.isNotEmpty)
          Text(role,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: _line, color: c.muted)),
      ]),
    );
  }
}

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
                        Text(_dateLabel(t),
                            style: TextStyle(
                                fontSize: 12,
                                color: t.upcoming ? c.text : c.muted)),
                        if (t.rating case final r?)
                          Text.rich(ratingSpan(context, r, const TextStyle(fontSize: 12))),
                        if (wished) _OwnedTags(title: t),
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
                  onPressed: () => _openSearch(context, t),
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
          Text(_dateLabel(t),
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
