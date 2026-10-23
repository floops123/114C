import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/content_kind.dart';
import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/bencode.dart';
import '../core/preferences.dart';
import 'cross_seed.dart';
import 'torrents.dart';

// Relance des torrents morts : on liste les sorties sans seeder d'un tracker
// (C411 par défaut) dans une catégorie, puis on cherche chacune sur les
// trackers choisis (même nom, même taille). La copie la plus seedée se
// télécharge depuis son tracker ; une fois terminée, le .torrent du tracker
// d'origine s'ajoute dans le même dossier : Transmission vérifie les données
// et la sortie morte retrouve un seeder.

enum ReviveStatus {
  waiting('En attente'),
  searching('Recherche…'),
  available('Disponible'),
  downloading('Téléchargement'),
  seeding('Repartagé'),
  noSeeders('Sans seeder ailleurs non plus'),
  notFound('Introuvable ailleurs'),
  present('Déjà dans Transmission'),
  mismatch('Fichiers différents'),
  error('Erreur');

  const ReviveStatus(this.label);
  final String label;
}

class ReviveItem {
  const ReviveItem({
    required this.release,
    this.status = ReviveStatus.waiting,
    this.candidate,
    this.hash,
    this.detail,
  });

  /// Sortie sans seeder, sur le tracker d'origine.
  final Release release;
  final ReviveStatus status;

  /// Même sortie sur un autre tracker (le plus seedé).
  final Release? candidate;

  /// Infohash de cette copie dans Transmission, une fois envoyée.
  final String? hash;
  final String? detail;

  String get key => release.id;

  ReviveItem copyWith({
    ReviveStatus? status,
    Release? candidate,
    String? hash,
    String? detail,
  }) =>
      ReviveItem(
        release: release,
        status: status ?? this.status,
        candidate: candidate ?? this.candidate,
        hash: hash ?? this.hash,
        detail: detail ?? this.detail,
      );
}

class ReviveState {
  const ReviveState({
    this.items = const [],
    this.running = false,
    this.listing = false,
    this.done = 0,
    this.error,
  });

  final List<ReviveItem> items;
  final bool running;

  /// Lecture des sorties mortes en cours (avant les recherches ailleurs).
  final bool listing;
  final int done;
  final String? error;

  int count(ReviveStatus s) => items.where((i) => i.status == s).length;

  ReviveState copyWith({
    List<ReviveItem>? items,
    bool? running,
    bool? listing,
    int? done,
    String? Function()? error,
  }) =>
      ReviveState(
        items: items ?? this.items,
        running: running ?? this.running,
        listing: listing ?? this.listing,
        done: done ?? this.done,
        error: error != null ? error() : this.error,
      );
}

/// Copie en cours de téléchargement, et le .torrent d'origine à ajouter
/// quand il sera terminé.
class PendingRevive {
  const PendingRevive(
      {required this.name, required this.metainfo, required this.at});
  final String name;
  final Uint8List metainfo;
  final DateTime at;
}

/// Torrents en attente de cross-seed vers leur tracker d'origine, par infohash
/// de la copie. Mémorisés
/// pour survivre à un redémarrage de l'application.
abstract class ReviveStore {
  Map<String, PendingRevive> load();
  void save(Map<String, PendingRevive> pending);
}

class PrefsReviveStore implements ReviveStore {
  PrefsReviveStore(this._prefs);
  final SharedPreferencesWithCache _prefs;
  static const key = 'revive';

  @override
  Map<String, PendingRevive> load() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return {};
      return {
        for (final MapEntry(key: k, value: v)
            in (jsonDecode(raw) as Map<String, dynamic>).entries)
          k: PendingRevive(
            name: (v as Map)['n'] as String? ?? '',
            metainfo: base64Decode(v['m'] as String),
            at: DateTime.tryParse(v['t'] as String? ?? '') ?? DateTime(2000),
          ),
      };
    } on Object {
      return {};
    }
  }

  @override
  void save(Map<String, PendingRevive> pending) => _prefs.setString(
      key,
      jsonEncode({
        for (final MapEntry(:key, :value) in pending.entries)
          key: {
            'n': value.name,
            'm': base64Encode(value.metainfo),
            't': value.at.toIso8601String(),
          },
      }));
}

class MemoryReviveStore implements ReviveStore {
  var _pending = <String, PendingRevive>{};
  @override
  Map<String, PendingRevive> load() => {..._pending};
  @override
  void save(Map<String, PendingRevive> pending) => _pending = {...pending};
}

final reviveStoreProvider = Provider<ReviveStore>((ref) {
  try {
    return PrefsReviveStore(ref.watch(sharedPrefsProvider));
  } on Object {
    return MemoryReviveStore(); // Préférences non initialisées (tests).
  }
});

/// Catégories d'un tracker (indépendamment de celui affiché dans Sorties).
final trackerCategoriesProvider =
    FutureProvider.family<List<Category>, Tracker>((ref, tracker) async {
  final api = ref.watch(trackersProvider)[tracker];
  return api == null ? const [] : api.categories();
});

class ReviveNotifier extends Notifier<ReviveState> {
  static const perPage = 50;

  /// Sans tri par seeders côté tracker (Torznab), on parcourt au plus ces
  /// pages des dernières sorties.
  static const maxUnsortedPages = 20;

  /// Un torrent en attente absent de Transmission depuis ce délai a été
  /// supprimé : on l'oublie.
  static const forgetAfter = Duration(minutes: 5);

  bool _stop = false;
  final _adding = <String>{};
  var _pending = <String, PendingRevive>{};

  @override
  ReviveState build() {
    _pending = ref.read(reviveStoreProvider).load();
    // Surveille les copies téléchargées pour passer en cross-seed dès la fin.
    ref.listen(torrentsProvider, (_, next) => _checkPending(next));
    return const ReviveState();
  }

  void stop() => _stop = true;

  void _set(String key, ReviveItem Function(ReviveItem) change) {
    state = state.copyWith(items: [
      for (final i in state.items) i.key == key ? change(i) : i,
    ]);
  }

  /// Sorties sans seeder de [deadOn] dans la catégorie, cherchées une à une
  /// sur [searchOn]. [limit] null : toutes.
  Future<void> scan({
    required Tracker deadOn,
    required List<Tracker> searchOn,
    int? categoryId,
    int? subcategoryId,
    int? limit,
  }) async {
    if (state.running) return;
    final trackers = ref.read(trackersProvider);
    final origin = trackers[deadOn];
    final sources = [
      for (final t in searchOn)
        if (t != deadOn) ?trackers[t],
    ];
    if (origin == null || sources.isEmpty) {
      state = state.copyWith(
          error: () => origin == null
              ? 'Configure ${deadOn.label} dans les réglages'
              : 'Choisis au moins un tracker où chercher');
      return;
    }
    // Sans tri serveur, les sorties arrivent par date : pas d'arrêt anticipé.
    final sorted = origin.serverSorts.contains(ReleaseSort.seeders);
    _stop = false;
    state = const ReviveState(running: true, listing: true);
    final delay = ref.read(crossSeedDelayProvider);

    // Tri par seeders croissants : les sorties sans seeder viennent d'abord,
    // on s'arrête à la première qui en a.
    final dead = <Release>[];
    try {
      for (var page = 1;; page++) {
        final result = await origin.releases(
          page: page,
          perPage: perPage,
          categoryId: categoryId,
          subcategoryId: subcategoryId,
          sort: ReleaseSort.seeders,
          ascending: true,
        );
        if (!ref.mounted) return;
        final zero = result.items.where((r) => r.seeders == 0);
        dead.addAll(zero);
        state = state.copyWith(items: [
          for (final r in dead.take(limit ?? dead.length)) ReviveItem(release: r),
        ]);
        if (_stop ||
            (limit != null && dead.length >= limit) ||
            result.items.isEmpty ||
            (sorted && zero.length < result.items.length) ||
            (!sorted && page >= maxUnsortedPages) ||
            page >= result.totalPages) {
          break;
        }
        await Future<void>.delayed(delay);
      }
    } on TrackerException catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
            running: false, listing: false, error: () => e.message);
      }
      return;
    }
    state = state.copyWith(listing: false);

    final present = ref.read(torrentsProvider).hashes;
    for (final item in state.items) {
      if (_stop || !ref.mounted) break;
      if (present.contains(item.release.infoHash)) {
        _set(item.key, (i) => i.copyWith(status: ReviveStatus.present));
        state = state.copyWith(done: state.done + 1);
        continue;
      }
      _set(item.key, (i) => i.copyWith(status: ReviveStatus.searching));
      final result = await _search(item, sources);
      if (!ref.mounted) return;
      final hash = result.candidate?.infoHash;
      _set(
          item.key,
          (_) => _pending.containsKey(hash)
              ? result.copyWith(status: ReviveStatus.downloading, hash: hash)
              : present.contains(hash)
                  ? result.copyWith(
                      detail: 'La copie ${result.candidate!.tracker.label} est '
                          'déjà dans Transmission')
                  : result);
      state = state.copyWith(done: state.done + 1);
      await Future<void>.delayed(delay);
    }
    if (ref.mounted) state = state.copyWith(running: false);
  }

  /// Copies de même taille sur chaque source ; garde la plus seedée.
  Future<ReviveItem> _search(ReviveItem item, List<TrackerApi> sources) async {
    final sameSize = <Release>[];
    final misses = <String>[];
    var errors = 0;
    for (final api in sources) {
      try {
        final found = await _find(api, item.release);
        final same = found.where((r) => r.size == item.release.size);
        sameSize.addAll(same);
        if (same.isEmpty) {
          misses.add('${api.tracker.label} : ${found.isEmpty
              ? 'aucun résultat'
              : '${found.length} résultat(s), aucun de même taille'}');
        }
      } on TrackerException catch (e) {
        errors++;
        misses.add(e.message);
      }
    }
    if (sameSize.isEmpty) {
      return item.copyWith(
          status: errors == sources.length
              ? ReviveStatus.error
              : ReviveStatus.notFound,
          detail: misses.join(' · '));
    }
    sameSize.sort((a, b) => b.seeders.compareTo(a.seeders));
    final best = sameSize.first;
    return item.copyWith(
        status:
            best.seeders > 0 ? ReviveStatus.available : ReviveStatus.noSeeders,
        candidate: best);
  }

  /// Recherche par nom. AstraTorrent cherche la chaîne telle quelle, et ses
  /// noms s'écrivent avec des points ou des espaces : on essaie les deux.
  Future<List<Release>> _find(TrackerApi api, Release release) async {
    final name = crossSeedQuery(release.name);
    final found = (await api.releases(query: name, perPage: 20)).items;
    final spaced = name.replaceAll('.', ' ');
    if (found.isNotEmpty || api.tracker != Tracker.astra || spaced == name) {
      return found;
    }
    return (await api.releases(query: spaced, perPage: 20)).items;
  }

  /// Vérifie que les deux .torrent ont les mêmes fichiers, télécharge la copie
  /// et mémorise le .torrent d'origine pour le cross-seed. Renvoie une erreur, ou
  /// null.
  Future<String?> add(ReviveItem item) async {
    final trackers = ref.read(trackersProvider);
    final origin = trackers[item.release.tracker];
    final candidate = item.candidate;
    final source = trackers[candidate?.tracker];
    final client = ref.read(transmissionProvider);
    if (origin == null || source == null || client == null || candidate == null) {
      return 'Configure ${item.release.tracker.label}, '
          '${candidate?.tracker.label ?? 'le tracker'} et Transmission dans '
          'les réglages';
    }
    final torrents = ref.read(torrentsProvider.notifier);
    try {
      final remote = await source.downloadTorrent(candidate);
      final local = await origin.downloadTorrent(item.release);
      if (!sameFiles(TorrentContent.parse(remote).files,
          TorrentContent.parse(local).files)) {
        if (ref.mounted) {
          _set(
              item.key,
              (i) => i.copyWith(
                  status: ReviveStatus.mismatch,
                  detail: 'Même taille, mais pas les mêmes fichiers'));
        }
        return 'Fichiers différents entre ${item.release.tracker.label} et '
            '${candidate.tracker.label}';
      }
      final added = await client.addTorrentWithHash(
          metainfo: remote,
          options: await client.categorized(const AddOptions(), ContentKind.of(item.release)));
      final hash = added.hash ?? candidate.infoHash;
      if (hash == null) return 'Transmission n’a pas renvoyé l’infohash';
      if (!ref.mounted) return null;
      _pending[hash] = PendingRevive(
          name: item.release.name, metainfo: local, at: DateTime.now());
      ref.read(reviveStoreProvider).save(_pending);
      _set(item.key,
          (i) => i.copyWith(status: ReviveStatus.downloading, hash: hash));
      await torrents.refresh(full: true);
      return null;
    } on TrackerException catch (e) {
      return e.message;
    } on TransmissionException catch (e) {
      return e.message;
    } on FormatException catch (e) {
      return '.torrent illisible : ${e.message}';
    }
  }

  /// Ajoute toutes les sorties disponibles ; renvoie le nombre d'envois.
  Future<int> addAll() async {
    var n = 0;
    for (final item in state.items
        .where((i) => i.status == ReviveStatus.available)
        .toList()) {
      if (await add(item) == null) n++;
    }
    return n;
  }

  /// Copie téléchargée : ajoute le .torrent d'origine dans son dossier.
  Future<void> _checkPending(TorrentsState torrents) async {
    final client = ref.read(transmissionProvider);
    if (!torrents.loaded || _pending.isEmpty || client == null) return;
    final byHash = {for (final t in torrents.byId.values) t.hash: t};

    for (final MapEntry(key: hash, value: p) in _pending.entries.toList()) {
      final t = byHash[hash];
      if (t == null) {
        if (DateTime.now().difference(p.at) > forgetAfter) _forget(hash);
        continue;
      }
      // Terminé et pas en cours de vérification.
      if (t.percentDone < 1 || t.status == 1 || t.status == 2) continue;
      if (!_adding.add(hash)) continue;
      try {
        await client.addTorrent(
          metainfo: p.metainfo,
          // Étiquettes de la copie, dont sa catégorie, en plus de cross-seed.
          options: AddOptions(
              downloadDir: t.downloadDir,
              labels: {CrossSeedNotifier.label, ...t.labels}.toList()),
        );
        if (!ref.mounted) return;
        _forget(hash);
        state = state.copyWith(items: [
          for (final i in state.items)
            i.hash == hash ? i.copyWith(status: ReviveStatus.seeding) : i,
        ]);
      } on TransmissionException {
        // Nouvel essai au prochain rafraîchissement.
      } finally {
        _adding.remove(hash);
      }
    }
  }

  void _forget(String hash) {
    if (_pending.remove(hash) != null) {
      ref.read(reviveStoreProvider).save(_pending);
    }
  }
}

final reviveProvider =
    NotifierProvider<ReviveNotifier, ReviveState>(ReviveNotifier.new);
