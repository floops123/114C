import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/c411.dart';
import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/bencode.dart';
import 'cross_seed.dart' show crossSeedQuery;
import 'palliative.dart' show PalliativeNotifier, c411SiteApiProvider;
import 'palliative_match.dart';
import 'releases.dart';
import 'torrents.dart';

// Reseed : des fichiers déjà sur l'appareil (un dossier choisi), retrouvés
// sur un tracker (même nom, même taille, mêmes fichiers, empreintes du
// premier et du dernier morceau), puis ajoutés à Transmission sur place :
// le torrent pointe vers le fichier ou le dossier existant. Il est ajouté en
// pause, vérifié par Transmission, et ne repart que si les données sont
// complètes — sinon il resterait à retélécharger.

enum ReseedStatus {
  match('Trouvé'),
  verifying('Vérification…'),
  added('Repartagé'),
  incomplete('Données incomplètes'),
  searching('Recherche…'),
  waiting('En attente'),
  mismatch('Fichiers différents'),
  present('Déjà dans Transmission'),
  notFound('Introuvable'),
  error('Erreur');

  const ReseedStatus(this.label);
  final String label;
}

/// Un fichier ou un dossier de l'appareil, et sa sortie sur le tracker.
class ReseedItem {
  const ReseedItem({
    required this.path,
    required this.size,
    this.status = ReseedStatus.waiting,
    this.release,
    this.metainfo,
    this.match,
    this.selected = false,
    this.detail,
  });

  /// Chemin sur l'appareil.
  final String path;
  final int size;
  final ReseedStatus status;
  final Release? release;
  final Uint8List? metainfo;
  final LocalMatch? match;
  final bool selected;
  final String? detail;

  String get key => path;
  String get name => path.split(Platform.pathSeparator).last;

  ReseedItem copyWith({
    ReseedStatus? status,
    Release? release,
    Uint8List? metainfo,
    LocalMatch? match,
    bool? selected,
    String? Function()? detail,
  }) =>
      ReseedItem(
        path: path,
        size: size,
        status: status ?? this.status,
        release: release ?? this.release,
        metainfo: metainfo ?? this.metainfo,
        match: match ?? this.match,
        selected: selected ?? this.selected,
        detail: detail != null ? detail() : this.detail,
      );
}

class ReseedState {
  const ReseedState({
    this.items = const [],
    this.running = false,
    this.adding = false,
    this.done = 0,
    this.error,
  });

  final List<ReseedItem> items;
  final bool running;
  final bool adding;
  final int done;
  final String? error;

  int count(ReseedStatus s) => items.where((i) => i.status == s).length;
  List<ReseedItem> get selected =>
      [for (final i in items) if (i.selected && i.status == ReseedStatus.match) i];

  ReseedState copyWith({
    List<ReseedItem>? items,
    bool? running,
    bool? adding,
    int? done,
    String? Function()? error,
  }) =>
      ReseedState(
        items: items ?? this.items,
        running: running ?? this.running,
        adding: adding ?? this.adding,
        done: done ?? this.done,
        error: error != null ? error() : this.error,
      );
}

/// Ce qu'on cherche dans [folder] : chaque fichier et dossier de premier
/// niveau ; avec [deep], aussi ce que contiennent ses sous-dossiers (un
/// dossier « Films » plein de sorties). Taille totale pour un dossier.
Future<List<(String, int, LocalIndex)>> reseedCandidates(String folder, {bool deep = false}) async {
  final out = <(String, int, LocalIndex)>[];
  Future<void> add(FileSystemEntity e) async {
    if (e is File) {
      final size = await e.length();
      if (size > 0) out.add((e.path, size, LocalIndex([(e.path, size)])));
    } else if (e is Directory) {
      final index = await LocalIndex.scan(e.path);
      final size = index.files.fold(0, (n, f) => n + f.$2);
      if (size > 0) out.add((e.path, size, index));
    }
  }

  Future<List<FileSystemEntity>> children(Directory d) async => [
        await for (final e in d.list(followLinks: false))
          if (!e.path.split(Platform.pathSeparator).last.startsWith('.')) e,
      ]..sort((a, b) => a.path.compareTo(b.path));

  for (final e in await children(Directory(folder))) {
    await add(e);
    if (deep && e is Directory) {
      for (final sub in await children(e)) {
        await add(sub);
      }
    }
  }
  return out;
}

/// Chemin vu par Transmission de [local], sous [folder] vu comme
/// [transmissionFolder] (le même dossier, ou un montage réseau).
String transmissionPath(String local, {required String folder, required String transmissionFolder}) {
  var rest = local.startsWith(folder) ? local.substring(folder.length) : local;
  rest = rest.replaceAll(Platform.pathSeparator, '/');
  final base = transmissionFolder.endsWith('/') || transmissionFolder.endsWith(r'\')
      ? transmissionFolder.substring(0, transmissionFolder.length - 1)
      : transmissionFolder;
  if (rest.isEmpty) return base;
  // Séparateur de Transmission : celui du chemin donné (« C:\… » sous Windows).
  final sep = base.contains(r'\') && !base.contains('/') ? r'\' : '/';
  return '$base$sep${rest.replaceAll('/', sep).replaceFirst(RegExp(r'^[\\/]'), '')}';
}

class ReseedNotifier extends Notifier<ReseedState> {
  bool _stop = false;
  final _indexes = <String, LocalIndex>{};

  /// Attente entre deux contrôles de la vérification de Transmission.
  static Duration pollEvery = const Duration(seconds: 2);

  @override
  ReseedState build() => const ReseedState();

  void stop() => _stop = true;

  void _set(String key, ReseedItem Function(ReseedItem) change) {
    if (!ref.mounted) return;
    state = state.copyWith(items: [
      for (final i in state.items) i.key == key ? change(i) : i,
    ]);
  }

  void toggle(String key, bool selected) => _set(key, (i) => i.copyWith(selected: selected));

  /// Cherche chaque fichier ou dossier de [folder] sur [tracker].
  Future<void> scan({required String folder, required Tracker tracker, bool deep = false}) async {
    if (state.running) return;
    final api = ref.read(trackersProvider)[tracker];
    if (api == null) {
      state = state.copyWith(error: () => 'Configure ${tracker.label} dans les Réglages');
      return;
    }
    _stop = false;
    state = const ReseedState(running: true);
    final List<(String, int, LocalIndex)> found;
    try {
      found = await reseedCandidates(folder, deep: deep);
    } on FileSystemException catch (e) {
      state = state.copyWith(running: false, error: () => 'Dossier illisible : ${e.message}');
      return;
    }
    if (!ref.mounted) return;
    _indexes
      ..clear()
      ..addEntries([for (final (p, _, index) in found) MapEntry(p, index)]);
    state = state.copyWith(items: [
      for (final (path, size, _) in found) ReseedItem(path: path, size: size),
    ]);
    final present = ref.read(torrentsProvider).hashes;
    final site = ref.read(c411SiteApiProvider);
    for (final (n, item) in state.items.toList().indexed) {
      if (_stop || !ref.mounted) break;
      _set(item.key, (i) => i.copyWith(status: ReseedStatus.searching));
      final ReseedItem result;
      try {
        result = await _search(api, site, item, present);
      } on TrackerException catch (e) {
        _set(item.key, (i) => i.copyWith(status: ReseedStatus.error, detail: () => e.message));
        state = state.copyWith(done: n + 1);
        continue;
      }
      _set(item.key, (_) => result);
      state = state.copyWith(done: n + 1);
    }
    if (ref.mounted) state = state.copyWith(running: false);
  }

  /// Même nom (sans extension), même taille, puis mêmes fichiers et mêmes
  /// empreintes que ce qui est sur l'appareil.
  Future<ReseedItem> _search(TrackerApi api, C411SiteApi? site, ReseedItem item, Set<String> present) async {
    final query = crossSeedQuery(item.name);
    var found = (await api.releases(query: query, perPage: 20)).items;
    // AstraTorrent : points ou espaces selon les sorties.
    if (found.isEmpty && api.tracker == Tracker.astra && query.contains('.')) {
      found = (await api.releases(query: query.replaceAll('.', ' '), perPage: 20)).items;
    }
    final sameSize = found.where((r) => r.size == item.size).toList();
    if (sameSize.isEmpty) {
      return item.copyWith(
          status: ReseedStatus.notFound,
          detail: () => found.isEmpty ? 'Aucune sortie de ce nom' : 'Aucune sortie de cette taille');
    }
    for (final r in sameSize.take(3)) {
      if (r.infoHash != null && present.contains(r.infoHash!.toLowerCase())) {
        return item.copyWith(status: ReseedStatus.present, release: r);
      }
      final metainfo = await fetchTorrentFile(api, site, r);
      final TorrentContent content;
      try {
        content = TorrentContent.parse(metainfo);
      } on FormatException {
        continue;
      }
      final match = await matchLocal(content, _indexes[item.path]!);
      if (match != null) {
        return item.copyWith(
            status: ReseedStatus.match, release: r, metainfo: metainfo, match: match, selected: true);
      }
    }
    return item.copyWith(
        status: ReseedStatus.mismatch,
        release: sameSize.first,
        detail: () => 'Même taille, mais pas les mêmes fichiers ou données');
  }

  /// Ajoute les correspondances cochées à Transmission, sur place :
  /// [folder] (le dossier choisi) est vu par Transmission comme
  /// [transmissionFolder]. Renvoie le nombre de torrents repartagés.
  Future<int> addSelected({required String folder, required String transmissionFolder}) async {
    final client = ref.read(transmissionProvider);
    if (client == null) {
      state = state.copyWith(error: () => 'Configure Transmission dans les Réglages');
      return 0;
    }
    state = state.copyWith(adding: true, error: () => null);
    var added = 0;
    for (final item in state.selected) {
      if (!ref.mounted) return added;
      try {
        if (await _add(client, item, folder: folder, transmissionFolder: transmissionFolder)) added++;
      } on TransmissionException catch (e) {
        _set(item.key, (i) => i.copyWith(status: ReseedStatus.error, detail: () => e.message));
      }
    }
    if (!ref.mounted) return added;
    state = state.copyWith(adding: false);
    await ref.read(torrentsProvider.notifier).refresh(full: true);
    return added;
  }

  /// En pause dans le dossier parent (vu par Transmission), renommé si le
  /// nom diffère de celui du torrent, vérifié ; relancé seulement si les
  /// données sont toutes là.
  Future<bool> _add(TransmissionClient client, ReseedItem item,
      {required String folder, required String transmissionFolder}) async {
    final match = item.match!;
    final content = TorrentContent.parse(item.metainfo!);
    final root = File(match.root);
    final parent = transmissionPath(root.parent.path, folder: folder, transmissionFolder: transmissionFolder);
    final name = root.uri.pathSegments.where((p) => p.isNotEmpty).last;
    _set(item.key, (i) => i.copyWith(status: ReseedStatus.verifying, detail: () => parent));
    final result = await client.addTorrentWithHash(
      metainfo: item.metainfo,
      options: AddOptions(downloadDir: parent, paused: true, labels: const ['reseed']),
    );
    final ids = (await client.torrentGet(['id'], ids: [?result.hash])).torrents
        .map((t) => (t['id'] as num).toInt())
        .toList();
    if (ids.isEmpty) throw const TransmissionException('Torrent ajouté introuvable');
    if (name != content.name) await client.renamePath(ids.first, content.name, name);
    await client.action('torrent-verify', ids);
    // Vérification : en attente (1) ou en cours (2) ; ensuite, la part des
    // données présentes.
    double done = 0;
    for (var tries = 0; tries < 900; tries++) {
      await Future<void>.delayed(pollEvery);
      if (!ref.mounted) return false;
      final t = (await client.torrentGet(['id', 'status', 'percentDone', 'recheckProgress'], ids: ids))
          .torrents
          .firstOrNull;
      if (t == null) throw const TransmissionException('Torrent retiré pendant la vérification');
      final status = (t['status'] as num?)?.toInt() ?? 0;
      done = (t['percentDone'] as num?)?.toDouble() ?? 0;
      if (status == 1 || status == 2) {
        final progress = ((t['recheckProgress'] as num?)?.toDouble() ?? 0) * 100;
        _set(item.key, (i) => i.copyWith(detail: () => 'Vérification ${progress.round()} % · $parent'));
        continue;
      }
      break;
    }
    if (done < 1) {
      // Fichiers introuvables au chemin donné, ou abîmés : on ne relance pas
      // (il retéléchargerait tout).
      _set(
          item.key,
          (i) => i.copyWith(
              status: ReseedStatus.incomplete,
              selected: false,
              detail: () => '${(done * 100).toStringAsFixed(1)} % trouvé dans $parent : '
                  'laissé en pause. Vérifie le dossier vu par Transmission.'));
      return false;
    }
    await client.action('torrent-start', ids);
    _set(item.key, (i) => i.copyWith(status: ReseedStatus.added, selected: false, detail: () => parent));
    return true;
  }
}

final reseedProvider = NotifierProvider<ReseedNotifier, ReseedState>(ReseedNotifier.new);

/// Transmission tourne sur cet appareil : il voit le dossier choisi tel quel.
bool reseedLocalClient(TransmissionClient? client) =>
    client != null && PalliativeNotifier.isLocalClient(client);
