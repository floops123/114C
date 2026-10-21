import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../core/format.dart';
import '../state/bulk_import.dart';
import 'release_detail_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Import en masse : on cherche un nom sur tous les trackers, on cadre les
/// résultats (taille, seeders, leechers, catégorie), on coche ce qui
/// convient, et on envoie tout à Transmission d'un coup.
class BulkImportPage extends ConsumerStatefulWidget {
  const BulkImportPage({super.key});

  @override
  ConsumerState<BulkImportPage> createState() => _BulkImportPageState();
}

class _BulkImportPageState extends ConsumerState<BulkImportPage> {
  final _name = TextEditingController();
  final _sizeMin = TextEditingController();
  final _sizeMax = TextEditingController();
  final _seedMin = TextEditingController();
  final _seedMax = TextEditingController();
  final _leechMin = TextEditingController();
  final _leechMax = TextEditingController();
  final _invalid = <TextEditingController>{};

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
    ref.read(bulkImportProvider.notifier).update(_criteria(ref.read(bulkImportProvider).criteria));
    ref.read(bulkImportProvider.notifier).search();
  }

  /// Applique les bornes à l'affichage (sans réinterroger les trackers).
  void _apply() {
    FocusScope.of(context).unfocus();
    ref.read(bulkImportProvider.notifier).update(_criteria(ref.read(bulkImportProvider).criteria));
    setState(() {}); // Pour repeindre les champs invalides en rouge.
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
        content: const Text(
          'Ils seront ajoutés à Transmission avec leurs dossiers d’origine, '
          'un par un. Les échecs restent affichés ligne par ligne.',
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
    messenger.showSnackBar(SnackBar(
      content: Text('$added torrent${added > 1 ? 's' : ''} envoyé'
          '${added > 1 ? 's' : ''} à Transmission'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(bulkImportProvider);
    final notifier = ref.read(bulkImportProvider.notifier);
    final selected = state.selected;
    // Reconstruire les contrôles (champs invalides colorés) après une saisie.
    final invalidSnapshot = _invalid.toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import en masse'),
        actions: [
          if (state.loading) ...[
            TextButton.icon(
              onPressed: notifier.stop,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Stopper'),
            ),
            TextButton.icon(
              onPressed: notifier.loadMore,
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              label: const Text('Encore'),
            ),
          ],
          IconButton(
            tooltip: 'Chercher',
            icon: const Icon(Icons.search_rounded),
            onPressed: _search,
          ),
        ],
      ),
      body: Column(children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Panel(
              radius: 14,
              child: Column(children: [
                TextField(
                  controller: _name,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    labelText: 'Nom (recherché sur les trackers choisis)',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                _FilterChips<Tracker>(
                  label: 'Trackers',
                  allLabel: 'Tous les trackers',
                  items: ref.watch(trackersProvider).keys.toList(),
                  selected: state.criteria.trackers,
                  onChanged: (next) => notifier.update(
                      state.criteria.copyWith(trackers: next)),
                ),
                const SizedBox(height: 6),
                _CategoryChips(
                  selected: state.criteria.categories,
                  available: state.availableCategories,
                  loading: state.loadingCategories,
                  onChanged: (next) => notifier.update(
                      state.criteria.copyWith(categories: next)),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _BoundField(
                      controller: _sizeMin,
                      label: 'Taille min',
                      hint: 'ex. 1,5 Go',
                      invalid: invalidSnapshot.contains(_sizeMin),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BoundField(
                      controller: _sizeMax,
                      label: 'Taille max',
                      hint: 'ex. 50 Go',
                      invalid: invalidSnapshot.contains(_sizeMax),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _BoundField(
                      controller: _seedMin,
                      label: 'Seeders min',
                      hint: '0',
                      digits: true,
                      invalid: invalidSnapshot.contains(_seedMin),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BoundField(
                      controller: _seedMax,
                      label: 'Seeders max',
                      hint: '∞',
                      digits: true,
                      invalid: invalidSnapshot.contains(_seedMax),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _BoundField(
                      controller: _leechMin,
                      label: 'Leechers min',
                      hint: '0',
                      digits: true,
                      invalid: invalidSnapshot.contains(_leechMin),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BoundField(
                      controller: _leechMax,
                      label: 'Leechers max',
                      hint: '∞',
                      digits: true,
                      invalid: invalidSnapshot.contains(_leechMax),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  FilledButton.icon(
                    onPressed: state.loading ? null : _search,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: Text(state.searched && !state.loading
                        ? 'Relancer'
                        : 'Rechercher'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _apply,
                    icon: const Icon(Icons.filter_alt_rounded, size: 18),
                    label: const Text('Filtrer l’existant'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
        if (state.searched)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${state.items.length} résultat${state.items.length > 1 ? 's' : ''}'
                  '${state.sentCount > 0 ? ' · ${state.sentCount} envoyé${state.sentCount > 1 ? 's' : ''}' : ''}'
                  '${selected.isNotEmpty ? ' · ${selected.length} sélectionné${selected.length > 1 ? 's' : ''}' : ''}',
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
              ),
              TextButton(
                onPressed: state.items.isEmpty
                    ? null
                    : () => notifier.toggleAll(true),
                child: const Text('Tout cocher'),
              ),
              TextButton(
                onPressed: state.items.isEmpty
                    ? null
                    : () => notifier.toggleAll(false),
                child: const Text('Tout décocher'),
              ),
            ]),
          ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: ErrorBanner(state.error!, onRetry: _search),
          ),
        Expanded(
          child: !state.searched
              ? const EmptyState(
                  Icons.playlist_add_rounded,
                  'Renseigne un nom et les bornes, puis lance la recherche.',
                )
              : state.items.isEmpty && state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : state.items.isEmpty
                      ? const EmptyState(Icons.search_off_rounded,
                          'Aucune sortie ne passe les filtres.')
                      : NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n.metrics.extentAfter < 400 && state.loading) {
                              notifier.loadMore();
                            }
                            return false;
                          },
                          child: ListView.builder(
                            itemCount: state.items.length +
                                (state.loading ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i >= state.items.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }
                              return _BulkRow(
                                item: state.items[i],
                                onToggle: (v) => notifier.toggle(
                                    state.items[i].key, v),
                              );
                            },
                          ),
                        ),
        ),
        if (selected.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: state.sending ? null : _send,
                  icon: state.sending
                      ? SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: c.onAccent),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(state.sending
                      ? 'Envoi…'
                      : 'Envoyer à Transmission (${selected.length})'),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Rangée de chips multi-sélection pour une énumération (ici `Tracker`).
/// `selected` vide = pas de filtre, l'utilisateur voit alors la chip « Tous »
/// marquée.
class _FilterChips<T> extends StatelessWidget {
  const _FilterChips({
    required this.label,
    required this.allLabel,
    required this.items,
    required this.selected,
    required this.onChanged,
  });
  final String label;
  final String allLabel;
  final List<T> items;
  final Set<T> selected;
  final void Function(Set<T> next) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label,
          style: TextStyle(
              color: c.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 6, children: [
        _allChip<T>(context, items, selected, onChanged, allLabel),
        for (final t in items) _itemChip<T>(context, t, selected, onChanged),
      ]),
    ]);
  }
}

Widget _allChip<T>(BuildContext context, List<T> items, Set<T> selected,
    void Function(Set<T>) onChanged, String label) {
  final c = context.colors;
  final isOn = selected.isEmpty;
  return ChoiceChip(
    label: Text(label),
    selected: isOn,
    onSelected: (_) => onChanged(<T>{}),
    avatar: Icon(Icons.all_inclusive_rounded,
        size: 16, color: isOn ? c.onAccent : c.muted),
  );
}

Widget _itemChip<T>(
    BuildContext context, T item, Set<T> selected, void Function(Set<T>) onChanged) {
  final isOn = selected.isEmpty || selected.contains(item);
  // Clic sur un chip coché → on l'enlève. Sur un chip non coché → on le
  // garde seul (ou on l'ajoute à l'ensemble courant). Logique : on ne garde
  // que les chips explicitement cochés, vidés = « tout » via la chip « Tous ».
  return ChoiceChip(
    label: Text(item.toString().split('.').last),
    selected: isOn,
    onSelected: (_) {
      if (selected.isEmpty) {
        // Tout est coché, on coche seulement cet item.
        onChanged({item});
      } else if (selected.contains(item)) {
        // On enlève cet item.
        onChanged({...selected}..remove(item));
      } else {
        // On l'ajoute.
        onChanged({...selected, item});
      }
    },
  );
}

/// Chips de sous-catégories : chargées en tâche de fond depuis les
/// `categories()` des trackers configurés. Pendant le chargement, une
/// « placeholder » est affichée.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.selected,
    required this.available,
    required this.loading,
    required this.onChanged,
  });
  final Set<String> selected;
  final List<String> available;
  final bool loading;
  final void Function(Set<String>) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Catégorie',
          style: TextStyle(
              color: c.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      if (loading && available.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text('Chargement des catégories…',
                style: TextStyle(color: c.muted, fontSize: 12)),
          ]),
        )
      else
        Wrap(spacing: 6, runSpacing: 6, children: [
          _allChip<String>(
            context,
            available,
            selected,
            onChanged,
            'Toutes',
          ),
          for (final cat in available)
            _itemChip<String>(context, cat, selected, onChanged),
        ]),
    ]);
  }
}

class _BoundField extends StatelessWidget {
  const _BoundField({
    required this.controller,
    required this.label,
    required this.hint,
    this.digits = false,
    this.invalid = false,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool digits;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.text,
      inputFormatters:
          digits ? [FilteringTextInputFormatter.digitsOnly] : null,
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

class _BulkRow extends ConsumerWidget {
  const _BulkRow({required this.item, required this.onToggle});
  final BulkItem item;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final r = item.release;
    final small = TextStyle(fontSize: 11.5, color: c.muted);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: item.done
                  ? c.success.withValues(alpha: 0.5)
                  : item.selected
                      ? c.accent.withValues(alpha: 0.5)
                      : c.border),
        ),
        child: InkWell(
          onTap: item.done
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ReleaseDetailPage(release: r))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
            child: Row(children: [
              Checkbox(
                value: item.done ? true : item.selected,
                onChanged: item.done ? null : (v) => onToggle(v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      r.title ?? r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: item.done ? c.muted : null,
                        decoration: item.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small),
                    const SizedBox(height: 5),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(spacing: 6, children: [
                        Tag(r.tracker.label, color: c.accent),
                        if (r.subcategory.isNotEmpty) Tag(r.subcategory),
                        Text(formatBytes(r.size), style: small),
                        Text('▲ ${r.seeders}', style: small),
                        Text('▼ ${r.leechers}', style: small),
                        if (item.done) Tag('ENVOYÉ', color: c.success),
                        if (item.failed) Tag('ÉCHEC', color: c.danger),
                      ]),
                    ),
                    if (item.detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(item.detail!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: small.copyWith(color: c.danger)),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}