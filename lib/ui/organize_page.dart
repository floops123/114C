import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/organize.dart';
import 'content_art.dart';
import 'theme.dart';
import 'widgets.dart';

/// Filtres de la liste.
enum _Filter {
  todo('À ranger'),
  outside('Hors du dossier'),
  unknown('Non reconnus'),
  done('Déjà rangés'),
  all('Tous');

  const _Filter(this.label);
  final String label;
}

/// Ranger par catégorie : étiquette de la catégorie sur les torrents déjà
/// présents, puis leurs fichiers dans le dossier de celle-ci.
class OrganizePage extends ConsumerStatefulWidget {
  const OrganizePage({super.key});

  @override
  ConsumerState<OrganizePage> createState() => _OrganizePageState();
}

class _OrganizePageState extends ConsumerState<OrganizePage> {
  _Filter _filter = _Filter.todo;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(organizeProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(organizeProvider);
      if (s.groups.isEmpty && !s.busy) notifier.scan();
    });
  }

  static bool _matches(OrganizeGroup g, String? root, _Filter filter) {
    final outside = root == null || !g.torrents.every((t) => insideRoot(t.downloadDir, root));
    final todo = g.kind != ContentKind.other && (g.needsLabels || g.needsMove(root));
    return switch (filter) {
      _Filter.todo => todo && !outside,
      _Filter.outside => outside,
      _Filter.unknown => g.kind == ContentKind.other,
      _Filter.done => !todo && g.kind != ContentKind.other,
      _Filter.all => true,
    };
  }

  Future<void> _move(int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Déplacer $count élément${count > 1 ? 's' : ''} ?'),
        content: const SizedBox(
          width: 460,
          child: Text(
            'Transmission déplace les fichiers dans le dossier de leur '
            'catégorie, un élément à la fois ; le seed reprend à l’arrivée. '
            'Sur le même disque, c’est immédiat. Vers un autre disque, les '
            'fichiers sont copiés puis effacés : c’est plus long, il faut la '
            'place libre, et le torrent est indisponible pendant la copie.\n\n'
            'Les torrents qui partagent leurs fichiers (cross-seed, reseed) '
            'sont déplacés ensemble. Une médiathèque qui lisait ces dossiers '
            '(Jellyfin…) devra les retrouver à leur nouvel emplacement.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Déplacer')),
        ],
      ),
    );
    if (ok == true && mounted) await ref.read(organizeProvider.notifier).apply(move: true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(organizeProvider);
    final notifier = ref.read(organizeProvider.notifier);
    final c = context.colors;
    final root = state.root;
    final counts = {
      for (final f in _Filter.values) f: state.groups.where((g) => _matches(g, root, f)).length,
    };
    final shown = [for (final g in state.groups) if (_matches(g, root, _filter)) g];
    final selected = [
      for (final g in state.groups)
        if (state.selected.contains(g.key) && g.kind != ContentKind.other) g,
    ];
    final toMove = selected.where((g) => g.needsMove(root)).length;
    final guessed = state.groups.where((g) => g.from == KindSource.name && g.kind != ContentKind.other).length;
    final small = TextStyle(color: c.muted, fontSize: 12.5, height: 1.4);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranger par catégorie'),
        actions: [
          if (state.busy)
            TextButton.icon(
              onPressed: notifier.stop,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Arrêter'),
            )
          else
            PopupMenuButton<bool>(
              tooltip: 'Relever',
              onSelected: (force) => notifier.scan(force: force),
              itemBuilder: (_) => const [
                PopupMenuItem(value: false, child: Text('Relever à nouveau')),
                PopupMenuItem(value: true, child: Text('Réinterroger les trackers')),
              ],
              icon: const Icon(Icons.more_vert_rounded),
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'Chaque torrent reçoit l’étiquette de sa catégorie (trouvée sur '
              'son tracker, sinon devinée d’après le nom), puis ses fichiers '
              'peuvent rejoindre le dossier de cette catégorie sous '
              '${root == null ? 'le dossier de téléchargement' : '« $root »'}. '
              'Les nouveaux torrents y vont directement.',
              style: small,
            ),
            if (guessed > 0 && !state.scanning)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '$guessed catégorie${guessed > 1 ? 's' : ''} devinée${guessed > 1 ? 's' : ''} '
                  'd’après le nom : à vérifier (touche la catégorie pour la changer).',
                  style: TextStyle(color: c.warning, fontSize: 12),
                ),
              ),
            if (state.busy) ...[
              const SizedBox(height: 8),
              Text(
                state.scanning
                    ? state.toLookUp > 0
                        ? 'Recherche sur les trackers ${state.lookedUp} / ${state.toLookUp}'
                        : 'Lecture des torrents de Transmission…'
                    : 'Rangement ${state.applied} / ${state.toApply}',
                style: small,
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: state.scanning
                    ? (state.toLookUp > 0 ? state.lookedUp / state.toLookUp : null)
                    : (state.toApply > 0 ? state.applied / state.toApply : null),
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
          ]),
        ),
        if (state.error != null) ErrorBanner(state.error!),
        if (state.groups.isNotEmpty)
          ChipRow<_Filter>(
            items: [
              for (final f in _Filter.values)
                if (f == _filter || f == _Filter.all || counts[f]! > 0) f,
            ],
            selected: _filter,
            label: (f) => '${f.label} (${counts[f]})',
            onSelected: (f) => setState(() => _filter = f),
          ),
        const SizedBox(height: 6),
        Divider(height: 1, color: c.border),
        Expanded(
          child: shown.isEmpty
              ? EmptyState(
                  Icons.folder_special_outlined,
                  state.scanning
                      ? 'Lecture des torrents de Transmission…'
                      : _filter == _Filter.todo
                          ? 'Tout est rangé.'
                          : 'Aucun torrent ici.',
                )
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) => _GroupTile(
                    group: shown[i],
                    root: root,
                    selected: state.selected.contains(shown[i].key),
                    enabled: !state.busy,
                  ),
                ),
        ),
        if (shown.isNotEmpty)
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
              child: Row(children: [
                IconButton(
                  tooltip: 'Tout cocher',
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: state.busy
                      ? null
                      : () => notifier.select({
                            ...state.selected,
                            for (final g in shown)
                              if (g.kind != ContentKind.other) g.key,
                          }),
                ),
                IconButton(
                  tooltip: 'Tout décocher',
                  icon: const Icon(Icons.deselect_rounded),
                  onPressed: state.busy || state.selected.isEmpty ? null : () => notifier.select(const {}),
                ),
                // Téléphone : les deux boutons l'un sous l'autre.
                Expanded(
                  child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 6, children: [
                    OutlinedButton(
                      onPressed: state.busy || selected.isEmpty ? null : () => notifier.apply(move: false),
                      child: Text('Étiqueter (${selected.length})'),
                    ),
                    FilledButton(
                      onPressed: state.busy || toMove == 0 ? null : () => _move(toMove),
                      child: Text('Étiqueter et déplacer ($toMove)'),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _GroupTile extends ConsumerWidget {
  const _GroupTile({
    required this.group,
    required this.root,
    required this.selected,
    required this.enabled,
  });
  final OrganizeGroup group;
  final String? root;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final g = group;
    final notifier = ref.read(organizeProvider.notifier);
    final small = TextStyle(fontSize: 11.5, color: c.muted);
    final target = g.target(root);
    final color = g.kind.colors(c).first;
    final step = switch (g.step) {
      OrganizeStep.working => Text('En cours…', style: small.copyWith(color: c.info, fontWeight: FontWeight.w600)),
      OrganizeStep.done => Text('Rangé', style: small.copyWith(color: c.success, fontWeight: FontWeight.w600)),
      OrganizeStep.failed => Text('Échec', style: small.copyWith(color: c.danger, fontWeight: FontWeight.w600)),
      OrganizeStep.idle => null,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(
          value: selected,
          onChanged: enabled && g.kind != ContentKind.other ? (_) => notifier.toggle(g.key) : null,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                PopupMenuButton<ContentKind>(
                  tooltip: 'Changer de catégorie',
                  enabled: enabled,
                  initialValue: g.kind,
                  onSelected: (k) => notifier.setKind(g.key, k),
                  itemBuilder: (_) => [
                    for (final k in ContentKind.values)
                      PopupMenuItem(
                        value: k,
                        child: Row(children: [
                          Icon(k.icon, size: 18, color: k.colors(c).first),
                          const SizedBox(width: 10),
                          Text(k == ContentKind.other ? 'Non classé' : k.plural),
                        ]),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
                    decoration: BoxDecoration(
                      color: Color.lerp(color, c.surface, 0.82),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Color.lerp(color, c.surface, 0.5)!),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(g.kind.icon, size: 13, color: color),
                      const SizedBox(width: 4),
                      Text(g.kind == ContentKind.other ? 'Non classé' : g.kind.plural,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.text)),
                      Icon(Icons.arrow_drop_down_rounded, size: 16, color: c.muted),
                    ]),
                  ),
                ),
                Text(
                  g.from == KindSource.tracker && g.source != null ? g.source!.label : g.from.title,
                  style: small.copyWith(color: g.from == KindSource.name ? c.warning : c.muted),
                ),
                if (g.torrents.length > 1)
                  Tag('${g.torrents.length} torrents, mêmes fichiers', color: c.info),
                ?step,
              ]),
              const SizedBox(height: 3),
              Text(
                target != null && g.needsMove(root) ? '${g.downloadDir}  →  $target' : g.downloadDir,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
              if (g.detail != null)
                Text(g.detail!, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: small.copyWith(color: g.step == OrganizeStep.failed ? c.danger : c.muted)),
            ]),
          ),
        ),
      ]),
    );
  }
}
