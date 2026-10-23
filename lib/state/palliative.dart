import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/c411.dart';
import '../api/content_kind.dart';
import '../api/ftp.dart';
import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/bencode.dart';
import '../core/preferences.dart';
import '../core/settings.dart';
import 'cross_seed.dart';
import 'media_library.dart';
import 'palliative_match.dart';
import 'releases.dart';
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
//
// Deux autres sources, sans tracker (voir palliative_match.dart) :
//   - un dossier de l'ordinateur : les fichiers trouvés partent sur le
//     serveur (FTP), dans le dossier de Transmission, puis le .torrent C411
//     y est ajouté ; Transmission vérifie et repart en partage. Avec un
//     Transmission local, pas d'envoi : il partage depuis le dossier ;
//   - les torrents déjà dans Transmission : la sortie C411 s'ajoute en
//     cross-seed sur les mêmes fichiers.

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
  uploading('Envoi vers le serveur'),
  noMatch('Aucune correspondance'),
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
    this.step,
  });

  final List<PalliativeItem> items;
  final bool running;

  /// Étape en cours d'une recherche sur le disque ou dans Transmission
  /// (« Dossier : 1 200 fichiers », « Comparaison 3/40 »).
  final String? step;

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
    String? Function()? step,
  }) =>
      PalliativeState(
        items: items ?? this.items,
        running: running ?? this.running,
        listing: listing ?? this.listing,
        done: done ?? this.done,
        error: error != null ? error() : this.error,
        step: step != null ? step() : this.step,
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
    if (!await _loadList(api, limit: limit)) return;

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

  /// Lecture paginée de la liste palliative (par bounty décroissant), dans
  /// [state]. Faux si elle a échoué (l'erreur est dans [state]).
  Future<bool> _loadList(C411SiteApi api, {int? limit}) async {
    final palliative = <Release>[];
    try {
      for (var page = 1;; page++) {
        if (_stop || !ref.mounted) break;
        final result = await api.palliative(page: page, perPage: perPage);
        if (!ref.mounted) return false;
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
      return false;
    }
    if (!ref.mounted) return false;
    state = state.copyWith(listing: false);
    return true;
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
      final added = await client.addTorrentWithHash(
          metainfo: remote,
          options: await client.categorized(const AddOptions(), ContentKind.of(item.release)));
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

  /// Ce qu'il faut pour les recherches sans tracker : la liste (cookie de
  /// session), les .torrent C411, Transmission. Null : l'erreur est posée.
  ({C411SiteApi site, TrackerApi c411, TransmissionClient client})? _sources() {
    final site = ref.read(c411SiteApiProvider);
    final c411 = ref.read(trackersProvider)[Tracker.c411];
    final client = ref.read(transmissionProvider);
    if (site == null || c411 == null || client == null) {
      state = state.copyWith(
          error: () => 'Configure le cookie de session et la clé API C411, et '
              'Transmission, dans les Réglages');
      return null;
    }
    return (site: site, c411: c411, client: client);
  }

  /// Transmission tourne sur cet ordinateur : il lit ses fichiers en place.
  static bool isLocalClient(TransmissionClient client) {
    final host = Uri.tryParse(client.url)?.host ?? '';
    return const {'localhost', '127.0.0.1', '::1', '[::1]'}.contains(host);
  }

  /// Pour chaque sortie palliative (liste relue), [maybe] dit si ça vaut la
  /// peine de télécharger son .torrent, puis [found] le compare et l'ajoute ;
  /// il renvoie le détail de l'ajout, ou null si rien ne correspond.
  Future<void> _matchAll({
    required C411SiteApi site,
    required TrackerApi c411,
    required bool Function(Release) maybe,
    required Future<String?> Function(PalliativeItem, TorrentContent, Uint8List) found,
  }) async {
    if (!await _loadList(site)) return;
    final present = ref.read(torrentsProvider).hashes;
    final total = state.items.length;
    for (final (n, item) in state.items.toList().indexed) {
      if (_stop || !ref.mounted) break;
      state = state.copyWith(done: n, step: () => 'Comparaison ${n + 1}/$total');
      final hash = item.release.infoHash;
      if (hash != null && present.contains(hash)) {
        _set(item.key, (i) => i.copyWith(status: PalliativeStatus.present));
        continue;
      }
      // Rien de cette taille : pas la peine de télécharger le .torrent.
      if (!maybe(item.release)) {
        _set(item.key, (i) => i.copyWith(status: PalliativeStatus.noMatch));
        continue;
      }
      _set(item.key, (i) => i.copyWith(status: PalliativeStatus.searching));
      try {
        final metainfo = await fetchTorrentFile(c411, site, item.release);
        final detail = await found(item, TorrentContent.parse(metainfo), metainfo);
        if (!ref.mounted) return;
        _set(
            item.key,
            (i) => detail == null
                ? i.copyWith(status: PalliativeStatus.noMatch)
                : i.copyWith(status: PalliativeStatus.seeding, detail: detail));
      } on Object catch (e) {
        if (!ref.mounted) return;
        final message = switch (e) {
          TrackerException(:final message) => message,
          TransmissionException(:final message) => message,
          RemoteFilesException(:final message) => message,
          _ => '$e',
        };
        _set(item.key, (i) => i.copyWith(status: PalliativeStatus.error, detail: message));
      }
    }
    if (!ref.mounted) return;
    state = state.copyWith(running: false, done: total, step: () => null);
    await ref.read(torrentsProvider.notifier).refresh(full: true);
  }

  /// Cherche les sorties palliatives dans les torrents de Transmission :
  /// mêmes fichiers (chemins et tailles) qu'un torrent terminé → la sortie
  /// C411 s'ajoute en cross-seed dans son dossier.
  Future<void> scanClient() async {
    if (state.running) return;
    final sources = _sources();
    if (sources == null) return;
    final (:site, :c411, :client) = sources;
    _stop = false;
    state = const PalliativeState(running: true, listing: true, step: 'Torrents de Transmission…');
    final List<Map<String, dynamic>> torrents;
    try {
      torrents = (await client.torrentGet(['id', 'hashString', 'name', 'downloadDir', 'percentDone', 'files'])).torrents;
    } on TransmissionException catch (e) {
      state = state.copyWith(running: false, listing: false, error: () => e.message, step: () => null);
      return;
    }
    int sizeOf(Map<String, dynamic> t) =>
        (t['files'] as List? ?? const []).whereType<Map>().fold(0, (n, f) => n + ((f['length'] as num?)?.toInt() ?? 0));
    final sizes = {
      for (final t in torrents)
        if (((t['percentDone'] as num?) ?? 0) >= 1) sizeOf(t),
    };
    await _matchAll(
      site: site,
      c411: c411,
      maybe: (r) => sizes.contains(r.size),
      found: (item, content, metainfo) async {
        final match = matchClient(content, torrents);
        if (match == null) return null;
        await client.addTorrent(
          metainfo: metainfo,
          options: AddOptions(
              downloadDir: match['downloadDir'] as String?,
              labels: [CrossSeedNotifier.label, ...ContentKind.of(item.release).labels]),
        );
        return 'Cross-seed sur « ${match['name']} »';
      },
    );
  }

  /// Cherche les sorties palliatives dans le dossier [dir] de l'ordinateur :
  /// fichiers retrouvés (tailles, chemins, empreintes) → envoyés sur le
  /// serveur dans le dossier de Transmission, puis le .torrent C411 ajouté.
  /// Avec un Transmission sur cet ordinateur, rien n'est envoyé.
  Future<void> scanFolder(String dir) async {
    if (state.running) return;
    final sources = _sources();
    if (sources == null) return;
    final (:site, :c411, :client) = sources;
    _stop = false;
    state = const PalliativeState(running: true, listing: true, step: 'Lecture du dossier…');
    final index = await LocalIndex.scan(dir, onCount: (n) {
      if (ref.mounted) state = state.copyWith(step: () => 'Dossier : $n fichiers');
    });
    if (!ref.mounted) return;
    final local = isLocalClient(client);
    await _matchAll(
      site: site,
      c411: c411,
      maybe: (r) => index.mayHold(r.size),
      found: (item, content, metainfo) async {
        final match = await matchLocal(content, index);
        if (match == null) return null;
        return local
            ? _addInPlace(client, content, metainfo, match, ContentKind.of(item.release).labels)
            : _upload(item, client, content, metainfo, match);
      },
    );
  }

  /// Transmission local : ajouté en pause dans le dossier parent, renommé si
  /// le fichier ou le dossier n'a pas le nom du torrent, vérifié, relancé.
  Future<String> _addInPlace(TransmissionClient client, TorrentContent content,
      Uint8List metainfo, LocalMatch match, List<String> labels) async {
    final root = File(match.root);
    final name = root.uri.pathSegments.where((p) => p.isNotEmpty).last;
    final added = await client.addTorrentWithHash(
        metainfo: metainfo,
        options: AddOptions(downloadDir: root.parent.path, paused: true, labels: labels));
    final ids = (await client.torrentGet(['id'], ids: [?added.hash])).torrents
        .map((t) => (t['id'] as num).toInt())
        .toList();
    if (ids.isEmpty) throw const TransmissionException('Torrent ajouté introuvable');
    if (name != content.name) await client.renamePath(ids.first, content.name, name);
    await client.action('torrent-verify', ids);
    await client.action('torrent-start', ids);
    return 'Partagé depuis ${match.root}';
  }

  /// Transmission sur le serveur : les fichiers partent par FTP dans son
  /// dossier de téléchargement (aux chemins du torrent), puis le .torrent
  /// est ajouté ; Transmission vérifie les données et repart en partage.
  Future<String> _upload(PalliativeItem item, TransmissionClient client, TorrentContent content,
      Uint8List metainfo, LocalMatch match) async {
    final settings = ref.read(settingsProvider).value;
    final library = ref.read(mediaLibraryProvider).library;
    final (from, to) = (library.pathFrom, library.pathTo);
    if (settings == null || !settings.hasFiles) {
      throw const RemoteFilesException(
          'Renseigne l’accès aux fichiers (FTP ou WebDAV) dans les Réglages pour envoyer les fichiers');
    }
    if (from == null || to == null) {
      throw const RemoteFilesException('Chemins du serveur inconnus : lance d’abord un parcours '
          'de la vidéothèque (Films & séries › Sur le disque)');
    }
    final downloadDir = '${(await client.sessionGet())['download-dir'] ?? ''}';
    if (!downloadDir.startsWith(from)) {
      throw RemoteFilesException(
          'Le dossier de Transmission ($downloadDir) n’est pas visible sur le serveur de fichiers');
    }
    final ftpDir = '$to${downloadDir.substring(from.length)}';
    final ftp = await ref.read(ftpConnectProvider)(filesConfigOf(settings));
    final total = match.files.fold(0, (n, f) => n + f.$3);
    var done = 0, shown = -1;
    try {
      for (final (path, local, size) in match.files) {
        final target = '$ftpDir/$path';
        await ftp.makeDirs(target.substring(0, target.lastIndexOf('/')));
        await ftp.write(target, File(local).openRead(), onProgress: (sent) {
          final percent = total == 0 ? 100 : (done + sent) * 100 ~/ total;
          if (percent != shown && ref.mounted) {
            shown = percent;
            _set(item.key, (i) => i.copyWith(status: PalliativeStatus.uploading, detail: '$percent %'));
          }
        });
        done += size;
      }
    } finally {
      await ftp.close();
    }
    await client.addTorrent(
        metainfo: metainfo,
        options: AddOptions(downloadDir: downloadDir, labels: ContentKind.of(item.release).labels));
    return 'Envoyé depuis ${match.root}';
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
          // Étiquettes de la copie, dont sa catégorie, en plus de cross-seed.
          options: AddOptions(
              downloadDir: t.downloadDir,
              labels: {CrossSeedNotifier.label, ...t.labels}.toList()),
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