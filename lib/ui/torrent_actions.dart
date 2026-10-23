import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/content_kind.dart';
import '../api/transmission.dart';
import '../core/bencode.dart';
import '../core/format.dart';
import '../state/torrents.dart';
import 'theme.dart';

/// Lance une action RPC puis rafraîchit la liste ; affiche l'erreur éventuelle.
Future<bool> runTorrentAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(TransmissionClient c) action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(torrentsProvider.notifier).run(action);
    if (success != null) {
      messenger.showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } on TransmissionException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

String _plural(int n, String word) => n > 1 ? '$n ${word}s' : '1 $word';

/// Entrées du menu d'actions, pour un ou plusieurs torrents.
enum TorrentAction {
  start('Démarrer', Icons.play_arrow_rounded),
  startNow('Démarrer maintenant', Icons.fast_forward_rounded),
  stop('Arrêter', Icons.pause_rounded),
  verify('Vérifier les données', Icons.fact_check_outlined),
  reannounce('Réannoncer', Icons.campaign_outlined),
  queueTop('Haut de la file', Icons.vertical_align_top_rounded),
  queueUp('Monter dans la file', Icons.arrow_upward_rounded),
  queueDown('Descendre dans la file', Icons.arrow_downward_rounded),
  queueBottom('Bas de la file', Icons.vertical_align_bottom_rounded),
  move('Déplacer les fichiers…', Icons.drive_file_move_outline),
  labels('Étiquettes…', Icons.label_outline),
  priority('Priorité…', Icons.low_priority_rounded),
  copyMagnet('Copier le lien magnet', Icons.link_rounded),
  remove('Supprimer…', Icons.delete_outline);

  const TorrentAction(this.label, this.icon);
  final String label;
  final IconData icon;

  /// Actions séparées des précédentes par un trait dans le menu.
  bool get startsGroup =>
      this == queueTop || this == move || this == remove;

  static const _rpc = {
    start: 'torrent-start',
    startNow: 'torrent-start-now',
    stop: 'torrent-stop',
    verify: 'torrent-verify',
    reannounce: 'torrent-reannounce',
    queueTop: 'queue-move-top',
    queueUp: 'queue-move-up',
    queueDown: 'queue-move-down',
    queueBottom: 'queue-move-bottom',
  };
}

/// Menu « ⋮ » d'actions sur des torrents.
class TorrentMenu extends ConsumerWidget {
  const TorrentMenu({
    super.key,
    required this.torrents,
    this.magnetLink,
    this.onRemoved,
    this.exclude = const {},
    this.compact = false,
  });

  final List<Torrent> torrents;

  /// Bouton réduit, aligné sur des boutons d'icône de 32 px (tableau).
  final bool compact;

  /// Disponible seulement sur l'écran de détail (champ lourd).
  final String? magnetLink;
  final VoidCallback? onRemoved;
  final Set<TorrentAction> exclude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final actions = TorrentAction.values.where((a) =>
        !exclude.contains(a) &&
        (a != TorrentAction.copyMagnet || magnetLink != null));
    return PopupMenuButton<TorrentAction>(
      tooltip: 'Actions',
      icon: Icon(Icons.more_vert_rounded, size: compact ? 18 : null),
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
      onSelected: (a) => handleTorrentAction(context, ref, a, torrents,
          magnetLink: magnetLink, onRemoved: onRemoved),
      itemBuilder: (_) => [
        for (final a in actions) ...[
          if (a.startsGroup) const PopupMenuDivider(),
          PopupMenuItem(
            value: a,
            child: Row(children: [
              Icon(a.icon,
                  size: 18,
                  color: a == TorrentAction.remove ? c.danger : c.muted),
              const SizedBox(width: 12),
              Text(a.label,
                  style: a == TorrentAction.remove
                      ? TextStyle(color: c.danger)
                      : null),
            ]),
          ),
        ],
      ],
    );
  }
}

Future<void> handleTorrentAction(
  BuildContext context,
  WidgetRef ref,
  TorrentAction action,
  List<Torrent> torrents, {
  String? magnetLink,
  VoidCallback? onRemoved,
}) async {
  final ids = [for (final t in torrents) t.id];
  final rpc = TorrentAction._rpc[action];
  if (rpc != null) {
    await runTorrentAction(context, ref, (c) => c.action(rpc, ids));
    return;
  }
  switch (action) {
    case TorrentAction.move:
      await askLocation(context, ref, torrents);
    case TorrentAction.labels:
      await editLabels(context, ref, torrents);
    case TorrentAction.priority:
      await askPriority(context, ref, torrents);
    case TorrentAction.copyMagnet:
      await Clipboard.setData(ClipboardData(text: magnetLink!));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lien magnet copié')));
      }
    case TorrentAction.remove:
      if (await confirmRemove(context, ref, torrents)) onRemoved?.call();
    default:
  }
}

Future<bool> confirmRemove(
    BuildContext context, WidgetRef ref, List<Torrent> torrents) async {
  var deleteData = false;
  final c = context.colors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(torrents.length == 1
            ? 'Supprimer ce torrent ?'
            : 'Supprimer ${torrents.length} torrents ?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (torrents.length == 1)
            Text(torrents.first.name, style: TextStyle(color: c.muted)),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: deleteData,
            onChanged: (v) => setState(() => deleteData = v ?? false),
            title: const Text('Supprimer aussi les fichiers téléchargés'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: c.danger),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  return runTorrentAction(
    context,
    ref,
    (cl) => cl.remove([for (final t in torrents) t.id], deleteData: deleteData),
    success: '${_plural(torrents.length, 'torrent')} supprimé(s)',
  );
}

/// Dossier de destination, avec l'espace libre du dossier saisi.
Future<void> askLocation(
    BuildContext context, WidgetRef ref, List<Torrent> torrents) async {
  final client = ref.read(transmissionProvider);
  if (client == null) return;
  final controller = TextEditingController(
      text: torrents.length == 1 ? torrents.first.downloadDir : '');
  var move = true;
  String? space;

  Future<void> checkSpace(void Function(void Function()) setState) async {
    final path = controller.text.trim();
    if (path.isEmpty) return;
    try {
      final d = await client.diskSpace(path);
      setState(() => space = d.free == null
          ? null
          : '${formatBytes(d.free!)} libres'
              '${d.total != null ? ' sur ${formatBytes(d.total!)}' : ''}');
    } on TransmissionException {
      setState(() => space = 'Dossier introuvable sur le serveur');
    }
  }

  final location = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      return AlertDialog(
        title: Text(torrents.length == 1
            ? 'Déplacer le torrent'
            : 'Déplacer ${torrents.length} torrents'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nouveau dossier sur le serveur',
                helperText: space,
                suffixIcon: IconButton(
                  tooltip: 'Espace libre',
                  icon: const Icon(Icons.storage_rounded, size: 18),
                  onPressed: () => checkSpace(setState),
                ),
              ),
              onSubmitted: (_) => checkSpace(setState),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: move,
              onChanged: (v) => setState(() => move = v ?? true),
              title: const Text('Déplacer les fichiers existants'),
              subtitle: const Text(
                  'Sinon, Transmission cherche les fichiers dans ce dossier'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Déplacer')),
        ],
      );
    }),
  );
  controller.dispose();
  if (location == null || location.isEmpty || !context.mounted) return;
  await runTorrentAction(
    context,
    ref,
    (c) => c.setLocation([for (final t in torrents) t.id], location, move: move),
    success: move ? 'Déplacement lancé' : 'Emplacement mis à jour',
  );
}

Future<void> editLabels(
    BuildContext context, WidgetRef ref, List<Torrent> torrents) async {
  // Étiquettes déjà utilisées sur le serveur, proposées en raccourci.
  final known = {
    for (final t in ref.read(torrentsProvider).byId.values) ...t.labels,
  }.toList()
    ..sort();
  final selected = torrents.length == 1 ? {...torrents.first.labels} : <String>{};
  final input = TextEditingController();

  final result = await showDialog<Set<String>>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      void add() {
        final value = input.text.trim();
        if (value.isEmpty) return;
        setState(() {
          selected.add(value);
          if (!known.contains(value)) known.add(value);
          input.clear();
        });
      }

      return AlertDialog(
        title: const Text('Étiquettes'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (torrents.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                    'Remplace les étiquettes des ${torrents.length} torrents.',
                    style: TextStyle(color: context.colors.muted)),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final l in known)
                  FilterChip(
                    label: Text(l),
                    selected: selected.contains(l),
                    onSelected: (v) => setState(
                        () => v ? selected.add(l) : selected.remove(l)),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: input,
              decoration: InputDecoration(
                hintText: 'Nouvelle étiquette',
                suffixIcon: IconButton(
                    icon: const Icon(Icons.add_rounded), onPressed: add),
              ),
              onSubmitted: (_) => add(),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Appliquer')),
        ],
      );
    }),
  );
  input.dispose();
  if (result == null || !context.mounted) return;
  await runTorrentAction(
    context,
    ref,
    (c) => c.torrentSet(
        [for (final t in torrents) t.id], {'labels': result.toList()}),
  );
}

Future<void> askPriority(
    BuildContext context, WidgetRef ref, List<Torrent> torrents) async {
  final priority = await showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Priorité de bande passante'),
      children: [
        for (final (value, label) in priorityLabels)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(label),
            ),
          ),
      ],
    ),
  );
  if (priority == null || !context.mounted) return;
  await runTorrentAction(
    context,
    ref,
    (c) => c.torrentSet(
        [for (final t in torrents) t.id], {'bandwidthPriority': priority}),
  );
}

const priorityLabels = [
  (TransmissionClient.priorityHigh, 'Haute'),
  (TransmissionClient.priorityNormal, 'Normale'),
  (TransmissionClient.priorityLow, 'Basse'),
];

/// Options d'ajout (dossier, pause, étiquettes, priorité). null = annulé.
Future<AddOptions?> askAddOptions(BuildContext context, WidgetRef ref,
    {String? title}) async {
  final client = ref.read(transmissionProvider);
  if (client == null) return null;
  String? defaultDir;
  try {
    defaultDir = (await client.sessionGet())['download-dir'] as String?;
  } on TransmissionException {
    // Pas bloquant : le champ reste vide (= dossier par défaut du serveur).
  }
  if (!context.mounted) return null;

  final dir = TextEditingController(text: defaultDir ?? '');
  final labels = TextEditingController();
  var paused = false;
  var priority = TransmissionClient.priorityNormal;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      return AlertDialog(
        title: Text(title ?? 'Options d’ajout'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: dir,
              decoration:
                  const InputDecoration(labelText: 'Dossier de téléchargement'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labels,
              decoration: const InputDecoration(
                  labelText: 'Étiquettes',
                  helperText: 'Séparées par des virgules'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final (value, label) in priorityLabels.reversed)
                    ButtonSegment(value: value, label: Text(label)),
                ],
                selected: {priority},
                onSelectionChanged: (s) => setState(() => priority = s.first),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ajouter en pause'),
              value: paused,
              onChanged: (v) => setState(() => paused = v),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ajouter')),
        ],
      );
    }),
  );
  final options = AddOptions(
    downloadDir: dir.text.trim() == defaultDir ? null : dir.text.trim(),
    paused: paused,
    labels: [
      for (final l in labels.text.split(','))
        if (l.trim().isNotEmpty) l.trim(),
    ],
    bandwidthPriority:
        priority == TransmissionClient.priorityNormal ? null : priority,
  );
  dir.dispose();
  labels.dispose();
  return ok == true ? options : null;
}

/// Bilan de l'envoi de fichiers .torrent.
class FileAddReport {
  int added = 0;
  int duplicates = 0;

  /// Fichiers qui ne sont pas des .torrent valides (nom du fichier).
  final invalid = <String>[];

  /// Refusés par Transmission (nom du fichier : raison).
  final failed = <String>[];

  String get summary => [
        if (added > 0) '$added ajouté(s)',
        if (duplicates > 0) '$duplicates déjà présent(s)',
        if (invalid.isNotEmpty) '${invalid.length} invalide(s)',
        if (failed.isNotEmpty) '${failed.length} refusé(s)',
      ].join(' · ');
}

/// Vérifie puis envoie des fichiers .torrent ; un fichier invalide ou refusé
/// n'empêche pas l'envoi des autres.
Future<FileAddReport> addTorrentFiles(
  TransmissionClient client,
  List<(String name, Uint8List bytes)> files,
  AddOptions options,
) async {
  final report = FileAddReport();
  for (final (name, bytes) in files) {
    final TorrentContent content;
    try {
      content = TorrentContent.parse(bytes);
    } on FormatException {
      report.invalid.add(name);
      continue;
    }
    try {
      // Sans tracker, la catégorie est devinée d'après le nom du torrent.
      final added = await client.addTorrent(
          metainfo: bytes,
          options: await client.categorized(options, ContentKind.ofName(content.name)));
      added ? report.added++ : report.duplicates++;
    } on TransmissionException catch (e) {
      report.failed.add('$name : ${e.message}');
    }
  }
  return report;
}

/// Choisit un ou plusieurs .torrent sur l'appareil et les envoie.
Future<void> pickAndAddTorrentFiles(BuildContext context, WidgetRef ref) async {
  final client = ref.read(transmissionProvider);
  if (client == null) return;
  final picked = await openFiles(
    // Android : pas de filtre, beaucoup de gestionnaires de fichiers ne
    // reconnaissent pas le type .torrent ; le contenu est vérifié ensuite.
    acceptedTypeGroups: Platform.isAndroid
        ? const []
        : const [
            XTypeGroup(
              label: 'Fichiers .torrent',
              extensions: ['torrent'],
              mimeTypes: ['application/x-bittorrent'],
            ),
          ],
    confirmButtonText: 'Ajouter',
  );
  if (picked.isEmpty || !context.mounted) return;

  final files = <(String, Uint8List)>[];
  final preview = <(String, TorrentContent?)>[];
  for (final f in picked) {
    final bytes = await f.readAsBytes();
    files.add((f.name, bytes));
    TorrentContent? content;
    try {
      content = TorrentContent.parse(bytes);
    } on FormatException {
      content = null;
    }
    preview.add((f.name, content));
  }
  if (!context.mounted) return;

  final valid = preview.where((p) => p.$2 != null).length;
  var withOptions = false;
  final c = context.colors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(picked.length == 1
            ? 'Ajouter ce torrent ?'
            : 'Ajouter $valid torrent(s) ?'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(shrinkWrap: true, children: [
                for (final (file, content) in preview)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      content == null
                          ? Icons.error_outline_rounded
                          : Icons.description_outlined,
                      color: content == null ? c.danger : c.muted,
                      size: 20,
                    ),
                    title: Text(content?.name ?? file,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(content == null
                        ? 'Pas un fichier .torrent valide'
                        : '${formatBytes(content.totalSize)} · '
                            '${content.files.length} fichier(s)'),
                  ),
              ]),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: withOptions,
              onChanged: valid == 0
                  ? null
                  : (v) => setState(() => withOptions = v ?? false),
              title: const Text('Choisir le dossier, les étiquettes…'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: valid == 0 ? null : () => Navigator.pop(context, true),
              child: const Text('Ajouter')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;

  var options = const AddOptions();
  if (withOptions) {
    final chosen = await askAddOptions(context, ref);
    if (chosen == null || !context.mounted) return;
    options = chosen;
  }
  final messenger = ScaffoldMessenger.of(context);
  final report = await addTorrentFiles(client, files, options);
  await ref.read(torrentsProvider.notifier).refresh(full: true);
  messenger.showSnackBar(SnackBar(
    content: Text([
      report.summary,
      ...report.failed,
    ].where((l) => l.isNotEmpty).join('\n')),
  ));
}
