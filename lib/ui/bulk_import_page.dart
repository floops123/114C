import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../core/format.dart';
import '../state/bulk_import.dart';
import '../state/palliative.dart';
import 'quota_notice.dart';
import 'release_detail_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Import en masse : on choisit un tracker et ses catégories, on cadre les
/// résultats (taille, seeders, leechers), on coche ce qui convient, et on
/// envoie tout à Transmission d'un coup.
class BulkImportPage extends ConsumerStatefulWidget {
  const BulkImportPage({super.key});

  @override
  ConsumerState<BulkImportPage> createState() => _BulkImportPageState();
}

class _BulkImportPageState extends ConsumerState<BulkImportPage> {
  /// Raccourcis de taille max (le cas d'usage premier : les petits torrents).
  static const _sizePresets = ['50 Mo', '200 Mo', '500 Mo', '1 Go', '4 Go'];

  final _name = TextEditingController();
  final _sizeMin = TextEditingController();
  final _sizeMax = TextEditingController();
  final _seedMin = TextEditingController();
  final _seedMax = TextEditingController();
  final _leechMin = TextEditingController();
  final _leechMax = TextEditingController();
  final _invalid = <TextEditingController>{};

  /// Petit écran : filtres dépliés (repliés après une recherche).
  bool _filtersOpen = true;

  @override
  void dispose() {
    for (final t in [
      _name,
      _sizeMin,
      _sizeMax,
      _seedMin,
      _seedMax,
      _leechMin,
      _leechMax,
    ]) {
      t.dispose();
    }
    super.dispose();
  }

  /// Traduit les champs en `BulkCriteria`. Un champ illisible est ignoré
  /// (et coloré rouge), pour ne pas casser une recherche déjà en cours.
  BulkCriteria _criteria(BulkCriteria base) {
    int? bytes(TextEditingController f, int? current) {
      if (f.text.trim().isEmpty) {
        _invalid.remove(f);
        return null;
      }
      final v = parseBytes(f.text);
      if (v == null) {
        _invalid.add(f);
        return current;
      }
      _invalid.remove(f);
      return v;
    }

    int? int2(TextEditingController f, int? current) {
      if (f.text.trim().isEmpty) {
        _invalid.remove(f);
        return null;
      }
      final v = int.tryParse(f.text.trim());
      if (v == null) {
        _invalid.add(f);
        return current;
      }
      _invalid.remove(f);
      return v;
    }

    return base.copyWith(
      name: _name.text.trim(),
      sizeMin: bytes(_sizeMin, base.sizeMin),
      sizeMax: bytes(_sizeMax, base.sizeMax),
      seedersMin: int2(_seedMin, base.seedersMin),
      seedersMax: int2(_seedMax, base.seedersMax),
      leechersMin: int2(_leechMin, base.leechersMin),
      leechersMax: int2(_leechMax, base.leechersMax),
    );
  }

  void _search() {
    FocusScope.of(context).unfocus();
    ref
        .read(bulkImportProvider.notifier)
        .update(_criteria(ref.read(bulkImportProvider).criteria));
    ref.read(bulkImportProvider.notifier).search();
    setState(() => _filtersOpen = false);
  }

  /// Remet tous les champs à zéro et vide la sélection côté notifier.
  void _clear() {
    FocusScope.of(context).unfocus();
    for (final c in [
      _name,
      _sizeMin,
      _sizeMax,
      _seedMin,
      _seedMax,
      _leechMin,
      _leechMax,
    ]) {
      c.clear();
    }
    _invalid.clear();
    ref.read(bulkImportProvider.notifier).update(const BulkCriteria());
    ref.read(bulkImportProvider.notifier).clear();
    setState(() {});
  }

  /// Applique les bornes à l'affichage (sans réinterroger les trackers).
  void _apply() {
    FocusScope.of(context).unfocus();
    final notifier = ref.read(bulkImportProvider.notifier);
    notifier.update(_criteria(ref.read(bulkImportProvider).criteria));
    notifier.refilter();
    setState(() {}); // Pour repeindre les champs invalides en rouge.
  }

  /// Raccourci de taille max : remplit le champ (vide : pas de maximum) et
  /// l'applique aux résultats déjà là.
  void _presetMax(String? size) {
    _sizeMax.text = size ?? '';
    _apply();
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(bulkImportProvider.notifier);
    final state = ref.read(bulkImportProvider);
    final n = state.selected.length;
    if (n == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Envoyer $n torrent${n > 1 ? 's' : ''} ?'),
        content: Text(
          'Ils seront ajoutés à Transmission avec leurs dossiers d’origine, '
          'un par un. Les échecs restent affichés ligne par ligne.'
          '${state.criteria.tracker != Tracker.c411
              ? ''
              : ref.read(c411SiteApiProvider) != null
              ? '\n\nC411 : téléchargés avec ton cookie de session.'
              : '\n\nC411 : téléchargés avec ta clé API (pas de cookie de session dans les Réglages).'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final added = await notifier.send();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$added torrent${added > 1 ? 's' : ''} envoyé'
          '${added > 1 ? 's' : ''} à Transmission',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bulkImportProvider);
    final notifier = ref.read(bulkImportProvider.notifier);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final filters = _Filters(
      state: state,
      trackers: ref.watch(trackersProvider).keys.toList(),
      name: _name,
      sizeMin: _sizeMin,
      sizeMax: _sizeMax,
      seedMin: _seedMin,
      seedMax: _seedMax,
      leechMin: _leechMin,
      leechMax: _leechMax,
      invalid: _invalid.toSet(),
      presets: _sizePresets,
      onPreset: _presetMax,
      onApply: _apply,
      onSearch: _search,
      onClear: _clear,
      onTracker: notifier.selectTracker,
      onCategories: (next) =>
          notifier.update(state.criteria.copyWith(categories: next)),
      onOrder: (o) {
        notifier.update(state.criteria.copyWith(order: o));
        notifier.refilter();
      },
    );
    final results = _Results(
      state: state,
      onSearch: _search,
      onClear: _clear,
      onSend: _send,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Import en masse')),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 380,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 0, 16),
                    child: Panel(radius: 16, child: filters),
                  ),
                ),
                Expanded(child: results),
              ],
            )
          // Petit écran : avant toute recherche, les filtres prennent toute
          // la hauteur ; ensuite, repliés en un résumé (ou ouverts sur une
          // partie de l'écran) au-dessus des résultats.
          : !state.searched
          ? Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Panel(
                radius: 16,
                child: Align(alignment: Alignment.topCenter, child: filters),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Panel(
                    radius: 16,
                    child: _filtersOpen
                        ? ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.sizeOf(context).height * 0.62,
                            ),
                            child: filters,
                          )
                        : _FiltersSummary(
                            state: state,
                            onOpen: () => setState(() => _filtersOpen = true),
                          ),
                  ),
                ),
                Expanded(child: results),
              ],
            ),
    );
  }
}

/// Taille sans décimales inutiles : « 50 Mo » plutôt que « 50,0 Mo ».
String _size(int bytes) =>
    formatBytes(bytes).replaceFirst(RegExp(r',0+ '), ' ');

/// Petit intitulé de section.
class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                color: c.muted,
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Les filtres, de haut en bas : tracker, taille (le cas d'usage premier),
/// catégories, nom, ordre, puis le reste ; « Rechercher » reste visible en
/// bas.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.state,
    required this.trackers,
    required this.name,
    required this.sizeMin,
    required this.sizeMax,
    required this.seedMin,
    required this.seedMax,
    required this.leechMin,
    required this.leechMax,
    required this.invalid,
    required this.presets,
    required this.onPreset,
    required this.onApply,
    required this.onSearch,
    required this.onClear,
    required this.onTracker,
    required this.onCategories,
    required this.onOrder,
  });

  final BulkState state;
  final List<Tracker> trackers;
  final TextEditingController name,
      sizeMin,
      sizeMax,
      seedMin,
      seedMax,
      leechMin,
      leechMax;
  final Set<TextEditingController> invalid;
  final List<String> presets;
  final ValueChanged<String?> onPreset;
  final VoidCallback onApply, onSearch, onClear;
  final ValueChanged<Tracker> onTracker;
  final ValueChanged<Set<CategoryRef>> onCategories;
  final ValueChanged<BulkOrder> onOrder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final criteria = state.criteria;
    final max = criteria.sizeMax;
    // Raccourci allumé : celui qui correspond à la taille max saisie.
    String? activePreset;
    for (final p in presets) {
      if (parseBytes(p) == max) activePreset = p;
    }
    final custom = max != null && activePreset == null;
    final extra = [
      seedMin,
      seedMax,
      leechMin,
      leechMax,
    ].where((f) => f.text.trim().isNotEmpty).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              const _Label('Tracker'),
              if (trackers.isEmpty)
                Text(
                  'Aucun tracker configuré : renseigne une clé dans les '
                  'Réglages.',
                  style: TextStyle(color: c.muted, fontSize: 12),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in trackers)
                      ChoiceChip(
                        label: Text(t.label),
                        selected: t == criteria.tracker,
                        onSelected: (_) => onTracker(t),
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              const _Label('Taille'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Toutes'),
                    selected: max == null,
                    onSelected: (_) => onPreset(null),
                  ),
                  for (final p in presets)
                    ChoiceChip(
                      label: Text('≤ $p'),
                      selected: p == activePreset,
                      onSelected: (_) => onPreset(p),
                    ),
                  if (custom)
                    ChoiceChip(
                      label: Text('≤ ${_size(max)}'),
                      selected: true,
                      onSelected: (_) {},
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _BoundField(
                      controller: sizeMin,
                      label: 'Min',
                      hint: 'ex. 100 Mo',
                      invalid: invalid.contains(sizeMin),
                      onSubmitted: onApply,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BoundField(
                      controller: sizeMax,
                      label: 'Max',
                      hint: 'ex. 700 Mo',
                      invalid: invalid.contains(sizeMax),
                      onSubmitted: onApply,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _CategoryTree(
                categories: state.categories,
                loading: state.loadingCategories,
                selected: criteria.categories,
                onChanged: onCategories,
              ),
              const SizedBox(height: 20),
              const _Label('Nom'),
              TextField(
                controller: name,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSearch(),
                decoration: const InputDecoration(
                  hintText: 'Facultatif : tout ce qui sort, sinon',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 20),
              const _Label('Ordre'),
              SegmentedButton<BulkOrder>(
                showSelectedIcon: false,
                segments: [
                  for (final o in BulkOrder.values)
                    ButtonSegment(value: o, label: Text(o.label)),
                ],
                selected: {criteria.order},
                onSelectionChanged: (s) => onOrder(s.first),
              ),
              const SizedBox(height: 12),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  initiallyExpanded: extra > 0,
                  title: Text(
                    extra > 0 ? 'Plus de filtres ($extra)' : 'Plus de filtres',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Seeders, leechers',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _BoundField(
                            controller: seedMin,
                            label: 'Seeders min',
                            hint: '0',
                            digits: true,
                            invalid: invalid.contains(seedMin),
                            onSubmitted: onApply,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _BoundField(
                            controller: seedMax,
                            label: 'Seeders max',
                            hint: '∞',
                            digits: true,
                            invalid: invalid.contains(seedMax),
                            onSubmitted: onApply,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _BoundField(
                            controller: leechMin,
                            label: 'Leechers min',
                            hint: '0',
                            digits: true,
                            invalid: invalid.contains(leechMin),
                            onSubmitted: onApply,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _BoundField(
                            controller: leechMax,
                            label: 'Leechers max',
                            hint: '∞',
                            digits: true,
                            invalid: invalid.contains(leechMax),
                            onSubmitted: onApply,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Toujours visible, sous les filtres.
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: state.loading || criteria.tracker == null
                        ? null
                        : onSearch,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: Text(state.searched ? 'Relancer' : 'Rechercher'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onClear,
                  child: const Text('Réinitialiser'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Filtres repliés (petit écran, après une recherche) : une ligne qui les
/// résume, touchée pour les rouvrir.
class _FiltersSummary extends StatelessWidget {
  const _FiltersSummary({required this.state, required this.onOpen});
  final BulkState state;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = state.criteria;
    final parts = [
      ?k.tracker?.label,
      if (k.sizeMin != null) '≥ ${_size(k.sizeMin!)}',
      if (k.sizeMax != null) '≤ ${_size(k.sizeMax!)}',
      if (k.categories.length == 1)
        categoryLabel(state.categories, k.categories.single)
      else if (k.categories.isNotEmpty)
        '${k.categories.length} catégories',
      if (k.name.isNotEmpty) '« ${k.name} »',
      k.order.label,
    ];
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, size: 18, color: c.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                parts.join('  ·  '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(onPressed: onOpen, child: const Text('Modifier')),
          ],
        ),
      ),
    );
  }
}

/// Catégories du tracker en arbre replié : une ligne par catégorie (case
/// à trois états : entière, en partie, pas du tout), ses sous-catégories
/// en puces quand on la déplie. Aucune cochée = toutes. Un champ filtre les
/// noms quand la liste est longue.
class _CategoryTree extends StatefulWidget {
  const _CategoryTree({
    required this.categories,
    required this.loading,
    required this.selected,
    required this.onChanged,
  });
  final List<Category> categories;
  final bool loading;
  final Set<CategoryRef> selected;
  final ValueChanged<Set<CategoryRef>> onChanged;

  @override
  State<_CategoryTree> createState() => _CategoryTreeState();
}

class _CategoryTreeState extends State<_CategoryTree> {
  final _open = <int>{};
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  void _toggleParent(Category cat) {
    final whole = (category: cat.id, subcategory: null);
    final mine = {
      for (final r in widget.selected)
        if (r.category == cat.id) r,
    };
    // Entière ou en partie : on la retire ; sinon on la prend entière.
    widget.onChanged(
      mine.isEmpty
          ? {...widget.selected, whole}
          : widget.selected.difference(mine),
    );
  }

  void _toggleSub(Category cat, Subcategory sub) {
    final whole = (category: cat.id, subcategory: null);
    final ref = (category: cat.id, subcategory: sub.id);
    final next = {...widget.selected}..remove(whole);
    widget.selected.contains(ref) ? next.remove(ref) : next.add(ref);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(color: c.muted, fontSize: 12);
    final cats = widget.categories;
    final selected = widget.selected;
    final query = _filter.text.trim().toLowerCase();
    bool hit(String s) => query.isNotEmpty && s.toLowerCase().contains(query);

    final label = _Label(
      'Catégories',
      trailing: selected.isEmpty
          ? Text('Toutes', style: small)
          : InkWell(
              onTap: () => widget.onChanged(const {}),
              child: Text(
                '${selected.length} · Tout effacer',
                style: TextStyle(
                  color: c.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
    );

    if (widget.loading && cats.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          Row(
            children: [
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text('Chargement des catégories…', style: small),
            ],
          ),
        ],
      );
    }
    if (cats.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          Text(
            'Ce tracker ne propose pas de catégories : recherche sur tout.',
            style: small,
          ),
        ],
      );
    }

    final total = cats.fold(0, (n, k) => n + 1 + k.subcategories.length);
    final shown = [
      for (final cat in cats)
        if (query.isEmpty ||
            hit(cat.name) ||
            cat.subcategories.any((s) => hit(s.name)))
          cat,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label,
        if (total > 15) ...[
          TextField(
            controller: _filter,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Filtrer les catégories',
              prefixIcon: const Icon(Icons.filter_list_rounded, size: 18),
              isDense: true,
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(_filter.clear),
                    ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              for (final (i, cat) in shown.indexed) ...[
                if (i > 0) Divider(height: 1, color: c.border),
                _parentRow(context, cat, query.isNotEmpty),
              ],
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Aucune catégorie ne correspond', style: small),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _parentRow(BuildContext context, Category cat, bool filtering) {
    final c = context.colors;
    final selected = widget.selected;
    final whole = selected.contains((category: cat.id, subcategory: null));
    final subs = selected
        .where((r) => r.category == cat.id && r.subcategory != null)
        .length;
    final open = filtering || _open.contains(cat.id);
    final hasSubs = cat.subcategories.isNotEmpty;
    final query = _filter.text.trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: hasSubs
              ? () => setState(
                  () => _open.contains(cat.id)
                      ? _open.remove(cat.id)
                      : _open.add(cat.id),
                )
              : () => _toggleParent(cat),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Checkbox(
                  tristate: true,
                  value: whole ? true : (subs > 0 ? null : false),
                  onChanged: (_) => _toggleParent(cat),
                ),
                Expanded(
                  child: Text(
                    cat.name,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (subs > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tag('$subs', color: c.accent),
                  ),
                if (hasSubs) ...[
                  Text(
                    '${cat.subcategories.length}',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                  Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: c.muted,
                  ),
                ],
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
        if (hasSubs && open)
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 0, 10, 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final sub in cat.subcategories)
                  if (query.isEmpty ||
                      cat.name.toLowerCase().contains(query) ||
                      sub.name.toLowerCase().contains(query))
                    FilterChip(
                      label: Text(sub.name),
                      selected:
                          whole ||
                          selected.contains((
                            category: cat.id,
                            subcategory: sub.id,
                          )),
                      onSelected: (_) => _toggleSub(cat, sub),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

/// La colonne des résultats : barre d'état, liste, barre d'envoi.
class _Results extends ConsumerWidget {
  const _Results({
    required this.state,
    required this.onSearch,
    required this.onClear,
    required this.onSend,
  });
  final BulkState state;
  final VoidCallback onSearch, onClear, onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final notifier = ref.read(bulkImportProvider.notifier);
    final selected = state.selected;
    final pending = state.pending;
    final all = pending.isNotEmpty && selected.length == pending.length;

    Widget list = const SizedBox.shrink();
    if (!state.searched) {
      list = const EmptyState(
        Icons.playlist_add_rounded,
        'Choisis un tracker et une taille max, puis lance la recherche.\n'
        'Les plus petits torrents arrivent en premier.',
      );
    } else if (state.items.isEmpty && state.loading) {
      list = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              '${state.scanned} sorties examinées',
              style: TextStyle(color: c.muted, fontSize: 12.5),
            ),
          ],
        ),
      );
    } else if (state.items.isEmpty) {
      list = _EmptyResults(
        criteria: state.criteria,
        categories: state.categories,
        scanned: state.scanned,
        onClear: onClear,
        onMore: state.hasMore ? notifier.loadMore : null,
      );
    }
    if (state.items.isEmpty) {
      // Petit écran, filtres ouverts : peu de hauteur, l'état vide défile.
      final message = list;
      list = LayoutBuilder(
        builder: (_, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(child: message),
          ),
        ),
      );
    } else {
      list = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 400 && state.hasMore && !state.loading) {
            notifier.loadMore();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount:
              state.items.length + (state.loading || state.hasMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= state.items.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: state.loading
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : OutlinedButton.icon(
                          onPressed: notifier.loadMore,
                          icon: const Icon(Icons.expand_more_rounded, size: 18),
                          label: const Text('Chercher plus loin'),
                        ),
                ),
              );
            }
            final item = state.items[i];
            return _BulkRow(
              item: item,
              onToggle: (v) => notifier.toggle(item.key, v),
            );
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.searched)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(
              children: [
                Checkbox(
                  tristate: true,
                  value: all ? true : (selected.isEmpty ? false : null),
                  onChanged: pending.isEmpty
                      ? null
                      : (_) => all
                            ? notifier.toggleAll(false)
                            : notifier.selectPending(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '${state.items.length} résultat'
                              '${state.items.length > 1 ? 's' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text:
                              ' sur ${state.scanned} examiné'
                              '${state.scanned > 1 ? 's' : ''}'
                              '${state.sentCount > 0 ? ' · ${state.sentCount} envoyé${state.sentCount > 1 ? 's' : ''}' : ''}',
                          style: TextStyle(color: c.muted),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (state.loading) ...[
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: notifier.stop,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('Stopper'),
                  ),
                ] else if (state.hasMore)
                  TextButton.icon(
                    onPressed: notifier.loadMore,
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    label: const Text('Encore'),
                  ),
              ],
            ),
          ),
        if (state.criteria.tracker case final t?)
          QuotaNotice(
            trackers: [t],
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: ErrorBanner(state.error!, onRetry: onSearch),
          ),
        Expanded(child: list),
        if (selected.isNotEmpty || state.sending)
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  '${selected.length} sélectionné'
                                  '${selected.length > 1 ? 's' : ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: '  ·  ${formatBytes(state.selectedSize)}',
                              style: TextStyle(color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: state.sending ? null : onSend,
                      icon: state.sending
                          ? SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.onAccent,
                              ),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        state.sending
                            ? 'Envoi ${state.sent + 1} / ${state.toSend}…'
                            // Le total est déjà à gauche : libellé court
                            // sur un téléphone.
                            : MediaQuery.sizeOf(context).width < 600
                            ? 'Envoyer'
                            : 'Envoyer à Transmission (${selected.length} · '
                                  '${formatBytes(state.selectedSize)})',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// État vide plus bavard que le simple « aucune sortie » : il récapitule
/// les filtres actifs pour aider à comprendre pourquoi la recherche n'a rien
/// ramené, et propose de chercher plus loin ou de tout effacer.
class _EmptyResults extends StatelessWidget {
  const _EmptyResults({
    required this.criteria,
    required this.categories,
    required this.scanned,
    required this.onClear,
    this.onMore,
  });
  final BulkCriteria criteria;
  final List<Category> categories;
  final int scanned;
  final VoidCallback onClear;

  /// Des pages restent à parcourir.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final parts = <String>[
      if (criteria.name.isNotEmpty) 'nom « ${criteria.name} »',
      if (criteria.categories.isNotEmpty)
        'catégories : ${criteria.categories.map((r) => categoryLabel(categories, r)).join(', ')}',
      if (criteria.sizeMin != null) 'taille ≥ ${_size(criteria.sizeMin!)}',
      if (criteria.sizeMax != null) 'taille ≤ ${_size(criteria.sizeMax!)}',
      if (criteria.seedersMin != null) 'seeders ≥ ${criteria.seedersMin}',
      if (criteria.seedersMax != null) 'seeders ≤ ${criteria.seedersMax}',
      if (criteria.leechersMin != null) 'leechers ≥ ${criteria.leechersMin}',
      if (criteria.leechersMax != null) 'leechers ≤ ${criteria.leechersMax}',
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 44, color: c.muted),
              const SizedBox(height: 12),
              const Text(
                'Aucun résultat',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                parts.isEmpty
                    ? 'La recherche n’a rien ramené — vérifie que le tracker est '
                          'bien configuré.'
                    : '$scanned sorties examinées. Filtres actifs : '
                          '${parts.join(' · ')}',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (onMore != null)
                    FilledButton.icon(
                      onPressed: onMore,
                      icon: const Icon(Icons.expand_more_rounded, size: 18),
                      label: const Text('Chercher plus loin'),
                    ),
                  OutlinedButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.clear_all_rounded, size: 18),
                    label: const Text('Vider les filtres'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoundField extends StatelessWidget {
  const _BoundField({
    required this.controller,
    required this.label,
    required this.hint,
    this.digits = false,
    this.invalid = false,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool digits;
  final bool invalid;

  /// Entrée : appliquer aux résultats déjà là.
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.text,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: invalid
          ? const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        errorText: invalid ? 'Format invalide' : null,
      ),
    );
  }
}

/// Une sortie : case, titre et nom, étiquettes ; taille et pairs à droite.
class _BulkRow extends StatelessWidget {
  const _BulkRow({required this.item, required this.onToggle});
  final BulkItem item;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = item.release;
    final small = TextStyle(fontSize: 11.5, color: c.muted);
    final on = !item.done && item.selected;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: on ? c.accent.withValues(alpha: 0.07) : c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: item.done
                ? c.success.withValues(alpha: 0.5)
                : item.failed
                ? c.danger.withValues(alpha: 0.5)
                : on
                ? c.accent.withValues(alpha: 0.45)
                : c.border,
          ),
        ),
        child: InkWell(
          onTap: item.done ? null : () => onToggle(!item.selected),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            child: Row(
              children: [
                Checkbox(
                  value: item.done ? true : item.selected,
                  onChanged: item.done ? null : (v) => onToggle(v ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title ?? r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: item.done ? c.muted : null,
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                      if (r.subcategory.isNotEmpty ||
                          item.present ||
                          item.done ||
                          item.failed) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (r.subcategory.isNotEmpty) Tag(r.subcategory),
                            if (item.present && !item.done)
                              Tag('DANS TRANSMISSION', color: c.muted),
                            if (item.done) Tag('ENVOYÉ', color: c.success),
                            if (item.failed) Tag('ÉCHEC', color: c.danger),
                          ],
                        ),
                      ],
                      if (item.detail != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            item.detail!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: small.copyWith(color: c.danger),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _size(r.size),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('▲ ${r.seeders}  ▼ ${r.leechers}', style: small),
                  ],
                ),
                IconButton(
                  tooltip: 'Détail',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: c.muted,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReleaseDetailPage(release: r),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
