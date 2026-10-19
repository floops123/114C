import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/c411.dart';
import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/bencode.dart';
import '../core/preferences.dart';
import '../core/settings.dart';
import 'cross_seed.dart';
import 'torrents.dart';

// Soins palliatifs : la liste officielle de C411 des sorties sans seeder
// depuis un certain temps (endpoint `/api/torrents?palliative=only`). Pour
// chacune, on cherche la même sortie (nom + taille exacte) sur les autres
// trackers configurés. La copie trouvée se télécharge depuis son tracker ; le
// .torrent d'origine (C411) est mis de côté pour être ajouté en cross-seed
// une fois la copie terminée (étiquette « ${ReviveNotifier.label} »).
//
// Logique calquée sur `lib/state/revive.dart` (sans seeder), mais :
//   - la liste source vient d'un endpoint C411 dédié (cookie de session) ;
//   - la catégorie n'est pas filtrée (paramétrable côté site).

/// Statut d'une sortie palliative, de la lecture C411 au cross-seed.
enum PalliativeStatus {
  waiting('En attente'),
  searching('Recherche…'),
  available('Disponible ailleurs'),
  downloading('Téléchargement'),
  seeding('Repartagé'),
  noSeeders('Sans seeder ailleurs non plus'),
  notFound('Introuvable ailleurs'),
  present('Déjà dans Transmission'),
  mismatch('Fichiers différents'),
  error('Erreur');

  const PalliativeStatus(this.label);
  final String label;
}

/// Une sortie palliative C411 et les copies trouvées sur les autres trackers.
class PalliativeItem {
  const PalliativeItem({
    required this.release,
    this.status = PalliativeStatus.waiting,
    this.candidates = const [],
    this.best,
    this.hash,
    this.detail,
  });

  /// Sortie palliative, côté C411 (tracker d'origine).
  final Release release;

  /// Copies trouvées sur les autres trackers, une par tracker.
  final List<Release> candidates;

  /// Copie la plus seedée, retenue par défaut pour le téléchargement.
  final Release? best;

  final PalliativeStatus status;
  final String? hash;
  final String? detail;

  String get key => release.id;

  PalliativeItem copyWith({
    PalliativeStatus? status,
    List<Release>? candidates,
    Release? best,
    String? hash,
    String? detail,
  }) =>
      PalliativeItem(
        release: release,
        status: status ?? this.status,
        candidates: candidates ?? this.candidates,
        best: best ?? this.best,
        hash: hash ?? this.hash,
        detail: detail ?? this.detail,
      );
}

class PalliativeState {
  const PalliativeState({
    this.items = const [],
    this.running = false,
    this.listing = false,
    this.done = 0,
    this.error,
  });

  final List<PalliativeItem> items;
  final bool running;

  /// Lecture de la liste palliative en cours (avant les recherches).
  final bool listing;
  final int done;
  final String? error;

  int count(PalliativeStatus s) => items.where((i) => i.status == s).length;

  PalliativeState copyWith({
    List<PalliativeItem>? items,
    bool? running,
    bool? listing,
    int? done,
    String? Function()? error,
  }) =>
      PalliativeState(
        items: items ?? this.items,
        running: running ?? this.running,
        listing: listing ?? this.listing,
        done: done ?? this.done,
        error: error != null ? error() : this.error,
      );
}

/// Copie en cours de téléchargement et .torrent C411 à réinjecter ensuite.
class PendingPalliative {
  const PendingPalliative(
      {required this.name, required this.metainfo, required this.at});
  final String name;
  final Uint8List metainfo;
  final DateTime at;
}

/// Torrents en attente de cross-seed vers C411, par infohash de la copie.
/// Mémorisés pour survivre à un redémarrage de l'application.
abstract class PalliativeStore {
  Map<String, PendingPalliative> load();
  void save(Map<String, PendingPalliative> pending);
}

class PrefsPalliativeStore implements PalliativeStore {
  PrefsPalliativeStore(this._prefs);
  final SharedPreferencesWithCache _prefs;
  static const key = 'palliative';

  @override
  Map<String, PendingPalliative> load() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return {};
      return {
        for (final MapEntry(key: k, value: v)
            in (jsonDecode(raw) as Map<String, dynamic>).entries)
          k: PendingPalliative(
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
  void save(Map<String, PendingPalliative> pending) => _prefs.setString(
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

class MemoryPalliativeStore implements PalliativeStore {
  var _pending = <String, PendingPalliative>{};
  @override
  Map<String, PendingPalliative> load() => {..._pending};
  @override
  void save(Map<String, PendingPalliative> pending) => _pending = {...pending};
}

final palliativeStoreProvider = Provider<PalliativeStore>((ref) {
  try {
    return PrefsPalliativeStore(ref.watch(sharedPrefsProvider));
  } on Object {
    return MemoryPalliativeStore(); // Préférences non initialisées (tests).
  }
});

/// Client C411 authentifié par le cookie de session, recréé à chaque
/// changement du cookie.
final c411SiteApiProvider = Provider<C411SiteApi?>((ref) {
  final cookie = ref.watch(
      settingsProvider.select((s) => s.value?.sessionCookie ?? ''));
  if (cookie.isEmpty) return null;
  final api = C411SiteApi(cookie);
  ref.onDispose(api.close);
  return api;
});

class PalliativeNotifier extends Notifier<PalliativeState> {
  static const perPage = 25;

  bool _stop = false;
  final _adding = <String>{};
  var _pending = <String, PendingPalliative>{};

  @override
  PalliativeState build() {
    _pending = ref.read(palliativeStoreProvider).load();
    // Surveille les copies téléchargées pour passer en cross-seed dès la fin.
    ref.listen(torrentsProvider, (_, next) => _checkPending(next));
    return const PalliativeState();
  }

  void stop() => _stop = true;

  void _set(String key, PalliativeItem Function(PalliativeItem) change) {
    state = state.copyWith(items: [
      for (final i in state.items) i.key == key ? change(i) : i,
    ]);
  }

  /// Charge les [limit] premières sorties palliatives (toutes si null) et
  /// cherche chacune sur les trackers non-C411 configurés.
  Future<void> scan({int? limit}) async {
    if (state.running) return;
    final api = ref.read(c411SiteApiProvider);
    final trackers = ref.read(trackersProvider);
    if (api == null) {
      state = state.copyWith(
          error: () =>
              'Configure le cookie de session C411 dans les Réglages');
      return;
    }
    final sources = {
      for (final t in trackers.entries)
        if (t.key != Tracker.c411) t.key: t.value,
    };
    if (sources.isEmpty) {
      state = state.copyWith(
          error: () =>
              'Configure au moins un tracker (autre que C411) pour chercher les palliatifs');
      return;
    }
    _stop = false;
    state = const PalliativeState(running: true, listing: true);

    // Lecture paginée de la liste palliative (par bounty décroissant).
    final palliative = <Release>[];
    try {
      for (var page = 1;; page++) {
        if (_stop || !ref.mounted) break;
        final result = await api.palliative(page: page, perPage: perPage);
        if (!ref.mounted) return;
        palliative.addAll(result.items);
        state = state.copyWith(items: [
          for (final r in palliative.take(limit ?? palliative.length))
            PalliativeItem(release: r),
        ]);
        if ((limit != null && palliative.length >= limit) ||
            result.items.isEmpty ||
            page >= result.totalPages) {
          break;
        }
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
    final delay = ref.read(crossSeedDelayProvider);
    for (final item in state.items) {
      if (_stop || !ref.mounted) break;
      final hash = item.release.infoHash;
      if (hash != null && present.contains(hash)) {
        _set(item.key, (i) => i.copyWith(status: PalliativeStatus.present));
        state = state.copyWith(done: state.done + 1);
        continue;
      }
      _set(item.key, (i) => i.copyWith(status: PalliativeStatus.searching));
      final candidates = await _search(item, sources);
      if (!ref.mounted) return;
      candidates.sort((a, b) => b.seeders.compareTo(a.seeders));
      final best = candidates.isNotEmpty ? candidates.first : null;
      final PalliativeStatus status = candidates.isEmpty
          ? PalliativeStatus.notFound
          : best!.seeders > 0
              ? PalliativeStatus.available
              : PalliativeStatus.noSeeders;
      _set(item.key, (i) => i.copyWith(
            status: status,
            candidates: candidates,
            best: best,
          ));
      state = state.copyWith(done: state.done + 1);
      await Future<void>.delayed(delay);
    }
    if (ref.mounted) state = state.copyWith(running: false);
  }

  /// Copies de même taille sur chaque tracker, dans l'ordre des résultats.
  /// AstraTorrent accepte les chaînes avec des points ou des espaces : on
  /// tente la deuxième variante si la première ne renvoie rien.
  Future<List<Release>> _search(
      PalliativeItem item, Map<Tracker, TrackerApi> sources) async {
    final candidates = <Release>[];
    for (final api in sources.values) {
      try {
        final found = await _find(api, item.release);
        candidates.addAll(
            found.where((r) => r.size == item.release.size));
      } on TrackerException {
        // Une erreur sur un tracker ne bloque pas les autres.
      }
    }
    return candidates;
  }

  Future<List<Release>> _find(TrackerApi api, Release release) async {
    final name = crossSeedQuery(release.name);
    final found = (await api.releases(query: name, perPage: 20)).items;
    final spaced = name.replaceAll('.', ' ');
    if (found.isNotEmpty || api.tracker != Tracker.astra || spaced == name) {
      return found;
    }
    return (await api.releases(query: spaced, perPage: 20)).items;
  }

  /// Vérifie que les deux .torrent ont les mêmes fichiers, télécharge la
  /// copie et mémorise le .torrent d'origine pour le cross-seed. Renvoie
  /// une erreur, ou null.
  Future<String?> add(PalliativeItem item) async {
    final best = item.best;
    if (best == null) {
      return 'Aucune copie à télécharger';
    }
    final trackers = ref.read(trackersProvider);
    final origin = trackers[Tracker.c411];
    final source = trackers[best.tracker];
    final client = ref.read(transmissionProvider);
    if (origin == null || source == null || client == null) {
      return 'Configure C411, ${best.tracker.label} et Transmission dans les '
          'réglages';
    }
    final torrents = ref.read(torrentsProvider.notifier);
    try {
      final remote = await source.downloadTorrent(best);
      final local = await origin.downloadTorrent(item.release);
      if (!sameFiles(TorrentContent.parse(remote).files,
          TorrentContent.parse(local).files)) {
        if (ref.mounted) {
          _set(
              item.key,
              (i) => i.copyWith(
                  status: PalliativeStatus.mismatch,
                  detail: 'Même taille, mais pas les mêmes fichiers'));
        }
        return 'Fichiers différents entre C411 et ${best.tracker.label}';
      }
      final added = await client.addTorrentWithHash(metainfo: remote);
      final hash = added.hash ?? best.infoHash;
      if (hash == null) return 'Transmission n’a pas renvoyé l’infohash';
      if (!ref.mounted) return null;
      _pending[hash] = PendingPalliative(
          name: item.release.name, metainfo: local, at: DateTime.now());
      ref.read(palliativeStoreProvider).save(_pending);
      _set(item.key,
          (i) => i.copyWith(status: PalliativeStatus.downloading, hash: hash));
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

  /// Ajoute toutes les copies disponibles ; renvoie le nombre d'envois.
  Future<int> addAll() async {
    var n = 0;
    for (final item in state.items
        .where((i) => i.status == PalliativeStatus.available)
        .toList()) {
      if (await add(item) == null) n++;
    }
    return n;
  }

  /// Copie téléchargée : ajoute le .torrent C411 dans son dossier.
  Future<void> _checkPending(TorrentsState torrents) async {
    final client = ref.read(transmissionProvider);
    if (!torrents.loaded || _pending.isEmpty || client == null) return;
    final byHash = {for (final t in torrents.byId.values) t.hash: t};

    for (final MapEntry(key: hash, value: p) in _pending.entries.toList()) {
      final t = byHash[hash];
      if (t == null) continue;
      if (t.percentDone < 1 || t.status == 1 || t.status == 2) continue;
      if (!_adding.add(hash)) continue;
      try {
        await client.addTorrent(
          metainfo: p.metainfo,
          options: AddOptions(
              downloadDir: t.downloadDir,
              labels: const [CrossSeedNotifier.label]),
        );
        if (!ref.mounted) return;
        _forget(hash);
        state = state.copyWith(items: [
          for (final i in state.items)
            i.hash == hash ? i.copyWith(status: PalliativeStatus.seeding) : i,
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
      ref.read(palliativeStoreProvider).save(_pending);
    }
  }
}

final palliativeProvider =
    NotifierProvider<PalliativeNotifier, PalliativeState>(PalliativeNotifier.new);