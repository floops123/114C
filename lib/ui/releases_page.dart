import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../core/format.dart';
import '../core/preferences.dart';
import '../state/releases.dart';
import 'release_detail_page.dart';
import 'send_button.dart';
import 'theme.dart';
import 'widgets.dart';

class ReleasesPage extends ConsumerStatefulWidget {
  const ReleasesPage({super.key});

  @override
  ConsumerState<ReleasesPage> createState() => _ReleasesPageState();
}

class _ReleasesPageState extends ConsumerState<ReleasesPage> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final filter = ref.read(releasesProvider).filter;
      if (filter.query != text.trim()) {
        ref
            .read(releasesProvider.notifier)
            .setFilter(filter.copyWith(query: text.trim()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(currentTrackerApiProvider);
    final configured = api != null;
    final trackers = ref.watch(trackersProvider).keys.toList();
    final selected = ref.watch(selectedTrackerProvider);
    final state = ref.watch(releasesProvider);
    final notifier = ref.read(releasesProvider.notifier);
    final grid = ref.watch(uiPrefsProvider.select((p) => p.releasesGrid));
    final c = context.colors;

    return Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Sorties',
            subtitle: state.total > 0
                ? Text(
                    '${state.total} torrents',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : null,
            actions: [
              IconButton(
                tooltip: grid ? 'Affichage liste' : 'Affichage grille',
                icon: Icon(
                  grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                ),
                onPressed: () =>
                    ref.read(uiPrefsProvider.notifier).setReleasesGrid(!grid),
              ),
              if (api != null)
                SortMenu<ReleaseSort>(
                  options: api.sorts,
                  selected: state.filter.sort,
                  ascending: state.filter.ascending,
                  label: (s) => s.label,
                  ascendingByDefault: (s) => s.ascendingByDefault,
                  note: api.serverSorts.isEmpty
                      ? 'Tri des résultats déjà chargés'
                      : null,
                  onChanged: notifier.setSort,
                ),
              IconButton(
                tooltip: 'Rafraîchir',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: configured ? notifier.reload : null,
              ),
            ],
          ),
          if (!configured)
            const Expanded(
              child: EmptyState(
                Icons.key_outlined,
                'Ajoute la clé API d’un tracker dans les réglages\npour voir les dernières sorties.',
              ),
            )
          else ...[
            if (trackers.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<Tracker>(
                    showSelectedIcon: false,
                    segments: [
                      for (final t in trackers)
                        ButtonSegment(value: t, label: Text(t.label)),
                    ],
                    selected: {?selected},
                    onSelectionChanged: (s) {
                      _search.clear();
                      ref
                          .read(selectedTrackerProvider.notifier)
                          .select(s.first);
                    },
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (v) {
                  setState(() {}); // affiche / masque le bouton d'effacement
                  _onSearch(v);
                },
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: 'Rechercher un titre',
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _search.clear();
                            _onSearch('');
                            setState(() {});
                          },
                        ),
                ),
              ),
            ),
            _CategoryChips(filter: state.filter),
            if (state.error != null)
              ErrorBanner(state.error!, onRetry: notifier.loadMore),
            Divider(height: 1, color: c.border),
            Expanded(
              child: _ReleaseList(state: state, grid: grid),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({required this.filter});
  final ReleaseFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final notifier = ref.read(releasesProvider.notifier);
    final current = categories
        .where((c) => c.id == filter.categoryId)
        .firstOrNull;
    final names = {for (final c in categories) c.id: c.name};

    return Column(
      children: [
        ChipRow<int?>(
          items: [null, ...categories.map((c) => c.id)],
          selected: filter.categoryId,
          label: (id) => id == null ? 'Tout' : names[id]!,
          onSelected: (id) => notifier.setFilter(
            filter.copyWith(categoryId: () => id, subcategoryId: () => null),
          ),
        ),
        if (current != null && current.subcategories.isNotEmpty) ...[
          const SizedBox(height: 4),
          ChipRow<int?>(
            items: [null, ...current.subcategories.map((s) => s.id)],
            selected: filter.subcategoryId,
            label: (id) => id == null
                ? 'Toutes'
                : current.subcategories.firstWhere((s) => s.id == id).name,
            onSelected: (id) =>
                notifier.setFilter(filter.copyWith(subcategoryId: () => id)),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ReleaseList extends ConsumerWidget {
  const _ReleaseList({required this.state, required this.grid});
  final ReleasesState state;
  final bool grid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(releasesProvider.notifier);
    if (state.items.isEmpty && state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.items.isEmpty && state.error == null) {
      return const EmptyState(Icons.search_off_rounded, 'Aucun résultat');
    }

    // Tri local quand le tracker ne sait pas trier (Torznab).
    final api = ref.watch(currentTrackerApiProvider);
    final f = state.filter;
    final items = api == null || api.serverSorts.contains(f.sort)
        ? state.items
        : (List.of(state.items)..sort(
            (a, b) => f.ascending ? f.sort.compare(a, b) : f.sort.compare(b, a),
          ));

    final count = items.length + (state.hasMore ? 1 : 0);
    Widget item(BuildContext context, int i) {
      // Chargement de la page suivante un peu avant d'atteindre le bas.
      if (i >= items.length - 12 && state.error == null) {
        Future.microtask(notifier.loadMore);
      }
      if (i >= items.length) {
        return const Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      final r = items[i];
      return grid ? ReleaseCard(release: r) : ReleaseRow(release: r);
    }

    return RefreshIndicator(
      onRefresh: notifier.reload,
      child: grid
          ? GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              // Téléphone : 3 colonnes ; au-delà, des cartes de 170 px au plus.
              gridDelegate: MediaQuery.sizeOf(context).width < 600
                  ? const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.52,
                    )
                  : const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 170,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.55,
                    ),
              itemCount: count,
              itemBuilder: item,
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemExtent: ReleaseRow.extent(context),
              itemCount: count,
              itemBuilder: item,
            ),
    );
  }
}

void _openDetail(BuildContext context, Release r) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ReleaseDetailPage(release: r)));

String _displayTitle(Release r) => r.title ?? r.name;

/// Carte « affiche » pour la vue grille.
class ReleaseCard extends StatelessWidget {
  const ReleaseCard({super.key, required this.release});
  final Release release;

  @override
  Widget build(BuildContext context) {
    final r = release;
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openDetail(context, r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Poster(r.posterUrl, radius: 10),
                Positioned(
                  left: 6,
                  top: 6,
                  right: 6,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (r.resolution != null) Tag(r.resolution!, solid: true),
                      if (r.isFreeleech)
                        Tag('FL', solid: true, color: c.success),
                      if (r.isExclusive)
                        Tag('EXCLU', solid: true, color: c.info),
                    ],
                  ),
                ),
                Positioned(right: 6, bottom: 6, child: SendButton(release: r)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _displayTitle(r),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (r.year != null) '${r.year}',
              formatBytes(r.size),
              '▲ ${r.seeders}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: c.muted),
          ),
        ],
      ),
    );
  }
}

/// HDR d'une sortie (« DV · HDR10+ »), ou null en SDR / inconnu.
String? hdrLabel(Release r) {
  final f = r.hdrFormat?.trim();
  if (f == null || f.isEmpty || f.toUpperCase() == 'SDR') return null;
  return f.split('.').join(' · ');
}

/// Ligne compacte pour la vue liste.
class ReleaseRow extends StatelessWidget {
  const ReleaseRow({super.key, required this.release});
  final Release release;

  /// Hauteur de ligne : fixe pour la fluidité du défilement, mais calculée
  /// d'après la taille de police du système (texte agrandi sur Android).
  /// Textes : titre 13,5, nom 12, étiquettes 10,5 (+ 4 de marge), infos 12 ;
  /// interligne 1,25 (1,3 pour les étiquettes) ; espacements 10 ; marges 12.
  static double extent(BuildContext context) {
    final s = MediaQuery.textScalerOf(context).scale(100) / 100;
    return 12 + math.max(75, (13.5 + 12 + 12) * 1.25 * s + 10.5 * 1.3 * s + 16);
  }

  static const _line = 1.25;

  @override
  Widget build(BuildContext context) {
    final r = release;
    final c = context.colors;
    return InkWell(
      onTap: () => _openDetail(context, r),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Poster(r.posterUrl, width: 50, height: 75, radius: 6),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    [
                      _displayTitle(r),
                      if (r.year != null) '(${r.year})',
                    ].join(' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: _line,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: _line,
                      color: c.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Une seule ligne d'étiquettes, coupée à droite si besoin
                  // (un retour à la ligne ferait déborder la ligne de liste).
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Row(
                      spacing: 4,
                      children: [
                        Tag(r.subcategory, color: c.accent),
                        if (r.resolution != null) Tag(r.resolution!),
                        if (r.source != null) Tag(r.source!),
                        if (hdrLabel(r) case final hdr?) Tag(hdr, color: c.info),
                        if (r.languages.isNotEmpty)
                          Tag(r.languages.take(2).join('/')),
                        if (r.audioCodec != null)
                          Tag([r.audioCodec!, ?r.audioChannels].join(' ')),
                        if (r.isFreeleech) Tag('FREELEECH', color: c.success),
                        if (r.isExclusive) Tag('EXCLU', color: c.info),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatBytes(r.size)}  ·  ▲ ${r.seeders}  ▼ ${r.leechers}'
                    '  ·  ${formatAgo(r.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: _line,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SendButton(release: r),
          ],
        ),
      ),
    );
  }
}
