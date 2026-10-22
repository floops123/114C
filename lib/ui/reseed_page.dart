import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/format.dart';
import '../state/reseed.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ordre d'affichage des résultats.
const _order = [
  ReseedStatus.match,
  ReseedStatus.verifying,
  ReseedStatus.added,
  ReseedStatus.incomplete,
  ReseedStatus.searching,
  ReseedStatus.waiting,
  ReseedStatus.mismatch,
  ReseedStatus.error,
  ReseedStatus.present,
  ReseedStatus.notFound,
];

/// Reseed : un dossier de l'appareil, cherché sur un tracker ; ce qui
/// correspond s'ajoute à Transmission sur place, sans retéléchargement.
class ReseedPage extends ConsumerStatefulWidget {
  const ReseedPage({super.key});

  @override
  ConsumerState<ReseedPage> createState() => _ReseedPageState();
}

class _ReseedPageState extends ConsumerState<ReseedPage> {
  String? _folder;
  Tracker? _tracker;
  bool _deep = false;
  ReseedStatus? _filter;
  final _transmissionFolder = TextEditingController();

  @override
  void dispose() {
    _transmissionFolder.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Choisir');
    if (dir == null || !mounted) return;
    setState(() {
      _folder = dir;
      // Transmission sur cet appareil : il voit le dossier tel quel.
      if (reseedLocalClient(ref.read(transmissionProvider)) || _transmissionFolder.text.isEmpty) {
        _transmissionFolder.text = reseedLocalClient(ref.read(transmissionProvider)) ? dir : '';
      }
    });
  }

  void _scan() {
    FocusScope.of(context).unfocus();
    setState(() => _filter = null);
    ref.read(reseedProvider.notifier).scan(folder: _folder!, tracker: _tracker!, deep: _deep);
  }

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await ref.read(reseedProvider.notifier).addSelected(
          folder: _folder!,
          transmissionFolder: _transmissionFolder.text.trim(),
        );
    messenger.showSnackBar(SnackBar(content: Text('$n torrent${n > 1 ? 's' : ''} repartagé${n > 1 ? 's' : ''}')));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reseedProvider);
    final notifier = ref.read(reseedProvider.notifier);
    final trackers = ref.watch(trackersProvider).keys.toList();
    final local = reseedLocalClient(ref.watch(transmissionProvider));
    final tracker = _tracker ?? (trackers.isEmpty ? null : trackers.first);
    _tracker = tracker;
    final c = context.colors;
    final total = state.items.length;
    final selected = state.selected;
    final canAdd = selected.isNotEmpty && _transmissionFolder.text.trim().isNotEmpty && !state.adding;

    final items = [
      for (final s in _order)
        for (final i in state.items)
          if (i.status == s && (_filter == null || _filter == s)) i,
    ];
    final present = {for (final i in state.items) i.status};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reseed'),
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
        Expanded(
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(
                    'Choisis un dossier de cet appareil : chaque fichier et dossier qu’il '
                    'contient est cherché sur le tracker (même nom, même taille, mêmes '
                    'fichiers et mêmes données). Ce qui correspond s’ajoute à '
                    'Transmission sur place : le torrent pointe vers tes fichiers, en '
                    'pause, et ne repart qu’une fois vérifié complet — rien n’est '
                    'retéléchargé.',
                    style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: Text(
                        _folder ?? 'Aucun dossier choisi',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: _folder == null ? c.muted : null),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: state.running ? null : _pick,
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: Text(_folder == null ? 'Choisir un dossier' : 'Changer'),
                    ),
                  ]),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _deep,
                    onChanged: state.running ? null : (v) => setState(() => _deep = v ?? false),
                    title: const Text('Aussi le contenu des sous-dossiers'),
                    subtitle: const Text('Pour un dossier qui regroupe des sorties (« Films », « Séries »)'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text('Chercher sur',
                        style: TextStyle(color: c.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final t in trackers)
                      ChoiceChip(
                        label: Text(t.label),
                        selected: t == tracker,
                        onSelected: state.running ? null : (_) => setState(() => _tracker = t),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _transmissionFolder,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Ce dossier, vu par Transmission',
                      hintText: local ? null : '/chemin/sur/le/serveur',
                      helperMaxLines: 3,
                      helperText: local
                          ? 'Transmission tourne sur cet appareil : le même chemin.'
                          : 'Transmission tourne sur un autre appareil : indique où il voit ce '
                              'dossier (partage réseau, NAS, montage). Sans accès à ces fichiers, '
                              'le torrent resterait en pause.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: state.running || _folder == null || tracker == null ? null : _scan,
                    icon: state.running
                        ? SizedBox.square(
                            dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent))
                        : const Icon(Icons.manage_search_rounded, size: 18),
                    label: Text(state.running ? 'Recherche ${state.done} / $total' : 'Rechercher'),
                  ),
                  if (state.running && total > 0) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                        value: state.done / total, minHeight: 3, borderRadius: BorderRadius.circular(2)),
                  ],
                ]),
              ),
            ),
            if (state.error != null) SliverToBoxAdapter(child: ErrorBanner(state.error!)),
            if (state.items.isNotEmpty)
              SliverToBoxAdapter(
                child: ChipRow<ReseedStatus?>(
                  items: [null, ..._order.where(present.contains)],
                  selected: _filter,
                  label: (s) => s == null ? 'Tous ($total)' : '${s.label} (${state.count(s)})',
                  onSelected: (s) => setState(() => _filter = s),
                ),
              ),
            SliverToBoxAdapter(child: Divider(height: 13, color: c.border)),
            if (state.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  Icons.drive_folder_upload_rounded,
                  state.running ? 'Lecture du dossier…' : 'Choisis un dossier et un tracker, puis lance la recherche.',
                ),
              )
            else
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => _ReseedTile(
                  item: items[i],
                  onToggle: (v) => notifier.toggle(items[i].key, v),
                ),
              ),
          ]),
        ),
        if (state.count(ReseedStatus.match) > 0 || state.adding)
          DecoratedBox(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _transmissionFolder.text.trim().isEmpty
                          ? 'Indique le dossier vu par Transmission'
                          : '${selected.length} sélectionné${selected.length > 1 ? 's' : ''} · '
                              '${formatBytes(selected.fold(0, (n, i) => n + i.size))}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: canAdd ? _add : null,
                    icon: state.adding
                        ? SizedBox.square(
                            dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent))
                        : const Icon(Icons.playlist_add_check_rounded, size: 18),
                    label: Text(state.adding ? 'Vérification…' : 'Ajouter à Transmission'),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _ReseedTile extends StatelessWidget {
  const _ReseedTile({required this.item, required this.onToggle});
  final ReseedItem item;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color color, IconData icon) = switch (item.status) {
      ReseedStatus.match => (c.accent, Icons.link_rounded),
      ReseedStatus.verifying => (c.info, Icons.fact_check_rounded),
      ReseedStatus.added => (c.success, Icons.check_circle_rounded),
      ReseedStatus.incomplete => (c.warning, Icons.pause_circle_rounded),
      ReseedStatus.present => (c.success, Icons.check_rounded),
      ReseedStatus.searching => (c.info, Icons.manage_search_rounded),
      ReseedStatus.mismatch => (c.warning, Icons.difference_outlined),
      ReseedStatus.error => (c.danger, Icons.error_outline_rounded),
      _ => (c.muted, Icons.remove_rounded),
    };
    final small = TextStyle(fontSize: 11.5, color: c.muted);
    final r = item.release;
    return InkWell(
      onTap: item.status == ReseedStatus.match ? () => onToggle(!item.selected) : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${item.status.label} · ${formatBytes(item.size)}', style: small.copyWith(color: color)),
              if (r != null)
                Text('${r.tracker.label} : ${r.name} · ▲ ${r.seeders}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
              if (item.detail != null) Text(item.detail!, maxLines: 3, style: small),
            ]),
          ),
          if (item.status == ReseedStatus.match)
            Checkbox(value: item.selected, onChanged: (v) => onToggle(v ?? false)),
        ]),
      ),
    );
  }
}
