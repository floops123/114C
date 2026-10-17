import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../core/format.dart';
import '../state/cross_seed.dart';
import '../state/revive.dart';
import '../state/torrents.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ordre d'affichage des résultats.
const _order = [
  ReviveStatus.available,
  ReviveStatus.downloading,
  ReviveStatus.seeding,
  ReviveStatus.searching,
  ReviveStatus.waiting,
  ReviveStatus.mismatch,
  ReviveStatus.error,
  ReviveStatus.noSeeders,
  ReviveStatus.notFound,
  ReviveStatus.present,
];

/// Sorties sans seeder d'un tracker, à récupérer sur d'autres puis à
/// repartager sur le premier.
class RevivePage extends ConsumerStatefulWidget {
  const RevivePage({super.key});

  @override
  ConsumerState<RevivePage> createState() => _RevivePageState();
}

class _RevivePageState extends ConsumerState<RevivePage> {
  /// Choix de l'utilisateur ; null : C411 (ou le premier tracker configuré)
  /// et tous les autres.
  Tracker? _deadOn;
  Set<Tracker>? _searchOn;
  int? _categoryId;
  int? _subcategoryId;
  final _limit = TextEditingController();

  /// null = tous les résultats.
  ReviveStatus? _filter;

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  /// Tracker des sorties mortes et trackers où chercher, parmi ceux configurés.
  (Tracker?, List<Tracker>) _direction(Iterable<Tracker> configured) {
    final deadOn = configured.contains(_deadOn)
        ? _deadOn
        : configured.contains(Tracker.c411)
            ? Tracker.c411
            : configured.firstOrNull;
    return (
      deadOn,
      [
        for (final t in configured)
          if (t != deadOn && (_searchOn?.contains(t) ?? true)) t,
      ],
    );
  }

  void _scan() {
    FocusScope.of(context).unfocus();
    setState(() => _filter = null);
    final (deadOn, searchOn) = _direction(ref.read(trackersProvider).keys);
    if (deadOn == null) return;
    final limit = int.tryParse(_limit.text.trim());
    ref.read(reviveProvider.notifier).scan(
          deadOn: deadOn,
          searchOn: searchOn,
          categoryId: _categoryId,
          subcategoryId: _subcategoryId,
          limit: limit != null && limit > 0 ? limit : null,
        );
  }

  Future<void> _addAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await ref.read(reviveProvider.notifier).addAll();
    messenger.showSnackBar(
        SnackBar(content: Text('$n torrent(s) envoyé(s) à Transmission')));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviveProvider);
    final notifier = ref.read(reviveProvider.notifier);
    final configured = ref.watch(trackersProvider).keys.toList();
    final (deadOn, searchOn) = _direction(configured);
    final categories = deadOn == null
        ? const AsyncValue<List<Category>>.data([])
        : ref.watch(trackerCategoriesProvider(deadOn));
    final idle = !state.running;
    final c = context.colors;
    final available = state.count(ReviveStatus.available);
    final total = state.items.length;

    final list = categories.value ?? const [];
    final names = {for (final cat in list) cat.id: cat.name};
    final current = list.where((cat) => cat.id == _categoryId).firstOrNull;

    final items = [
      for (final s in _order)
        for (final i in state.items)
          if (i.status == s && (_filter == null || _filter == s)) i,
    ];
    final present = {for (final i in state.items) i.status};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sans seeder'),
        actions: [
          if (state.running)
            TextButton.icon(
              onPressed: notifier.stop,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Arrêter'),
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Liste les sorties sans seeder d’un tracker et les cherche sur '
            'les autres (même nom, même taille). La copie la plus seedée se '
            'télécharge depuis son tracker ; une fois terminée, la sortie '
            'morte s’ajoute dans le même dossier et repart en partage '
            '(étiquette « ${CrossSeedNotifier.label} »).',
            style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
          ),
        ),
        const _Label('Sorties sans seeder sur'),
        ChipRow<Tracker>(
          items: configured,
          selected: deadOn ?? Tracker.c411,
          label: (t) => t.label,
          onSelected: (t) {
            if (!idle || t == deadOn) return;
            setState(() {
              // Le tracker quitté devient un tracker où chercher.
              _searchOn = {...searchOn, ?deadOn}..remove(t);
              _deadOn = t;
              _categoryId = _subcategoryId = null;
            });
          },
        ),
        const _Label('Chercher les copies sur'),
        SizedBox(
          height: 34,
          child: HorizontalScroller(
            builder: (controller) => ListView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final t in configured)
                  if (t != deadOn)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Center(
                        child: FilterChip(
                          label: Text(t.label),
                          selected: searchOn.contains(t),
                          onSelected: idle
                              ? (on) => setState(() => _searchOn = on
                                  ? {...searchOn, t}
                                  : ({...searchOn}..remove(t)))
                              : null,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
        const _Label('Catégorie'),
        if (categories.hasError)
          ErrorBanner(
              'Catégories ${deadOn?.label} indisponibles : ${categories.error}',
              onRetry: () => ref.invalidate(trackerCategoriesProvider))
        else ...[
          ChipRow<int?>(
            items: [null, ...list.map((cat) => cat.id)],
            selected: _categoryId,
            label: (id) => id == null ? 'Toutes catégories' : names[id]!,
            onSelected: state.running
                ? (_) {}
                : (id) => setState(() {
                      _categoryId = id;
                      _subcategoryId = null;
                    }),
          ),
          if (current != null && current.subcategories.isNotEmpty) ...[
            const SizedBox(height: 4),
            ChipRow<int?>(
              items: [null, ...current.subcategories.map((s) => s.id)],
              selected: _subcategoryId,
              label: (id) => id == null
                  ? 'Toutes'
                  : current.subcategories.firstWhere((s) => s.id == id).name,
              onSelected: state.running
                  ? (_) {}
                  : (id) => setState(() => _subcategoryId = id),
            ),
          ],
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(children: [
            SizedBox(
              width: 130,
              child: TextField(
                controller: _limit,
                enabled: !state.running,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Tous',
                  isDense: true,
                ),
                onSubmitted: (_) => _scan(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: idle && deadOn != null && searchOn.isNotEmpty
                    ? _scan
                    : null,
                icon: state.running
                    ? SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: c.onAccent))
                    : const Icon(Icons.manage_search_rounded, size: 18),
                label: Text(state.listing
                    ? 'Lecture ${deadOn?.label ?? ''}… $total'
                    : state.running
                        ? 'Recherche ${state.done} / $total'
                        : 'Rechercher'),
              ),
            ),
          ]),
        ),
        if (available > 0 && !state.running)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addAll,
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                label: Text('Tout télécharger ($available)'),
              ),
            ),
          ),
        if (state.running && !state.listing && total > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LinearProgressIndicator(
              value: state.done / total,
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        if (state.error != null) ErrorBanner(state.error!),
        if (state.items.isNotEmpty)
          ChipRow<ReviveStatus?>(
            items: [null, ..._order.where(present.contains)],
            selected: _filter,
            label: (s) => s == null
                ? 'Tous ($total)'
                : '${s.label} (${state.count(s)})',
            onSelected: (s) => setState(() => _filter = s),
          ),
        const SizedBox(height: 6),
        Divider(height: 1, color: c.border),
        Expanded(
          child: state.items.isEmpty
              ? EmptyState(
                  Icons.healing_rounded,
                  state.listing
                      ? 'Lecture des sorties sans seeder…'
                      : state.running
                          ? 'Recherche…'
                          : 'Choisis les trackers, une catégorie, et lance la '
                              'recherche des sorties sans seeder.',
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => _ItemTile(item: items[i]),
                ),
        ),
      ]),
    );
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item});
  final ReviveItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final (Color color, IconData icon) = switch (item.status) {
      ReviveStatus.available => (c.accent, Icons.download_rounded),
      ReviveStatus.downloading => (c.info, Icons.downloading_rounded),
      ReviveStatus.seeding => (c.success, Icons.check_circle_rounded),
      ReviveStatus.present => (c.success, Icons.check_rounded),
      ReviveStatus.searching => (c.info, Icons.manage_search_rounded),
      ReviveStatus.mismatch => (c.warning, Icons.difference_outlined),
      ReviveStatus.error => (c.danger, Icons.error_outline_rounded),
      _ => (c.muted, Icons.remove_rounded),
    };
    // Avancement du téléchargement de la copie.
    final progress = item.status == ReviveStatus.downloading
        ? ref.watch(torrentsProvider.select((s) => s.byId.values
            .where((t) => t.hash == item.hash)
            .firstOrNull
            ?.percentDone))
        : null;
    final candidate = item.candidate;
    final small = TextStyle(fontSize: 11.5, color: c.muted);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.release.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (item.release.subcategory.isNotEmpty)
                    Tag(item.release.subcategory, color: c.accent),
                  Text(item.status.label,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                  Text(formatBytes(item.release.size), style: small),
                  if (candidate != null)
                    Text('${candidate.tracker.label} : ${candidate.seeders} seeder(s)',
                        style: small),
                  if (progress != null)
                    Text('${(progress * 100).floor()} %', style: small),
                ],
              ),
              if (item.detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(item.detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: small),
                ),
            ],
          ),
        ),
        if (item.status == ReviveStatus.available)
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final error = await ref.read(reviveProvider.notifier).add(item);
              messenger.showSnackBar(SnackBar(
                  content: Text(
                      error ?? 'Envoyé à Transmission : ${item.release.name}')));
            },
            child: const Text('Télécharger'),
          ),
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(text,
            style: TextStyle(
                color: context.colors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600)),
      );
}
