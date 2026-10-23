import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/astra.dart';
import '../api/content_kind.dart';
import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/preferences.dart';
import 'cross_seed.dart' show crossSeedQuery;
import 'torrents.dart';

// Rangement par catégorie des torrents déjà dans Transmission : chacun reçoit
// l'étiquette de sa catégorie, puis ses fichiers vont dans le dossier de
// celle-ci sous le dossier de téléchargement du serveur. Transmission
// déplace lui-même les données (`torrent-set-location`) : même torrent, le
// seed reprend à l'arrivée.
//
// La catégorie vient, dans l'ordre : d'une étiquette de catégorie déjà posée,
// du tracker d'origine (recherche par nom, puis la même empreinte), à défaut
// du nom. Les torrents qui partagent leurs fichiers (cross-seed, reseed :
// même dossier, même nom) forment un groupe, déplacé d'un bloc.

/// D'où vient la catégorie retenue, du plus sûr au moins sûr.
enum KindSource {
  manual('Choisie'),
  label('Étiquette'),
  tracker('Tracker'),
  name('D’après le nom');

  const KindSource(this.title);
  final String title;
}

/// Un torrent de Transmission à ranger.
class OrganizeTorrent {
  const OrganizeTorrent({
    required this.id,
    required this.hash,
    required this.name,
    required this.downloadDir,
    required this.labels,
    this.status = 0,
    this.size = 0,
    this.source,
  });

  final int id;
  final String hash;
  final String name;
  final String downloadDir;
  final List<String> labels;
  final int status;
  final int size;

  /// Tracker d'origine, d'après les adresses d'annonce.
  final Tracker? source;

  /// Mêmes fichiers sur le disque : même dossier, même nom.
  String get groupKey => '${trimDir(downloadDir)}\u0000$name';

  /// Vérification en cours ou en attente : pas de déplacement.
  bool get checking => status == 1 || status == 2;
}

/// Catégorie posée par une étiquette (« Films »…), null s'il n'y en a pas.
ContentKind? kindOfLabels(Iterable<String> labels) {
  for (final k in ContentKind.values) {
    if (k != ContentKind.other && labels.contains(k.plural)) return k;
  }
  return null;
}

/// Étiquettes d'un torrent rangé en [kind] : les autres catégories retirées,
/// la sienne ajoutée, le reste (cross-seed, reseed…) gardé.
List<String> relabel(List<String> labels, ContentKind kind) {
  final categories = {for (final k in ContentKind.values) k.plural};
  return {
    for (final l in labels)
      if (!categories.contains(l)) l,
    ...kind.labels,
  }.toList();
}

/// Dossier sans séparateur final (la racine « / » reste telle quelle).
String trimDir(String dir) =>
    dir.length > 1 && (dir.endsWith('/') || dir.endsWith(r'\'))
        ? dir.substring(0, dir.length - 1)
        : dir;

/// [dir] est [root] ou l'un de ses sous-dossiers.
bool insideRoot(String dir, String root) {
  final d = trimDir(dir);
  final r = trimDir(root);
  return d == r || d.startsWith('$r/') || d.startsWith('$r\\');
}

enum OrganizeStep { idle, working, done, failed }

/// Torrents rangés ensemble (ils partagent leurs fichiers).
class OrganizeGroup {
  const OrganizeGroup({
    required this.key,
    required this.torrents,
    required this.kind,
    required this.from,
    this.step = OrganizeStep.idle,
    this.detail,
  });

  final String key;
  final List<OrganizeTorrent> torrents;
  final ContentKind kind;
  final KindSource from;
  final OrganizeStep step;
  final String? detail;

  OrganizeTorrent get first => torrents.first;
  String get name => first.name;
  String get downloadDir => first.downloadDir;
  Tracker? get source => torrents.map((t) => t.source).nonNulls.firstOrNull;

  /// Une étiquette à poser ou à corriger.
  bool get needsLabels =>
      torrents.any((t) => !_sameLabels(t.labels, relabel(t.labels, kind)));

  /// Dossier visé sous [root] ; null pour un contenu non reconnu (on ne le
  /// déplace pas).
  String? target(String? root) =>
      root == null || root.isEmpty || kind == ContentKind.other
          ? null
          : categoryFolder(root, kind);

  bool needsMove(String? root) {
    final t = target(root);
    return t != null && torrents.any((x) => trimDir(x.downloadDir) != t);
  }

  OrganizeGroup copyWith({
    List<OrganizeTorrent>? torrents,
    ContentKind? kind,
    KindSource? from,
    OrganizeStep? step,
    String? Function()? detail,
  }) =>
      OrganizeGroup(
        key: key,
        torrents: torrents ?? this.torrents,
        kind: kind ?? this.kind,
        from: from ?? this.from,
        step: step ?? this.step,
        detail: detail == null ? this.detail : detail(),
      );
}

bool _sameLabels(List<String> a, List<String> b) =>
    a.length == b.length && a.toSet().containsAll(b);

class OrganizeState {
  const OrganizeState({
    this.groups = const [],
    this.selected = const {},
    this.root,
    this.scanning = false,
    this.lookedUp = 0,
    this.toLookUp = 0,
    this.applying = false,
    this.applied = 0,
    this.toApply = 0,
    this.error,
  });

  final List<OrganizeGroup> groups;

  /// Clés des groupes cochés.
  final Set<String> selected;

  /// Dossier de téléchargement du serveur.
  final String? root;
  final bool scanning;
  final int lookedUp;
  final int toLookUp;
  final bool applying;
  final int applied;
  final int toApply;
  final String? error;

  bool get busy => scanning || applying;

  OrganizeState copyWith({
    List<OrganizeGroup>? groups,
    Set<String>? selected,
    String? Function()? root,
    bool? scanning,
    int? lookedUp,
    int? toLookUp,
    bool? applying,
    int? applied,
    int? toApply,
    String? Function()? error,
  }) =>
      OrganizeState(
        groups: groups ?? this.groups,
        selected: selected ?? this.selected,
        root: root == null ? this.root : root(),
        scanning: scanning ?? this.scanning,
        lookedUp: lookedUp ?? this.lookedUp,
        toLookUp: toLookUp ?? this.toLookUp,
        applying: applying ?? this.applying,
        applied: applied ?? this.applied,
        toApply: toApply ?? this.toApply,
        error: error == null ? this.error : error(),
      );
}

/// Catégories trouvées sur les trackers, par empreinte (`-` : introuvable),
/// pour ne pas réinterroger les trackers à chaque relevé.
abstract class OrganizeCache {
  Map<String, String> load();
  void save(Map<String, String> kinds);
}

class PrefsOrganizeCache implements OrganizeCache {
  PrefsOrganizeCache(this._prefs);
  static const key = 'organize';
  final SharedPreferencesWithCache _prefs;

  @override
  Map<String, String> load() {
    try {
      return (jsonDecode(_prefs.getString(key) ?? '{}') as Map).cast<String, String>();
    } on Object {
      return {};
    }
  }

  @override
  void save(Map<String, String> kinds) => _prefs.setString(key, jsonEncode(kinds));
}

class MemoryOrganizeCache implements OrganizeCache {
  Map<String, String> kinds = {};
  @override
  Map<String, String> load() => {...kinds};
  @override
  void save(Map<String, String> kinds) => this.kinds = {...kinds};
}

final organizeCacheProvider = Provider<OrganizeCache>((ref) {
  try {
    return PrefsOrganizeCache(ref.watch(sharedPrefsProvider));
  } on Object {
    return MemoryOrganizeCache(); // Préférences non initialisées (tests).
  }
});

/// Écart entre deux relevés de l'avancement d'un déplacement.
final organizePollProvider = Provider<Duration>((ref) => const Duration(seconds: 2));

class OrganizeNotifier extends Notifier<OrganizeState> {
  bool _stop = false;

  @override
  OrganizeState build() => const OrganizeState();

  void stop() => _stop = true;

  /// Relève les torrents de Transmission et leur catégorie. [force] :
  /// réinterroge les trackers même pour les torrents déjà cherchés.
  Future<void> scan({bool force = false}) async {
    if (state.busy) return;
    final client = ref.read(transmissionProvider);
    if (client == null) {
      state = state.copyWith(error: () => 'Configure Transmission dans les réglages');
      return;
    }
    _stop = false;
    state = const OrganizeState(scanning: true);

    final List<OrganizeTorrent> torrents;
    final String? root;
    try {
      root = (await client.sessionGet())['download-dir'] as String?;
      torrents = [
        for (final t in (await client.torrentGet([
          'id', 'name', 'hashString', 'downloadDir', 'labels', 'status',
          'totalSize', 'trackers',
        ]))
            .torrents)
          OrganizeTorrent(
            id: (t['id'] as num).toInt(),
            hash: (t['hashString'] as String).toLowerCase(),
            name: t['name'] as String? ?? '',
            downloadDir: t['downloadDir'] as String? ?? '',
            labels: (t['labels'] as List? ?? const []).whereType<String>().toList(),
            status: (t['status'] as num?)?.toInt() ?? 0,
            size: (t['totalSize'] as num?)?.toInt() ?? 0,
            source: Tracker.fromAnnounces([
              for (final tr in (t['trackers'] as List? ?? const []).whereType<Map>())
                '${tr['announce']}',
            ]),
          ),
      ];
    } on TransmissionException catch (e) {
      if (ref.mounted) state = state.copyWith(scanning: false, error: () => e.message);
      return;
    }
    if (!ref.mounted) return;

    final cache = ref.read(organizeCacheProvider);
    final memory = force ? <String, String>{} : cache.load();
    final kinds = <String, (ContentKind, KindSource)>{};
    final pending = <OrganizeTorrent>[];
    final trackers = ref.read(trackersProvider);
    for (final t in torrents) {
      final labelled = kindOfLabels(t.labels);
      final cached = ContentKind.values.asNameMap()[memory[t.hash]];
      if (labelled != null) {
        kinds[t.hash] = (labelled, KindSource.label);
      } else if (cached != null) {
        kinds[t.hash] = (cached, KindSource.tracker);
      } else {
        kinds[t.hash] = (ContentKind.ofName(t.name), KindSource.name);
        if (trackers.containsKey(t.source) && !memory.containsKey(t.hash)) pending.add(t);
      }
    }
    state = state.copyWith(
      root: () => root,
      groups: _group(torrents, kinds),
      toLookUp: pending.length,
    );
    _selectDefault();

    // Sur le tracker d'origine : AstraTorrent (sans recherche) d'un coup par
    // son scanner, les autres un par un.
    final astra = [for (final t in pending) if (t.source == Tracker.astra) t];
    if (astra.isNotEmpty) {
      try {
        final found = await (trackers[Tracker.astra]! as AstraApi).bulkScan([
          for (final t in astra) (name: t.name, size: t.size, hash: t.hash),
        ]);
        for (final t in astra) {
          _learn(t, found[t.hash], memory);
        }
      } on TrackerException {
        // Réessayé au prochain relevé.
      }
      if (!ref.mounted) return;
      state = state.copyWith(lookedUp: state.lookedUp + astra.length);
    }
    for (final t in pending) {
      if (t.source == Tracker.astra) continue;
      if (_stop || !ref.mounted) break;
      try {
        final page = await trackers[t.source]!.releases(query: crossSeedQuery(t.name), perPage: 20);
        final match = page.items.where((r) => r.infoHash == t.hash).firstOrNull ??
            page.items.where((r) => r.infoHash == null && r.name == t.name && r.size == t.size).firstOrNull;
        _learn(t, match, memory);
      } on TrackerException {
        // Réessayé au prochain relevé.
      }
      if (!ref.mounted) return;
      state = state.copyWith(lookedUp: state.lookedUp + 1);
    }
    cache.save(memory);
    if (ref.mounted) state = state.copyWith(scanning: false);
  }

  /// Catégorie trouvée (ou non) sur le tracker pour [t].
  void _learn(OrganizeTorrent t, Release? release, Map<String, String> memory) {
    if (release == null) {
      memory[t.hash] = '-';
      return;
    }
    final kind = ContentKind.of(release);
    memory[t.hash] = kind.name;
    final groups = [
      for (final g in state.groups)
        if (g.torrents.contains(t) && KindSource.tracker.index < g.from.index)
          g.copyWith(kind: kind, from: KindSource.tracker)
        else
          g,
    ];
    state = state.copyWith(groups: groups);
    _selectDefault();
  }

  /// Groupes par fichiers partagés ; la catégorie la plus sûre de leurs
  /// torrents l'emporte. Ceux qui ont le plus à faire d'abord.
  List<OrganizeGroup> _group(
      List<OrganizeTorrent> torrents, Map<String, (ContentKind, KindSource)> kinds) {
    final byKey = <String, List<OrganizeTorrent>>{};
    for (final t in torrents) {
      (byKey[t.groupKey] ??= []).add(t);
    }
    final groups = [
      for (final MapEntry(:key, :value) in byKey.entries)
        () {
          final best = [for (final t in value) kinds[t.hash]!]
            ..sort((a, b) => a.$2.index.compareTo(b.$2.index));
          return OrganizeGroup(key: key, torrents: value, kind: best.first.$1, from: best.first.$2);
        }(),
    ];
    return groups..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Cochés d'office : les groupes à étiqueter ou à déplacer, rangés sous
  /// le dossier de téléchargement (un dossier à part, comme une
  /// médiathèque partagée en reseed, reste au choix).
  void _selectDefault() {
    final root = state.root;
    state = state.copyWith(selected: {
      for (final g in state.groups)
        if (g.kind != ContentKind.other &&
            (g.needsLabels || g.needsMove(root)) &&
            root != null &&
            g.torrents.every((t) => insideRoot(t.downloadDir, root)))
          g.key,
    });
  }

  void toggle(String key) {
    final next = {...state.selected};
    next.contains(key) ? next.remove(key) : next.add(key);
    state = state.copyWith(selected: next);
  }

  void select(Iterable<String> keys) => state = state.copyWith(selected: {...keys});

  /// Catégorie choisie à la main pour un groupe.
  void setKind(String key, ContentKind kind) {
    state = state.copyWith(groups: [
      for (final g in state.groups)
        if (g.key == key)
          g.copyWith(kind: kind, from: KindSource.manual, step: OrganizeStep.idle, detail: () => null)
        else
          g,
    ]);
  }

  void _set(String key, OrganizeGroup Function(OrganizeGroup) change) {
    state = state.copyWith(groups: [
      for (final g in state.groups) g.key == key ? change(g) : g,
    ]);
  }

  /// Étiquette les groupes cochés et, avec [move], déplace leurs fichiers
  /// dans le dossier de leur catégorie, un groupe à la fois.
  Future<void> apply({required bool move}) async {
    final client = ref.read(transmissionProvider);
    if (client == null || state.busy) return;
    _stop = false;
    final root = state.root;
    final todo = [
      for (final g in state.groups)
        if (state.selected.contains(g.key) && g.kind != ContentKind.other) g,
    ];
    state = state.copyWith(applying: true, applied: 0, toApply: todo.length, error: () => null);
    for (final g in todo) {
      if (_stop || !ref.mounted) break;
      _set(g.key, (g) => g.copyWith(step: OrganizeStep.working, detail: () => null));
      final (ok, detail, moved) = await _apply(client, g, move ? root : null);
      if (!ref.mounted) return;
      _set(g.key, (g) => g.copyWith(
            step: ok ? OrganizeStep.done : OrganizeStep.failed,
            detail: () => detail,
            torrents: [
              for (final t in g.torrents)
                OrganizeTorrent(
                  id: t.id,
                  hash: t.hash,
                  name: t.name,
                  downloadDir: moved ?? t.downloadDir,
                  labels: relabel(t.labels, g.kind),
                  status: t.status,
                  size: t.size,
                  source: t.source,
                ),
            ],
          ));
      if (ok) state = state.copyWith(selected: {...state.selected}..remove(g.key));
      state = state.copyWith(applied: state.applied + 1);
    }
    if (!ref.mounted) return;
    state = state.copyWith(applying: false);
    await ref.read(torrentsProvider.notifier).refresh(full: true);
  }

  /// Étiquettes, puis déplacement vers le dossier de catégorie sous [root]
  /// (null : étiquettes seules). Renvoie la réussite, le détail et le
  /// nouveau dossier s'il a changé.
  Future<(bool, String?, String?)> _apply(
      TransmissionClient client, OrganizeGroup g, String? root) async {
    try {
      for (final t in g.torrents) {
        final labels = relabel(t.labels, g.kind);
        if (!_sameLabels(t.labels, labels)) await client.torrentSet([t.id], {'labels': labels});
      }
      final target = g.target(root);
      if (target == null || !g.needsMove(root)) return (true, null, null);
      if (g.torrents.any((t) => t.checking)) {
        return (false, 'Étiqueté ; vérification en cours, pas déplacé', null);
      }
      final ids = [for (final t in g.torrents) t.id];
      try {
        await client.setLocation(ids, target);
      } on TransmissionException {
        // Un déplacement entre deux disques peut retenir la réponse au-delà
        // du délai : l'avancement dira s'il a eu lieu.
      }
      return await _waitMoved(client, ids, target);
    } on TransmissionException catch (e) {
      return (false, e.message, null);
    }
  }

  /// Attend que Transmission ait fini de déplacer [ids] vers [target].
  Future<(bool, String?, String?)> _waitMoved(
      TransmissionClient client, List<int> ids, String target) async {
    final poll = ref.read(organizePollProvider);
    var failures = 0;
    while (!_stop && ref.mounted) {
      try {
        final now = (await client.torrentGet(['id', 'downloadDir', 'error', 'errorString'], ids: ids))
            .torrents;
        failures = 0;
        if (now.isNotEmpty && now.every((t) => trimDir('${t['downloadDir']}') == target)) {
          return (true, null, target);
        }
        // 3 : erreur locale (fichiers) ; 1 et 2 viennent du tracker.
        final broken = now.where((t) => t['error'] == 3).firstOrNull;
        if (broken != null) return (false, '${broken['errorString']}', null);
      } on TransmissionException catch (e) {
        // Serveur occupé par la copie : on insiste un peu.
        if (++failures >= 30) return (false, e.message, null);
      }
      await Future<void>.delayed(poll);
    }
    return (false, 'Arrêté avant la fin du déplacement (il continue sur le serveur)', null);
  }
}

final organizeProvider = NotifierProvider<OrganizeNotifier, OrganizeState>(OrganizeNotifier.new);
