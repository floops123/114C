import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/c411.dart';
import '../core/format.dart';
import '../state/releases.dart';
import '../state/torrents.dart';
import 'release_detail_page.dart';
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
      final notifier = ref.read(releasesProvider.notifier);
      final filter = ref.read(releasesProvider).filter;
      if (filter.query != text.trim()) {
        notifier.setFilter(filter.copyWith(query: text.trim()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(c411Provider) != null;
    final state = ref.watch(releasesProvider);
    final notifier = ref.read(releasesProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sorties'),
        actions: [
          PopupMenuButton<String?>(
            tooltip: 'Trier',
            icon: const Icon(Icons.sort),
            initialValue: state.filter.sortBy,
            onSelected: (v) =>
                notifier.setFilter(state.filter.copyWith(sortBy: () => v)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: null, child: Text('Plus récents')),
              PopupMenuItem(value: 'seeders', child: Text('Plus de seeders')),
            ],
          ),
          IconButton(
            tooltip: 'Rafraîchir',
            icon: const Icon(Icons.refresh),
            onPressed: configured ? notifier.reload : null,
          ),
        ],
      ),
      body: !configured
          ? const EmptyState(Icons.key_outlined,
              'Ajoute ta clé API C411 dans les réglages pour voir les sorties.')
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: TextField(
                  controller: _search,
                  onChanged: _onSearch,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Rechercher',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              _CategoryBar(filter: state.filter),
              if (state.error != null)
                ErrorBanner(state.error!, onRetry: notifier.loadMore),
              Expanded(child: _ReleaseList(state: state)),
            ]),
    );
  }
}

class _CategoryBar extends ConsumerWidget {
  const _CategoryBar({required this.filter});
  final ReleaseFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final notifier = ref.read(releasesProvider.notifier);
    final current =
        categories.where((c) => c.id == filter.categoryId).firstOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Expanded(
          child: DropdownButton<int?>(
            isExpanded: true,
            value: current?.id,
            items: [
              const DropdownMenuItem(value: null, child: Text('Toutes catégories')),
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (id) => notifier.setFilter(filter.copyWith(
                categoryId: () => id, subcategoryId: () => null)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButton<int?>(
            isExpanded: true,
            value: filter.subcategoryId,
            items: [
              const DropdownMenuItem(value: null, child: Text('Tout')),
              for (final s in current?.subcategories ?? const <Subcategory>[])
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: current == null
                ? null
                : (id) => notifier
                    .setFilter(filter.copyWith(subcategoryId: () => id)),
          ),
        ),
      ]),
    );
  }
}

class _ReleaseList extends ConsumerWidget {
  const _ReleaseList({required this.state});
  final ReleasesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(releasesProvider.notifier);
    if (state.items.isEmpty && state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.items.isEmpty && state.error == null) {
      return const EmptyState(Icons.search_off, 'Aucun résultat');
    }
    return RefreshIndicator(
      onRefresh: notifier.reload,
      child: ListView.builder(
        itemExtent: 112,
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          // Chargement de la page suivante un peu avant d'atteindre le bas.
          if (i >= state.items.length - 10 && state.error == null) {
            Future.microtask(notifier.loadMore);
          }
          if (i >= state.items.length) {
            return const Center(child: CircularProgressIndicator());
          }
          return ReleaseTile(release: state.items[i]);
        },
      ),
    );
  }
}

class ReleaseTile extends ConsumerWidget {
  const ReleaseTile({super.key, required this.release});
  final Release release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = release;
    final inClient = ref.watch(
        torrentsProvider.select((s) => s.hashes.contains(r.infoHash)));
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReleaseDetailPage(release: r))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Poster(r.posterUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [r.title ?? r.name, if (r.year != null) '(${r.year})']
                      .join(' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                Text(r.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                const SizedBox(height: 4),
                Flexible(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Badge411(r.subcategory,
                          color: theme.colorScheme.tertiary),
                      if (r.resolution != null) Badge411(r.resolution!),
                      if (r.source != null) Badge411(r.source!),
                      if (r.languages.isNotEmpty)
                        Badge411(r.languages.take(2).join('/')),
                      if (r.isFreeleech)
                        const Badge411('FREELEECH', color: Colors.green),
                      if (r.isExclusive)
                        const Badge411('EXCLU', color: Colors.orange),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '${formatBytes(r.size)}  ·  ▲ ${r.seeders}  ▼ ${r.leechers}'
                  '  ·  ${formatAgo(r.createdAt)}',
                  style: muted,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: inClient ? 'Déjà dans Transmission' : 'Télécharger',
            icon: Icon(inClient ? Icons.check_circle : Icons.download),
            color: inClient ? Colors.green : null,
            onPressed:
                inClient ? null : () => sendToTransmission(context, ref, r),
          ),
        ]),
      ),
    );
  }
}
