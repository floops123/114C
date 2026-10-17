import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/tmdb.dart';
import '../api/tracker.dart';
import '../core/format.dart';
import '../state/wishlist.dart';
import 'releases_page.dart';
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
      if (mounted) ref.read(wishlistProvider.notifier).refreshDates();
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
      body = ListView.builder(
        itemCount: wishes.length,
        itemBuilder: (_, i) => _TitleTile(title: wishes[i].title, wished: true),
      );
    }

    return Scaffold(
      body: Column(children: [
        PageHeader(
          title: 'Souhaits',
          subtitle: wishes.isEmpty
              ? null
              : Text('${wishes.length} dans la liste',
                  style: TextStyle(color: c.muted, fontSize: 12.5)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
        if (_query.isEmpty) ...[
          ChipRow<_Mode>(
            items: _Mode.values,
            selected: mode,
            label: (m) => switch (m) {
              _Mode.list => 'Ma liste (${wishes.length})',
              _Mode.discover => 'Découvrir',
            },
            onSelected: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 6),
        ],
        Divider(height: 1, color: c.border),
        Expanded(child: body),
      ]),
    );
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
            data: (titles) => titles.isEmpty
                ? const EmptyState(Icons.search_off_rounded, 'Aucun résultat.')
                : ListView.builder(
                    itemCount: titles.length,
                    itemBuilder: (_, i) => _TitleTile(title: titles[i]),
                  ),
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
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final feed in TmdbFeed.discover()) _FeedRow(feed: feed),
        for (final type in TmdbType.values) _GenreRow(type: type),
      ],
    );
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
            data: (items) => items.isEmpty
                ? Center(
                    child: Text('Rien pour l’instant.',
                        style: TextStyle(color: c.muted)))
                : _carousel(
                    items.length, (i) => _PosterCard(title: items[i])),
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
            ]),
          ),
          const SizedBox(height: 5),
          Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, height: _line, fontWeight: FontWeight.w600)),
          Text(t.year?.toString() ?? '—',
              maxLines: 1,
              style: TextStyle(fontSize: 11.5, height: _line, color: c.muted)),
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.feed.label)),
      body: Column(children: [
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
                    itemCount: _items.length,
                    itemBuilder: (_, i) =>
                        _PosterCard(title: _items[i], expand: true),
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
        (MediaQuery.sizeOf(context).width * 0.5).clamp(240.0, 460.0);

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
        child: Poster(t.posterUrl, width: 120, height: 180, radius: 10),
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
                  Poster(backdrop, radius: 0),
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
                  OutlinedButton.icon(
                    onPressed: () => _openSearch(context, t),
                    icon: const Icon(Icons.travel_explore_rounded),
                    label: const Text('Chercher sur les trackers'),
                  ),
                  if (d?.trailer case final url?)
                    OutlinedButton.icon(
                      onPressed: () =>
                          launchUrl(url, mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      label: const Text('Bande-annonce'),
                    ),
                ]),
                if (details.hasError) ...[
                  const SizedBox(height: 8),
                  ErrorBanner('${details.error}',
                      onRetry: () => ref.invalidate(tmdbDetailsProvider(t))),
                ],
                if (t.type == TmdbType.movie)
                  _FrenchDatesBlock(title: t, dates: d?.french,
                      loading: details.isLoading),
                _TrackersBlock(title: t),
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
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            Icon(Icons.dns_outlined, size: 15, color: c.muted),
            const SizedBox(width: 6),
            Text('Sur les trackers',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: c.muted)),
          ]),
        ),
        if (!_started)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _started = true),
                icon: const Icon(Icons.manage_search_rounded, size: 18),
                label: const Text('Vérifier la disponibilité'),
              ),
            ),
          )
        else
          for (final tr in trackers)
            _TrackerSummary(tracker: tr, title: widget.title),
        if (_started) const SizedBox(height: 4),
      ]),
    );
  }
}

class _TrackerSummary extends ConsumerWidget {
  const _TrackerSummary({required this.tracker, required this.title});
  final Tracker tracker;
  final TmdbTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final results = ref.watch(wishSearchProvider((tracker, title)));
    final items = results.value ?? const <Release>[];

    final Widget leading;
    final String detail;
    if (results.isLoading) {
      leading = const SizedBox.square(
          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2));
      detail = 'Recherche…';
    } else if (results.hasError) {
      leading = Icon(Icons.error_outline_rounded, size: 20, color: c.danger);
      detail = '${results.error}';
    } else if (items.isEmpty) {
      leading = Icon(Icons.remove_circle_outline_rounded, size: 20, color: c.muted);
      detail = 'Rien pour l’instant';
    } else {
      leading = Icon(Icons.check_circle_rounded, size: 20, color: c.success);
      final s = summarizeReleases(items);
      detail = [
        '${items.length} sortie${items.length > 1 ? 's' : ''}',
        if (s.bestQuality != null) 'jusqu’en ${s.bestQuality}',
        if (s.hdr) 'HDR',
        if (s.atmos) 'Atmos',
        if (s.languages.isNotEmpty) s.languages.take(3).join('/'),
        '▲ ${s.maxSeeders} max',
        if (s.freeleech > 0) '${s.freeleech} freeleech',
      ].join(' · ');
    }

    return InkWell(
      onTap: () => _openSearch(context, title, tracker),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          leading,
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: Text(tracker.label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.muted)),
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: c.muted),
        ]),
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

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.flag_outlined, size: 15, color: c.muted),
          const SizedBox(width: 6),
          Text('Sorties en France',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: c.muted)),
        ]),
        const SizedBox(height: 6),
        if (loading && f == null)
          Text('…', style: TextStyle(color: c.muted))
        else if (f == null || f.isEmpty)
          Text(
              'Pas encore de date en France'
              '${title.date == null ? '' : ' (sortie mondiale : ${_day(title.date!)})'}',
              style: TextStyle(fontSize: 12.5, color: c.muted))
        else
          Row(children: [
            cell(Icons.theaters_outlined, 'Cinéma', f.cinema),
            cell(Icons.ondemand_video_rounded, 'VOD', f.digital),
            cell(Icons.album_outlined, 'DVD / Blu-ray', f.physical),
          ]),
      ]),
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

    return InkWell(
      onTap: () => openTitle(context, t),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(children: [
          Poster(t.posterUrl, width: 50, height: 75, radius: 6),
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
            ascendingByDefault: (s) => s.ascendingByDefault,
            onChanged: ref.read(wishSortProvider.notifier).set,
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
        // Intertitres (groupes) et sorties à plat, pour une liste paresseuse.
        final rows = <Object>[
          for (final (header, group) in sortWish(items, sort, ascending)) ...[
            ?(header == null ? null : '$header (${group.length})'),
            ...group,
          ],
        ];
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) => switch (rows[i]) {
            final Release r => ReleaseRow(release: r),
            final header => _GroupHeader('$header'),
          },
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
          color: c.surfaceAlt,
          border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Text(text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }
}
