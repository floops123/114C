import 'package:flutter/material.dart';

import '../api/tracker.dart';
import '../state/bulk_import.dart' show CategoryRef;
import 'theme.dart';
import 'widgets.dart';

/// Catégories du tracker en arbre replié : une ligne par catégorie (case
/// à trois états : entière, en partie, pas du tout), ses sous-catégories
/// en puces quand on la déplie. Aucune cochée = toutes. Un champ filtre les
/// noms quand la liste est longue.
class CategoryTree extends StatefulWidget {
  const CategoryTree({
    super.key,
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
  State<CategoryTree> createState() => _CategoryTreeState();
}

class _CategoryTreeState extends State<CategoryTree> {
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

