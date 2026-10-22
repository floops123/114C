import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/astra.dart';
import '../api/content_kind.dart';
import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/bencode.dart';
import '../core/preferences.dart';
import 'torrents.dart';

// Cross-seed : partager sur un autre tracker des fichiers déjà téléchargés.
// Pour chaque torrent terminé de Transmission, on cherche la même release sur
// les autres trackers configurés (par nom), on garde les candidats de même
// taille à l'octet près, puis on compare fichier par fichier le .torrent
// candidat avec le torrent local. Une correspondance s'ajoute à Transmission
// dans le dossier existant : il vérifie les données et partage aussitôt.

enum CrossSeedStatus {
  waiting('En attente'),
  searching('Recherche…'),
  match('À ajouter'),
  added('Ajouté'),
  present('Déjà partagé'),
  mismatch('Fichiers différents'),
  notFound('Introuvable'),
  error('Erreur');

  const CrossSeedStatus(this.label);
  final String label;

  /// Résultats mémorisés d'une analyse à l'autre.
  bool get cached => this == notFound || this == mismatch || this == present;
}

class CrossSeedItem {
  const CrossSeedItem({
    required this.torrentId,
    required this.hash,
    required this.name,
    required this.size,
    required this.downloadDir,
    required this.target,
    this.source,
    this.status = CrossSeedStatus.waiting,
    this.candidate,
    this.metainfo,
    this.detail,
  });

  final int torrentId;
  final String hash;
  final String name;
  final int size;
  final String downloadDir;

  /// Tracker d'origine (null : autre tracker ou torrent public).
  final Tracker? source;
  final Tracker target;
  final CrossSeedStatus status;
  final Release? candidate;

  /// .torrent du candidat, conservé pour l'ajout.
  final Uint8List? metainfo;
  final String? detail;

  String get key => '$hash|${target.name}';

  CrossSeedItem copyWith({
    CrossSeedStatus? status,
    Release? candidate,
    Uint8List? metainfo,
    String? detail,
  }) =>
      CrossSeedItem(
        torrentId: torrentId,
        hash: hash,
        name: name,
        size: size,
        downloadDir: downloadDir,
        source: source,
        target: target,
        status: status ?? this.status,
        candidate: candidate ?? this.candidate,
        metainfo: metainfo ?? this.metainfo,
        detail: detail ?? this.detail,
      );
}

class CrossSeedState {
  const CrossSeedState({
    this.items = const [],
    this.running = false,
    this.done = 0,
    this.skipped = 0,
    this.error,
  });

  final List<CrossSeedItem> items;
  final bool running;

  /// Analyses terminées dans la passe en cours, et torrents ignorés car
  /// analysés récemment.
  final int done;
  final int skipped;
  final String? error;

  int count(CrossSeedStatus s) => items.where((i) => i.status == s).length;

  CrossSeedState copyWith({
    List<CrossSeedItem>? items,
    bool? running,
    int? done,
    int? skipped,
    String? Function()? error,
  }) =>
      CrossSeedState(
        items: items ?? this.items,
        running: running ?? this.running,
        done: done ?? this.done,
        skipped: skipped ?? this.skipped,
        error: error != null ? error() : this.error,
      );
}

/// Résultats mémorisés (introuvable, différent, déjà partagé) : un torrent
/// n'est pas recherché à nouveau avant [CrossSeedNotifier.recheckAfter].
abstract class CrossSeedCache {
  Map<String, ({CrossSeedStatus status, DateTime at})> load();
  void save(Map<String, ({CrossSeedStatus status, DateTime at})> entries);
}

class PrefsCrossSeedCache implements CrossSeedCache {
  PrefsCrossSeedCache(this._prefs);
  final SharedPreferencesWithCache _prefs;
  static const key = 'crossSeed';

  @override
  Map<String, ({CrossSeedStatus status, DateTime at})> load() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return {};
      final statuses = CrossSeedStatus.values.asNameMap();
      return {
        for (final MapEntry(key: k, value: v)
            in (jsonDecode(raw) as Map<String, dynamic>).entries)
          if (statuses[(v as Map)['s']] != null)
            k: (
              status: statuses[v['s']]!,
              at: DateTime.tryParse(v['t'] as String? ?? '') ?? DateTime(2000),
            ),
      };
    } on Object {
      return {};
    }
  }

  @override
  void save(Map<String, ({CrossSeedStatus status, DateTime at})> entries) =>
      _prefs.setString(
          key,
          jsonEncode({
            for (final MapEntry(:key, :value) in entries.entries)
              key: {'s': value.status.name, 't': value.at.toIso8601String()},
          }));
}

class MemoryCrossSeedCache implements CrossSeedCache {
  var _entries = <String, ({CrossSeedStatus status, DateTime at})>{};
  @override
  Map<String, ({CrossSeedStatus status, DateTime at})> load() => {..._entries};
  @override
  void save(Map<String, ({CrossSeedStatus status, DateTime at})> entries) =>
      _entries = {...entries};
}

final crossSeedCacheProvider = Provider<CrossSeedCache>((ref) {
  try {
    return PrefsCrossSeedCache(ref.watch(sharedPrefsProvider));
  } on Object {
    return MemoryCrossSeedCache(); // Préférences non initialisées (tests).
  }
});

/// Sens de cross-seed choisis : trackers d'origine et trackers de
/// destination exclus (un tracker ajouté plus tard est donc inclus d'office).
/// `null` dans [offFrom] : les torrents d'autres trackers ou publics.
class CrossSeedDirections {
  const CrossSeedDirections({this.offFrom = const {}, this.offTo = const {}});
  final Set<Tracker?> offFrom;
  final Set<Tracker> offTo;

  bool from(Tracker? source) => !offFrom.contains(source);
  bool to(Tracker target) => !offTo.contains(target);
}

class CrossSeedDirectionsNotifier extends Notifier<CrossSeedDirections> {
  static const key = 'crossSeedDirections';
  static const _other = 'other';

  SharedPreferencesWithCache? get _prefs {
    try {
      return ref.read(sharedPrefsProvider);
    } on Object {
      return null; // Préférences non initialisées (tests).
    }
  }

  @override
  CrossSeedDirections build() {
    try {
      final raw = _prefs?.getString(key);
      if (raw == null) return const CrossSeedDirections();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final trackers = Tracker.values.asNameMap();
      return CrossSeedDirections(
        offFrom: {
          for (final n in (json['from'] as List? ?? const []).cast<String>())
            if (n == _other) null else ?trackers[n],
        },
        offTo: {
          for (final n in (json['to'] as List? ?? const []).cast<String>())
            ?trackers[n],
        },
      );
    } on Object {
      return const CrossSeedDirections();
    }
  }

  void toggleFrom(Tracker? source) => _save(CrossSeedDirections(
      offFrom: {...state.offFrom}..toggle(source), offTo: state.offTo));

  void toggleTo(Tracker target) => _save(CrossSeedDirections(
      offFrom: state.offFrom, offTo: {...state.offTo}..toggle(target)));

  void _save(CrossSeedDirections d) {
    state = d;
    _prefs?.setString(
        key,
        jsonEncode({
          'from': [for (final t in d.offFrom) t?.name ?? _other],
          'to': [for (final t in d.offTo) t.name],
        }));
  }
}

extension<T> on Set<T> {
  void toggle(T value) {
    if (!remove(value)) add(value);
  }
}

final crossSeedDirectionsProvider =
    NotifierProvider<CrossSeedDirectionsNotifier, CrossSeedDirections>(
        CrossSeedDirectionsNotifier.new);

/// Pause entre deux requêtes vers un tracker (quota C411 : 120 / min).
final crossSeedDelayProvider =
    Provider<Duration>((ref) => const Duration(milliseconds: 1100));

const _extensions = {
  'mkv', 'mp4', 'avi', 'm4v', 'ts', 'iso', 'zip', 'rar', 'epub', 'pdf',
  'cbz', 'cbr', 'mp3', 'flac', 'm4a', 'm4b',
};

/// Nom à rechercher : celui du torrent, sans extension de fichier.
String crossSeedQuery(String name) {
  final dot = name.lastIndexOf('.');
  if (dot > 0 && _extensions.contains(name.substring(dot + 1).toLowerCase())) {
    return name.substring(0, dot);
  }
  return name;
}

/// Mêmes fichiers (chemin et taille), dans n'importe quel ordre.
bool sameFiles(List<(String, int)> a, List<(String, int)> b) {
  if (a.length != b.length) return false;
  final left = {for (final f in a) f};
  return b.every(left.contains);
}

class CrossSeedNotifier extends Notifier<CrossSeedState> {
  static const recheckAfter = Duration(days: 7);
  static const label = 'cross-seed';

  bool _stop = false;

  @override
  CrossSeedState build() => const CrossSeedState();

  void stop() => _stop = true;

  void _set(String key, CrossSeedItem Function(CrossSeedItem) change) {
    state = state.copyWith(items: [
      for (final i in state.items) i.key == key ? change(i) : i,
    ]);
  }

  /// Analyse les torrents terminés vers les autres trackers configurés, dans
  /// les sens choisis ([crossSeedDirectionsProvider]).
  /// [force] : ignore les résultats mémorisés.
  Future<void> scan({bool force = false}) async {
    if (state.running) return;
    final client = ref.read(transmissionProvider);
    final trackers = ref.read(trackersProvider);
    if (client == null || trackers.isEmpty) {
      state = state.copyWith(
          error: () => 'Configure Transmission et au moins un tracker');
      return;
    }
    _stop = false;
    state = const CrossSeedState(running: true);

    final List<Map<String, dynamic>> torrents;
    try {
      torrents = (await client.torrentGet([
        'id', 'name', 'hashString', 'totalSize', 'downloadDir',
        'percentDone', 'trackers',
      ]))
          .torrents;
    } on TransmissionException catch (e) {
      state = state.copyWith(running: false, error: () => e.message);
      return;
    }
    if (!ref.mounted) return;

    final present = {
      for (final t in torrents) (t['hashString'] as String).toLowerCase(),
    };
    final directions = ref.read(crossSeedDirectionsProvider);
    final cache = ref.read(crossSeedCacheProvider);
    final memory = cache.load();
    final now = DateTime.now();
    var skipped = 0;
    final items = <CrossSeedItem>[];
    for (final t in torrents) {
      if (((t['percentDone'] as num?) ?? 0) < 1) continue;
      final announces = [
        for (final tr in (t['trackers'] as List? ?? const []).whereType<Map>())
          '${tr['announce']}',
      ];
      final source = Tracker.fromAnnounces(announces);
      if (!directions.from(source)) continue;
      for (final target in trackers.keys) {
        if (target == source || !directions.to(target)) continue;
        final item = CrossSeedItem(
          torrentId: (t['id'] as num).toInt(),
          hash: (t['hashString'] as String).toLowerCase(),
          name: t['name'] as String? ?? '',
          size: (t['totalSize'] as num?)?.toInt() ?? 0,
          downloadDir: t['downloadDir'] as String? ?? '',
          source: source,
          target: target,
        );
        final known = memory[item.key];
        if (!force &&
            known != null &&
            (known.status == CrossSeedStatus.present ||
                now.difference(known.at) < recheckAfter)) {
          skipped++;
          continue;
        }
        items.add(item);
      }
    }
    state = CrossSeedState(items: items, running: true, skipped: skipped);

    // AstraTorrent n'a pas de recherche : tous ses torrents sont soumis d'un
    // coup à son scanner, par lots, avant la vérification une à une.
    final astraItems = [
      for (final i in items)
        if (i.target == Tracker.astra) i,
    ];
    var astra = <String, Release>{};
    String? astraError;
    if (astraItems.isNotEmpty) {
      for (final i in astraItems) {
        _set(i.key, (i) => i.copyWith(status: CrossSeedStatus.searching));
      }
      try {
        astra = await (trackers[Tracker.astra]! as AstraApi).bulkScan([
          for (final i in astraItems) (name: i.name, size: i.size, hash: i.hash),
        ]);
      } on TrackerException catch (e) {
        astraError = e.message;
      }
      if (!ref.mounted) return;
    }

    final delay = ref.read(crossSeedDelayProvider);
    for (final item in items) {
      if (_stop || !ref.mounted) break;
      _set(item.key, (i) => i.copyWith(status: CrossSeedStatus.searching));
      final api = trackers[item.target]!;
      final CrossSeedItem result;
      if (item.target != Tracker.astra) {
        result = await _check(item, api, client, present);
      } else if (astraError != null) {
        result = item.copyWith(status: CrossSeedStatus.error, detail: astraError);
      } else if (astra[item.hash] case final candidate?) {
        result = await _verify(item, api, client, present, [candidate]);
      } else {
        result = item.copyWith(
            status: CrossSeedStatus.notFound, detail: 'Aucune correspondance');
      }
      if (!ref.mounted) return;
      _set(item.key, (_) => result);
      if (result.status.cached) {
        memory[item.key] = (status: result.status, at: DateTime.now());
        cache.save(memory);
      }
      state = state.copyWith(done: state.done + 1);
      // Sans candidat, AstraTorrent n'a pas été interrogé pour ce torrent.
      if (item.target != Tracker.astra || result.candidate != null) {
        await Future<void>.delayed(delay);
      }
    }
    if (ref.mounted) state = state.copyWith(running: false);
  }

  Future<CrossSeedItem> _check(CrossSeedItem item, TrackerApi api,
      TransmissionClient client, Set<String> present) async {
    try {
      final page = await api.releases(
          query: crossSeedQuery(item.name), perPage: 20);
      final sameSize = page.items.where((r) => r.size == item.size).toList();
      if (sameSize.isEmpty) {
        return item.copyWith(
          status: CrossSeedStatus.notFound,
          detail: page.items.isEmpty
              ? 'Aucun résultat'
              : '${page.items.length} résultat(s), aucun de même taille',
        );
      }
      return await _verify(item, api, client, present, sameSize);
    } on TrackerException catch (e) {
      return item.copyWith(status: CrossSeedStatus.error, detail: e.message);
    }
  }

  /// Compare fichier par fichier les candidats avec le torrent local.
  Future<CrossSeedItem> _verify(CrossSeedItem item, TrackerApi api,
      TransmissionClient client, Set<String> present,
      List<Release> sameSize) async {
    try {
      final already = sameSize.where((r) => present.contains(r.infoHash));
      if (already.isNotEmpty) {
        return item.copyWith(
            status: CrossSeedStatus.present, candidate: already.first);
      }
      final local = await client.torrentGet(['files'], ids: [item.torrentId]);
      final localFiles = [
        for (final f in (local.torrents.firstOrNull?['files'] as List? ?? const [])
            .whereType<Map>())
          ('${f['name']}', (f['length'] as num).toInt()),
      ];
      String? why;
      for (final candidate in sameSize) {
        final bytes = await api.downloadTorrent(candidate);
        final remote = TorrentContent.parse(bytes);
        if (sameFiles(localFiles, remote.files)) {
          return item.copyWith(
              status: CrossSeedStatus.match,
              candidate: candidate,
              metainfo: bytes);
        }
        why = remote.name != item.name
            ? 'Même taille, nom différent : ${remote.name}'
            : 'Même taille, fichiers différents';
      }
      return item.copyWith(
          status: CrossSeedStatus.mismatch,
          candidate: sameSize.first,
          detail: why);
    } on TrackerException catch (e) {
      return item.copyWith(status: CrossSeedStatus.error, detail: e.message);
    } on TransmissionException catch (e) {
      return item.copyWith(status: CrossSeedStatus.error, detail: e.message);
    } on FormatException catch (e) {
      return item.copyWith(
          status: CrossSeedStatus.error, detail: '.torrent illisible : ${e.message}');
    }
  }

  /// Ajoute la correspondance dans le dossier des données existantes.
  Future<String?> add(CrossSeedItem item) async {
    final client = ref.read(transmissionProvider);
    if (client == null || item.metainfo == null) return 'Rien à ajouter';
    try {
      final kind = switch (item.candidate) {
        final candidate? => ContentKind.of(candidate),
        null => ContentKind.ofName(item.name),
      };
      final added = await client.addTorrent(
        metainfo: item.metainfo,
        options: AddOptions(downloadDir: item.downloadDir, labels: [label, ...kind.labels]),
      );
      _set(
          item.key,
          (i) => i.copyWith(
              status: added ? CrossSeedStatus.added : CrossSeedStatus.present));
      await ref.read(torrentsProvider.notifier).refresh(full: true);
      return null;
    } on TransmissionException catch (e) {
      return e.message;
    }
  }

  /// Ajoute toutes les correspondances ; renvoie le nombre d'ajouts.
  Future<int> addAll() async {
    var n = 0;
    for (final item in state.items
        .where((i) => i.status == CrossSeedStatus.match)
        .toList()) {
      if (await add(item) == null) n++;
    }
    return n;
  }
}

final crossSeedProvider =
    NotifierProvider<CrossSeedNotifier, CrossSeedState>(CrossSeedNotifier.new);
