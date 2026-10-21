import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../core/format.dart';
import '../state/cross_seed.dart';
import '../state/palliative.dart';
import '../state/revive.dart';
import '../state/torrents.dart';
import 'content_art.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ordre d'affichage des résultats de l'onglet « Sans seeder ».
const _reviveOrder = [
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

/// Ordre d'affichage des résultats de l'onglet « Soins palliatif ».
const _palliativeOrder = [
  PalliativeStatus.available,
  PalliativeStatus.uploading,
  PalliativeStatus.downloading,
  PalliativeStatus.seeding,
  PalliativeStatus.searching,
  PalliativeStatus.waiting,
  PalliativeStatus.mismatch,
  PalliativeStatus.error,
  PalliativeStatus.noSeeders,
  PalliativeStatus.notFound,
  PalliativeStatus.noMatch,
  PalliativeStatus.present,
];

/// Page « Sans seeder / Soins palliatif » : retrouve des torrents orphelins
/// sur d'autres trackers.
class RevivePage extends StatelessWidget {
  const RevivePage({super.key, this.palliative = false});

  /// Ouvrir directement l'onglet « Soins palliatif ».
  final bool palliative;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: palliative ? 1 : 0,
      child: Builder(builder: (context) {
        final controller = DefaultTabController.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Sans seeder'),
            bottom: TabBar(
              controller: controller,
              // Deux onglets fixes qui se partagent la largeur ; sans
              // `tabAlignment: fill`, Flutter récent utilise
              // `TabAlignment.start` qui n'est valide que pour un
              // `TabBar` scrollable.
              tabAlignment: TabAlignment.fill,
              tabs: const [
                Tab(text: 'Sans seeder'),
                Tab(text: 'Soins palliatif'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              _ReviveTab(),
              _PalliativeTab(),
            ],
          ),
        );
      }),
    );
  }
}

/// Onglet « Sans seeder » : on choisit un tracker, on liste ses sorties sans
/// seeder, on les cherche sur les autres.
class _ReviveTab extends ConsumerStatefulWidget {
  const _ReviveTab();

  @override
  ConsumerState<_ReviveTab> createState() => _ReviveTabState();
}

class _ReviveTabState extends ConsumerState<_ReviveTab> {
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
      for (final s in _reviveOrder)
        for (final i in state.items)
          if (i.status == s && (_filter == null || _filter == s)) i,
    ];
    final present = {for (final i in state.items) i.status};

    return Column(children: [
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
          icon: (id) => categoryIcon(id == null ? null : names[id]),
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
            icon: (id) => id == null
                ? null
                : categoryIcon(
                    current.subcategories.firstWhere((s) => s.id == id).name),
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
          items: [null, ..._reviveOrder.where(present.contains)],
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
                itemBuilder: (_, i) => _ReviveTile(item: items[i]),
              ),
      ),
    ]);
  }
}

/// Tuile d'une sortie sans seeder : icône d'état, nom, sous-catégorie, taille,
/// tracker de la copie, bouton de téléchargement.
class _ReviveTile extends ConsumerWidget {
  const _ReviveTile({required this.item});
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

/// Onglet « Soins palliatif » : on lit la liste palliative de C411 (via le
/// cookie de session) et on cherche chaque sortie sur les trackers non-C411
/// configurés.
class _PalliativeTab extends ConsumerStatefulWidget {
  const _PalliativeTab();

  @override
  ConsumerState<_PalliativeTab> createState() => _PalliativeTabState();
}

/// Dossiers de l'ordinateur : version de bureau seulement.
final _desktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;

class _PalliativeTabState extends ConsumerState<_PalliativeTab> {
  Set<Tracker>? _searchOn;
  final _limit = TextEditingController();
  PalliativeStatus? _filter;

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  List<Tracker> _searchTrackers(Iterable<Tracker> configured) => [
        for (final t in configured)
          if (t != Tracker.c411 && (_searchOn?.contains(t) ?? true)) t,
      ];

  void _scan() {
    FocusScope.of(context).unfocus();
    setState(() => _filter = null);
    final limit = int.tryParse(_limit.text.trim());
    ref.read(palliativeProvider.notifier).scan(
        limit: limit != null && limit > 0 ? limit : null);
  }

  /// Un dossier de l'ordinateur (version de bureau seulement).
  Future<void> _scanFolder() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Chercher ici');
    if (dir == null || !mounted) return;
    setState(() => _filter = null);
    ref.read(palliativeProvider.notifier).scanFolder(dir);
  }

  void _scanClient() {
    setState(() => _filter = null);
    ref.read(palliativeProvider.notifier).scanClient();
  }

  Future<void> _addAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await ref.read(palliativeProvider.notifier).addAll();
    messenger.showSnackBar(
        SnackBar(content: Text('$n torrent(s) envoyé(s) à Transmission')));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(palliativeProvider);
    final configured = ref.watch(trackersProvider).keys.toList();
    final searchOn = _searchTrackers(configured);
    final idle = !state.running;
    final c = context.colors;
    final available = state.count(PalliativeStatus.available);
    final total = state.items.length;

    final items = [
      for (final s in _palliativeOrder)
        for (final i in state.items)
          if (i.status == s && (_filter == null || _filter == s)) i,
    ];
    final present = {for (final i in state.items) i.status};

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(
          'Liste les sorties palliatives de C411 (sans seeder depuis un '
          'certain temps) et les cherche sur les autres trackers configurés '
          '(même nom, même taille). La copie la plus seedée se télécharge '
          'depuis son tracker ; une fois terminée, la sortie C411 s’ajoute '
          'dans le même dossier et repart en partage '
          '(étiquette « ${CrossSeedNotifier.label} »). '
          '${_desktop ? '« Sur mon ordinateur » cherche les fichiers dans un dossier : '
              'trouvés, ils partent sur le serveur et la sortie C411 y est ajoutée. ' : ''}'
          '« Dans Transmission » cherche les mêmes fichiers dans tes torrents '
          'et ajoute la sortie C411 en cross-seed.',
          style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
        ),
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
                if (t != Tracker.c411)
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
              onPressed: idle && searchOn.isNotEmpty ? _scan : null,
              icon: state.running
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: c.onAccent))
                  : const Icon(Icons.medical_services_rounded, size: 18),
              label: Text(state.listing
                  ? 'Lecture C411… $total'
                  : state.running
                      ? 'Recherche ${state.done} / $total'
                      : 'Rechercher'),
            ),
          ),
        ]),
      ),
      // Sans tracker : les fichiers déjà là, sur l'ordinateur ou dans
      // Transmission.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          if (_desktop)
            OutlinedButton.icon(
              onPressed: idle ? _scanFolder : null,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('Sur mon ordinateur'),
            ),
          OutlinedButton.icon(
            onPressed: idle ? _scanClient : null,
            icon: const Icon(Icons.join_inner_rounded, size: 18),
            label: const Text('Dans Transmission'),
          ),
        ]),
      ),
      if (state.step != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(state.step!, style: TextStyle(color: c.muted, fontSize: 12.5)),
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
        ChipRow<PalliativeStatus?>(
          items: [null, ..._palliativeOrder.where(present.contains)],
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
                Icons.medical_services_rounded,
                state.listing
                    ? 'Lecture de la liste palliative C411…'
                    : state.running
                        ? 'Recherche…'
                        : 'Choisis les trackers où chercher les palliatifs, '
                            'un nombre, et lance la recherche.',
              )
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => _PalliativeTile(item: items[i]),
              ),
      ),
    ]);
  }
}

/// Tuile d'une sortie palliative : icône d'état, nom, sous-catégorie, état,
/// taille, et la liste des copies trouvées (une par tracker). Bouton de
/// téléchargement pour la copie la plus seedée.
class _PalliativeTile extends ConsumerWidget {
  const _PalliativeTile({required this.item});
  final PalliativeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final (Color color, IconData icon) = switch (item.status) {
      PalliativeStatus.available => (c.accent, Icons.download_rounded),
      PalliativeStatus.downloading => (c.info, Icons.downloading_rounded),
      PalliativeStatus.uploading => (c.info, Icons.upload_rounded),
      PalliativeStatus.seeding => (c.success, Icons.check_circle_rounded),
      PalliativeStatus.present => (c.success, Icons.check_rounded),
      PalliativeStatus.searching => (c.info, Icons.manage_search_rounded),
      PalliativeStatus.mismatch => (c.warning, Icons.difference_outlined),
      PalliativeStatus.error => (c.danger, Icons.error_outline_rounded),
      _ => (c.muted, Icons.remove_rounded),
    };
    final progress = item.status == PalliativeStatus.downloading
        ? ref.watch(torrentsProvider.select((s) => s.byId.values
            .where((t) => t.hash == item.hash)
            .firstOrNull
            ?.percentDone))
        : null;
    final small = TextStyle(fontSize: 11.5, color: c.muted);

    // Copies trouvées, regroupées par tracker (au cas où un même tracker
    // renverrait plusieurs fois la même sortie).
    final byTracker = <Tracker, List<Release>>{};
    for (final r in item.candidates) {
      byTracker.putIfAbsent(r.tracker, () => []).add(r);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: color),
        ),
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
                  if (progress != null)
                    Text('${(progress * 100).floor()} %', style: small),
                ],
              ),
              if (byTracker.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final MapEntry(key: tracker, value: copies)
                    in byTracker.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Row(children: [
                      Icon(Icons.subdirectory_arrow_right,
                          size: 12, color: c.muted),
                      const SizedBox(width: 4),
                      Text(
                        '${tracker.label} : ',
                        style: small,
                      ),
                      Text(
                        copies
                            .map((c) => '${c.seeders} seeder(s)')
                            .join(' / '),
                        style: small.copyWith(
                            color: copies.any((c) => c.seeders > 0)
                                ? c.success
                                : c.muted,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
              ],
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
        if (item.status == PalliativeStatus.available && item.best != null)
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final error = await ref
                  .read(palliativeProvider.notifier)
                  .add(item);
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