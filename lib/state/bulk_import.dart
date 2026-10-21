import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../api/transmission.dart';
import 'torrents.dart';

// Import en masse : on interroge les trackers avec un nom, on ne garde que ce
// qui passe les bornes (taille, seeders, leechers) et la catégorie, on coche
// ce qui convient, et on envoie tout d'un coup à Transmission.
//
// Seul le nom est demandé au tracker (paramètre `q` / `name`) : aucun indexer
// ne sait filtrer sur le nombre de seeders ou sur la taille, et les bornes
// doivent gelten sur tous les trackers à la fois. Elles sont donc appliquées
// ici, sur les résultats de la page.

// Bornes d'un critère numérique ; null : pas de borne.
typedef Bound = ({int? min, int? max});

/// Ce qu'on cherche. Toutes les bornes sont facultatives.
class BulkCriteria {
  const BulkCriteria({
    this.name = '',
    this.trackers = const {},
    this.categories = const {},
    this.sizeMin,
    this.sizeMax,
    this.seedersMin,
    this.seedersMax,
    this.leechersMin,
    this.leechersMax,
  });

  /// Nom recherché, passé tel quel au tracker.
  final String name;

  /// Trackers à interroger (vide = tous les trackers configurés).
  final Set<Tracker> trackers;

  /// Sous-catégories retenues (vide = tout). Les valeurs correspondent à
  /// `r.subcategory` (insensible à la casse).
  final Set<String> categories;

  /// Tailles en octets.
  final int? sizeMin;
  final int? sizeMax;
  final int? seedersMin;
  final int? seedersMax;
  final int? leechersMin;
  final int? leechersMax;

  bool get hasFilters =>
      name.isNotEmpty ||
      trackers.isNotEmpty ||
      categories.isNotEmpty ||
      sizeMin != null ||
      sizeMax != null ||
      seedersMin != null ||
      seedersMax != null ||
      leechersMin != null ||
      leechersMax != null;

  Bound get size => (min: sizeMin, max: sizeMax);
  Bound get seeders => (min: seedersMin, max: seedersMax);
  Bound get leechers => (min: leechersMin, max: leechersMax);

  BulkCriteria copyWith({
    String? name,
    Set<Tracker>? trackers,
    Set<String>? categories,
    int? sizeMin,
    int? sizeMax,
    int? seedersMin,
    int? seedersMax,
    int? leechersMin,
    int? leechersMax,
  }) =>
      BulkCriteria(
        name: name ?? this.name,
        trackers: trackers ?? this.trackers,
        categories: categories ?? this.categories,
        sizeMin: sizeMin ?? this.sizeMin,
        sizeMax: sizeMax ?? this.sizeMax,
        seedersMin: seedersMin ?? this.seedersMin,
        seedersMax: seedersMax ?? this.seedersMax,
        leechersMin: leechersMin ?? this.leechersMin,
        leechersMax: leechersMax ?? this.leechersMax,
      );

  /// La sortie passe-t-elle les filtres ? Un ensemble vide = pas de filtre.
  bool accepts(Release r) {
    if (trackers.isNotEmpty && !trackers.contains(r.tracker)) return false;
    if (categories.isNotEmpty) {
      final cs = categories.map((c) => c.toLowerCase()).toSet();
      if (!cs.contains(r.subcategory.toLowerCase())) return false;
    }
    return _within(r.size, size) &&
        _within(r.seeders, seeders) &&
        _within(r.leechers, leechers);
  }

  static bool _within(int value, Bound b) =>
      (b.min == null || value >= b.min!) && (b.max == null || value <= b.max!);
}

/// Une sortie trouvée, avec son état d'envoi.
class BulkItem {
  const BulkItem({
    required this.release,
    this.selected = true,
    this.done = false,
    this.failed = false,
    this.detail,
  });

  final Release release;

  /// Cochée par l'utilisateur (par défaut, tout ce qui matche est coché).
  final bool selected;

  /// Envoyée à Transmission.
  final bool done;

  /// L'envoi a échoué ; le motif est dans [detail].
  final bool failed;
  final String? detail;

  String get key => '${release.tracker.name}:${release.id}';

  BulkItem copyWith({bool? selected, bool? done, bool? failed, String? detail}) =>
      BulkItem(
        release: release,
        selected: selected ?? this.selected,
        done: done ?? this.done,
        failed: failed ?? this.failed,
        detail: detail ?? this.detail,
      );
}

class BulkState {
  const BulkState({
    this.items = const [],
    this.criteria = const BulkCriteria(),
    this.loading = false,
    this.searched = false,
    this.sending = false,
    this.error,
    this.availableCategories = const [],
    this.loadingCategories = false,
  });

  final List<BulkItem> items;
  final BulkCriteria criteria;
  final bool loading;

  /// Une recherche a eu lieu (pour distinguer « pas encore cherché » de
  /// « aucun résultat »).
  final bool searched;
  final bool sending;
  final String? error;

  /// Sous-catégories proposées par les `categories()` des trackers configurés,
  /// pour les proposer en filtre avant même la première recherche. Chargé
  /// en tâche de fond à l'ouverture de la page.
  final List<String> availableCategories;
  final bool loadingCategories;

  /// Ce qu'il reste à envoyer (coché, pas encore envoyé).
  List<BulkItem> get pending => items.where((i) => !i.done).toList();
  List<BulkItem> get selected => pending.where((i) => i.selected).toList();

  int get sentCount => items.where((i) => i.done).length;

  BulkState copyWith({
    List<BulkItem>? items,
    BulkCriteria? criteria,
    bool? loading,
    bool? searched,
    bool? sending,
    String? Function()? error,
    List<String>? availableCategories,
    bool? loadingCategories,
  }) =>
      BulkState(
        items: items ?? this.items,
        criteria: criteria ?? this.criteria,
        loading: loading ?? this.loading,
        searched: searched ?? this.searched,
        sending: sending ?? this.sending,
        error: error != null ? error() : this.error,
        availableCategories: availableCategories ?? this.availableCategories,
        loadingCategories: loadingCategories ?? this.loadingCategories,
      );
}

class BulkImportNotifier extends Notifier<BulkState> {
  /// Taille d'une page demandée à chaque tracker.
  static const perPage = 50;

  /// Plafond de pages par tracker : évite de marteler un nom vide ou trop
  /// courant (quota C411 : 120 requêtes / minute).
  static const maxPages = 10;

  bool _busy = false;
  int _generation = 0;
  var _pages = <Tracker, int>{};
  var _more = <Tracker, bool>{};

  /// Vrai après le premier déclenchement de chargement des catégories.
  /// Conservé en champ privé pour persister d'un build à l'autre : lire
  /// `state` depuis `build()` est interdit en Riverpod 3.
  bool _categoriesRequested = false;

  /// Critères saisis par l'utilisateur. Conservés ici pour survivre au
  /// rebuild déclenché par un changement de la liste des trackers.
  BulkCriteria _criteria = const BulkCriteria();

  /// Catégories déjà chargées depuis les `categories()` des trackers. Vides
  /// tant que `_loadAvailableCategories` n'a pas tourné ; conservées ici
  /// pour ne pas re-solliciter les trackers à chaque rebuild.
  List<String> _availableCategories = const [];

  @override
  BulkState build() {
    // Les clients sont recréés quand les réglages changent : on repart de zéro.
    // On n'utilise pas `state` ici (interdit en Riverpod 3) : les champs
    // privés ci-dessus conservent ce qui doit l'être, et la liste des
    // résultats, la sélection et les flags de chargement repartent à zéro.
    ref.watch(trackersProvider);
    if (!_categoriesRequested) {
      _categoriesRequested = true;
      Future.microtask(_loadAvailableCategories);
    }
    return BulkState(
      criteria: _criteria,
      availableCategories: _availableCategories,
      loadingCategories: false,
    );
  }

  /// Récupère les sous-catégories de chaque tracker configuré et alimente
  /// `availableCategories` avec l'union dédupliquée. Une erreur par tracker
  /// est ignorée : le tracker qui échoue sera de toute façon signalé dans
  /// les résultats de recherche.
  Future<void> _loadAvailableCategories() async {
    final trackers = ref.read(trackersProvider);
    final names = <String>{};
    await Future.wait([
      for (final t in trackers.keys)
        () async {
          try {
            for (final c in await trackers[t]!.categories()) {
              for (final s in c.subcategories) {
                final n = s.name.trim();
                if (n.isNotEmpty) names.add(n);
              }
            }
          } on Object catch (_) {
            // Ignoré.
          }
        }(),
    ]);
    if (!ref.mounted) return;
    final sorted = (names.toList()..sort());
    _availableCategories = sorted;
    state = state.copyWith(availableCategories: sorted, loadingCategories: false);
  }

  void update(BulkCriteria criteria) {
    _criteria = criteria;
    state = state.copyWith(criteria: criteria);
  }

  void clear() {
    _generation++;
    _busy = false;
    _pages = {};
    _more = {};
    state = state.copyWith(
      items: const [],
      searched: false,
      sending: false,
      error: null,
    );
  }

  /// Relance la recherche depuis la première page.
  void search() {
    _generation++;
    final generation = _generation;
    _busy = false;
    _pages = {};
    _more = {};
    state = state.copyWith(
      items: const [],
      searched: true,
      loading: true,
      error: null,
    );
    Future.microtask(() => _load(generation));
  }

  void loadMore() {
    if (_busy) return;
    _busy = true;
    Future.microtask(() => _load(_generation));
  }

  /// Stoppe la recherche en cours : la génération est incrémentée, donc la
  /// `_load()` en vol jette ses résultats ; le spinner s'arrête. Les
  /// requêtes HTTP déjà parties vont au bout (pas d'annulation possible
  /// sans `CancelToken` par requête), mais leur réponse est ignorée. Les
  /// résultats déjà accumulés dans `items` sont conservés.
  void stop() {
    _generation++;
    state = state.copyWith(loading: false);
  }

  /// Charge une page de chaque tracker encore à feuilleter, et n'ajoute que
  /// les sorties qui passent les bornes. Si `criteria.trackers` est non vide,
  /// on n'interroge que les trackers qu'il contient.
  Future<void> _load(int generation) async {
    final trackers = ref.read(trackersProvider);
    final criteria = state.criteria;
    final selected = criteria.trackers;
    // Log via stderr : sort en build release et debug, visible dans le
    // terminal `flutter run` (et `adb logcat` sur Android).
    // ignore: avoid_print
    print('[bulk_import] _load gen=$generation '
        'trackers=${trackers.keys.map((t) => t.name).toList()} '
        'name="${criteria.name}" selected=$selected '
        'categories=${criteria.categories} '
        'bounds=(${criteria.sizeMin},${criteria.sizeMax}) '
        'seeders=(${criteria.seedersMin},${criteria.seedersMax}) '
        'leechers=(${criteria.leechersMin},${criteria.leechersMax})');
    developer.log('bulk _load', name: 'bulk_import');
    final todo = [
      for (final t in trackers.keys)
        if ((selected.isEmpty || selected.contains(t)) &&
            (_pages[t] == null || (_more[t] ?? false)))
          t,
    ];
    if (todo.isEmpty) {
      _busy = false;
      state = state.copyWith(loading: false);
      return;
    }
    final results = await Future.wait([
      for (final t in todo)
        () async {
          final page = (_pages[t] ?? 0) + 1;
          try {
            final api = trackers[t]!;
            final sort = api.sorts.contains(ReleaseSort.seeders)
                ? ReleaseSort.seeders
                : ReleaseSort.date;
            final r = await api.releases(
              page: page,
              perPage: perPage,
              query: criteria.name,
              sort: sort,
            );
            return (t, page, r, null);
          } on Object catch (e) {
            return (t, page, null, '$e');
          }
        }(),
    ]);
    if (!ref.mounted || generation != _generation) return;
    _busy = false;

    // Un torrent déjà présent (page précédente) garde son état d'envoi ;
    // seuls les nouveaux entrent.
    final known = {for (final i in state.items) i.key: i};
    final fresh = <String, BulkItem>{};
    String? error;
    for (final (t, page, r, failure) in results) {
      _pages[t] = page;
      if (r == null) {
        _more[t] = false;
        error = failure;
        continue;
      }
      _more[t] = page < r.totalPages && r.items.isNotEmpty && page < maxPages;
      for (final release in r.items) {
        if (!criteria.accepts(release)) continue;
        final key = '${release.tracker.name}:${release.id}';
        if (known.containsKey(key) || fresh.containsKey(key)) continue;
        fresh[key] = BulkItem(release: release);
      }
    }
    state = state.copyWith(
      items: [...fresh.values, ...known.values],
      loading: _more.values.any((m) => m),
      error: () => error,
    );
  }

  void toggle(String key, bool selected) =>
      _patch(key, (i) => i.copyWith(selected: selected));

  void toggleAll(bool selected) => state = state.copyWith(
        items: [for (final i in state.items) i.copyWith(selected: selected)],
      );

  /// N'ajoute que les sorties qui ne l'ont pas encore été envoyées (après un
  /// changement de filtres, les lignes déjà envoyées sont barrées).
  void selectPending() => state = state.copyWith(
        items: [for (final i in state.items) i.copyWith(selected: !i.done)],
      );

  void _patch(String key, BulkItem Function(BulkItem) change) {
    state = state.copyWith(
      items: [for (final i in state.items) i.key == key ? change(i) : i],
    );
  }

  /// Envoie les sorties cochées à Transmission, une par une. Renvoie le
  /// nombre d'ajouts ; les échecs restent visibles sur la ligne.
  Future<int> send() async {
    if (state.sending) return 0;
    final trackers = ref.read(trackersProvider);
    final transmission = ref.read(transmissionProvider);
    if (transmission == null) {
      state = state.copyWith(
        error: () => 'Configure Transmission dans les Réglages',
      );
      return 0;
    }
    final todo = state.selected;
    if (todo.isEmpty) return 0;
    state = state.copyWith(sending: true, error: null);
    var added = 0;
    for (final item in todo) {
      if (!ref.mounted) return added;
      try {
        final api = trackers[item.release.tracker];
        if (api == null) {
          _patch(item.key,
              (i) => i.copyWith(failed: true, detail: 'Tracker non configuré'));
          continue;
        }
        final link = item.release.downloadUrl;
        final ok = link != null && link.startsWith('magnet:')
            ? await transmission.addTorrent(filename: link)
            : await transmission.addTorrent(
                metainfo: await api.downloadTorrent(item.release),
              );
        if (ok) added++;
        _patch(item.key, (i) => i.copyWith(done: true, failed: false, detail: null));
      } on TrackerException catch (e) {
        _patch(item.key, (i) => i.copyWith(failed: true, detail: e.message));
      } on TransmissionException catch (e) {
        _patch(item.key, (i) => i.copyWith(failed: true, detail: e.message));
      } on FormatException catch (e) {
        _patch(item.key, (i) =>
            i.copyWith(failed: true, detail: '.torrent illisible : ${e.message}'));
      }
    }
    if (!ref.mounted) return added;
    state = state.copyWith(sending: false);
    if (added > 0) await ref.read(torrentsProvider.notifier).refresh(full: true);
    return added;
  }
}

final bulkImportProvider =
    NotifierProvider<BulkImportNotifier, BulkState>(BulkImportNotifier.new);