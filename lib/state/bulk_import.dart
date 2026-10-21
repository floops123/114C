import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../api/transmission.dart';
import 'torrents.dart';

// Import en masse : on interroge les trackers, on ne garde que ce qui passe
// les bornes (taille, seeders, leechers) et la catégorie, on coche ce qui
// convient, et on envoie tout d'un coup à Transmission.
//
// Aucun indexer ne sait filtrer sur la taille ou les seeders : les bornes sont
// appliquées ici. Mais l'ordre de parcours, lui, est demandé au tracker quand
// il sait le faire : en taille croissante (le cas d'usage premier : les
// petits torrents), le parcours s'arrête à la taille max et saute à la taille
// min par dichotomie. La catégorie est aussi transmise quand elle désigne une
// seule catégorie du tracker.

/// Ordre dans lequel les trackers sont parcourus et les résultats affichés.
enum BulkOrder {
  smallest('Plus petits'),
  seeders('Plus de seeders'),
  newest('Plus récents');

  const BulkOrder(this.label);
  final String label;

  int compare(Release a, Release b) => switch (this) {
        smallest => a.size.compareTo(b.size),
        seeders => b.seeders.compareTo(a.seeders),
        newest => b.createdAt.compareTo(a.createdAt),
      };
}

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
    this.order = BulkOrder.smallest,
  });

  /// Nom recherché, passé tel quel au tracker.
  final String name;

  /// Trackers à interroger (vide = tous les trackers configurés).
  final Set<Tracker> trackers;

  /// Catégories retenues (vide = tout). Une sortie passe si son
  /// `subcategory` ou l'une de ses `categories` en fait partie (insensible
  /// à la casse).
  final Set<String> categories;

  /// Tailles en octets.
  final int? sizeMin;
  final int? sizeMax;
  final int? seedersMin;
  final int? seedersMax;
  final int? leechersMin;
  final int? leechersMax;
  final BulkOrder order;

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
    BulkOrder? order,
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
        order: order ?? this.order,
      );

  /// La sortie passe-t-elle les filtres ? Un ensemble vide = pas de filtre.
  bool accepts(Release r) {
    if (trackers.isNotEmpty && !trackers.contains(r.tracker)) return false;
    if (categories.isNotEmpty) {
      final cs = categories.map((c) => c.toLowerCase()).toSet();
      if (![r.subcategory, ...r.categories]
          .any((c) => cs.contains(c.toLowerCase()))) {
        return false;
      }
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
    this.present = false,
  });

  final Release release;

  /// Cochée par l'utilisateur (par défaut, tout ce qui matche est coché).
  final bool selected;

  /// Envoyée à Transmission.
  final bool done;

  /// L'envoi a échoué ; le motif est dans [detail].
  final bool failed;
  final String? detail;

  /// Déjà dans Transmission au moment de la recherche : décochée d'office.
  final bool present;

  String get key => '${release.tracker.name}:${release.id}';

  BulkItem copyWith({bool? selected, bool? done, bool? failed, String? detail}) =>
      BulkItem(
        release: release,
        selected: selected ?? this.selected,
        done: done ?? this.done,
        failed: failed ?? this.failed,
        detail: detail ?? this.detail,
        present: present,
      );
}

class BulkState {
  const BulkState({
    this.items = const [],
    this.criteria = const BulkCriteria(),
    this.loading = false,
    this.hasMore = false,
    this.scanned = 0,
    this.searched = false,
    this.sending = false,
    this.error,
    this.availableCategories = const [],
    this.loadingCategories = false,
  });

  final List<BulkItem> items;
  final BulkCriteria criteria;

  /// Requêtes en cours.
  final bool loading;

  /// Des trackers ont encore des pages à parcourir (« Encore »).
  final bool hasMore;

  /// Sorties examinées depuis la recherche, retenues ou non.
  final int scanned;

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

  int get selectedSize => selected.fold(0, (n, i) => n + i.release.size);

  BulkState copyWith({
    List<BulkItem>? items,
    BulkCriteria? criteria,
    bool? loading,
    bool? hasMore,
    int? scanned,
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
        hasMore: hasMore ?? this.hasMore,
        scanned: scanned ?? this.scanned,
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

  /// Tours de pages enchaînés automatiquement par recherche (ou par
  /// « Encore ») : évite de marteler un tracker (quota C411 : 120 requêtes /
  /// minute) quand les bornes ne laissent presque rien passer.
  static const maxPages = 10;

  /// Résultats retenus au-delà desquels on cesse d'enchaîner les pages.
  static const target = perPage;

  /// Plafond de requêtes pour trouver la page de la taille min.
  static const maxProbes = 14;

  bool _busy = false;
  int _generation = 0;
  var _pages = <Tracker, int>{};
  var _more = <Tracker, bool>{};

  /// Catégories de chaque tracker, pour lui transmettre celle choisie.
  var _trackerCategories = <Tracker, List<Category>>{};

  /// Critères saisis par l'utilisateur. Conservés ici pour survivre au
  /// rebuild déclenché par un changement de la liste des trackers.
  BulkCriteria _criteria = const BulkCriteria();

  /// Catégories déjà chargées depuis les `categories()` des trackers. Vides
  /// tant que `_loadAvailableCategories` n'a pas tourné ; conservées ici
  /// pour rester affichées pendant leur rechargement.
  List<String> _availableCategories = const [];

  /// Numéro du dernier chargement des catégories lancé.
  int _categoryLoad = 0;

  @override
  BulkState build() {
    // Les clients sont recréés quand les réglages changent : on repart de zéro.
    // On n'utilise pas `state` ici (interdit en Riverpod 3) : les champs
    // privés ci-dessus conservent ce qui doit l'être, et la liste des
    // résultats, la sélection et les flags de chargement repartent à zéro.
    // L'instance survit au rebuild : une `_load()` en vol, faite avec les
    // anciens clients, est invalidée par la génération.
    ref.watch(trackersProvider);
    _reset();
    // Les catégories dépendent des trackers configurés : rechargées à chaque
    // build (le premier compris).
    Future.microtask(_loadAvailableCategories);
    return BulkState(
      criteria: _criteria,
      availableCategories: _availableCategories,
      loadingCategories: true,
    );
  }

  /// Récupère les sous-catégories de chaque tracker configuré et alimente
  /// `availableCategories` avec l'union dédupliquée. Une erreur par tracker
  /// est ignorée : le tracker qui échoue sera de toute façon signalé dans
  /// les résultats de recherche.
  Future<void> _loadAvailableCategories() async {
    final trackers = ref.read(trackersProvider);
    final load = ++_categoryLoad;
    final names = <String>{};
    final byTracker = <Tracker, List<Category>>{};
    await Future.wait([
      for (final t in trackers.keys)
        () async {
          try {
            // Les sous-catégories quand il y en a ; sinon la catégorie
            // elle-même (AstraTorrent n'expose que celles-ci).
            final cats = byTracker[t] = await trackers[t]!.categories();
            for (final c in cats) {
              for (final n in c.subcategories.isEmpty
                  ? [c.name]
                  : c.subcategories.map((s) => s.name)) {
                if (n.trim().isNotEmpty) names.add(n.trim());
              }
            }
          } on Object catch (_) {
            // Ignoré.
          }
        }(),
    ]);
    // Un rebuild entre-temps a relancé le chargement avec les nouveaux
    // trackers : celui-ci est périmé.
    if (!ref.mounted || load != _categoryLoad) return;
    final sorted = (names.toList()..sort());
    _availableCategories = sorted;
    _trackerCategories = byTracker;
    state = state.copyWith(availableCategories: sorted, loadingCategories: false);
  }

  void update(BulkCriteria criteria) {
    _criteria = criteria;
    state = state.copyWith(criteria: criteria);
  }

  /// Applique les critères aux résultats déjà là, sans réinterroger les
  /// trackers : retire ce qui ne passe plus (sauf ce qui est déjà envoyé) et
  /// retrie dans l'ordre choisi.
  void refilter() {
    final criteria = state.criteria;
    state = state.copyWith(
      items: [
        for (final i in state.items)
          if (i.done || criteria.accepts(i.release)) i,
      ]..sort((a, b) => criteria.order.compare(a.release, b.release)),
    );
  }

  /// Oublie la pagination et invalide la `_load()` en vol.
  void _reset() {
    _generation++;
    _busy = false;
    _pages = {};
    _more = {};
  }

  void clear() {
    _reset();
    state = state.copyWith(
      items: const [],
      searched: false,
      sending: false,
      loading: false,
      hasMore: false,
      scanned: 0,
      error: () => null,
    );
  }

  /// Relance la recherche depuis la première page.
  void search() {
    _reset();
    final generation = _generation;
    state = state.copyWith(
      items: const [],
      searched: true,
      loading: true,
      hasMore: false,
      scanned: 0,
      error: () => null,
    );
    Future.microtask(() => _load(generation));
  }

  void loadMore() {
    if (_busy || !state.hasMore) return;
    _busy = true;
    state = state.copyWith(loading: true);
    Future.microtask(() => _load(_generation));
  }

  /// Stoppe la recherche en cours : la génération est incrémentée, donc la
  /// `_load()` en vol jette ses résultats ; le spinner s'arrête et « Encore »
  /// reprend là où on en était. Les
  /// requêtes HTTP déjà parties vont au bout (pas d'annulation possible
  /// sans `CancelToken` par requête), mais leur réponse est ignorée. Les
  /// résultats déjà accumulés dans `items` sont conservés.
  void stop() {
    _generation++;
    _busy = false;
    state = state.copyWith(
      loading: false,
      hasMore: _pages.isEmpty || _more.values.any((m) => m),
    );
  }

  /// Parcourt les trackers page par page, en enchaînant tant que moins de
  /// [target] sorties ont été retenues (au plus [maxPages] tours) : avec des
  /// bornes serrées, une page peut ne rien laisser passer. Si
  /// `criteria.trackers` est non vide, seuls ceux-là sont interrogés.
  Future<void> _load(int generation) async {
    final trackers = ref.read(trackersProvider);
    final criteria = state.criteria;
    final selected = criteria.trackers;
    var retained = 0;
    for (var round = 0; round < maxPages && retained < target; round++) {
      final todo = [
        for (final t in trackers.keys)
          if ((selected.isEmpty || selected.contains(t)) &&
              (_pages[t] == null || (_more[t] ?? false)))
            t,
      ];
      if (todo.isEmpty) break;
      final results = await Future.wait([
        for (final t in todo)
          () async {
            try {
              final (page, r) = await _fetch(t, trackers[t]!, criteria);
              return (t, page, r, null);
            } on Object catch (e) {
              return (t, _pages[t] ?? 1, null, '$e');
            }
          }(),
      ]);
      if (!ref.mounted || generation != _generation) return;
      retained += _merge(criteria, results);
    }
    if (!ref.mounted || generation != _generation) return;
    _busy = false;
    state = state.copyWith(
      loading: false,
      hasMore: _more.values.any((m) => m),
    );
  }

  /// Comment interroger [api] pour l'ordre voulu : taille croissante ou
  /// seeders si le tracker trie lui-même, sinon les plus récentes.
  static ({ReleaseSort sort, bool ascending, bool bySize}) plan(
      TrackerApi api, BulkOrder order) {
    final server = api.serverSorts;
    return switch (order) {
      BulkOrder.smallest when server.contains(ReleaseSort.size) =>
        (sort: ReleaseSort.size, ascending: true, bySize: true),
      BulkOrder.seeders when server.contains(ReleaseSort.seeders) =>
        (sort: ReleaseSort.seeders, ascending: false, bySize: false),
      _ => (sort: ReleaseSort.date, ascending: false, bySize: false),
    };
  }

  /// Catégorie à transmettre au tracker : seulement si les noms choisis y
  /// désignent une seule catégorie ou sous-catégorie (un seul paramètre
  /// possible). Sinon le filtre reste fait ici.
  static ({int? category, int? subcategory}) serverCategory(
      List<Category>? categories, Set<String> names) {
    const none = (category: null, subcategory: null);
    if (names.isEmpty || categories == null) return none;
    final wanted = {for (final n in names) n.trim().toLowerCase()};
    final matches = [
      for (final c in categories) ...[
        if (wanted.contains(c.name.trim().toLowerCase()))
          (category: c.id, subcategory: null),
        for (final s in c.subcategories)
          if (wanted.contains(s.name.trim().toLowerCase()))
            (category: c.id, subcategory: s.id),
      ],
    ];
    return matches.length == 1 ? matches.single : none;
  }

  /// Page suivante d'un tracker. La toute première, en taille croissante
  /// avec une taille min, est cherchée par dichotomie : les plus petites
  /// sorties (fichiers de quelques Ko) occupent souvent des dizaines de
  /// pages.
  Future<(int, ReleasePage)> _fetch(
      Tracker t, TrackerApi api, BulkCriteria criteria) async {
    final how = plan(api, criteria.order);
    final cat = serverCategory(_trackerCategories[t], criteria.categories);
    Future<ReleasePage> get(int page) => api.releases(
          page: page,
          perPage: perPage,
          query: criteria.name,
          sort: how.sort,
          ascending: how.ascending,
          categoryId: cat.category,
          subcategoryId: cat.subcategory,
        );

    final previous = _pages[t];
    if (previous != null) return (previous + 1, await get(previous + 1));
    final first = await get(1);
    final min = criteria.sizeMin;
    if (!how.bySize ||
        min == null ||
        first.items.isEmpty ||
        first.items.last.size >= min ||
        first.totalPages <= 1) {
      return (1, first);
    }
    // Page 1 entièrement sous la taille min : on cherche la première page
    // dont la dernière sortie l'atteint.
    final seen = <int, ReleasePage>{};
    var lo = 2, hi = first.totalPages;
    for (var probes = 0; lo < hi && probes < maxProbes; probes++) {
      final mid = (lo + hi) ~/ 2;
      final r = seen[mid] = await get(mid);
      if (r.items.isEmpty || r.items.last.size >= min) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return (lo, seen[lo] ?? await get(lo));
  }

  /// Intègre un tour de résultats ; renvoie le nombre de sorties retenues.
  int _merge(BulkCriteria criteria,
      List<(Tracker, int, ReleasePage?, String?)> results) {
    final trackers = ref.read(trackersProvider);
    final present = ref.read(torrentsProvider).hashes;
    // Un torrent déjà présent (page précédente) garde son état d'envoi ;
    // seuls les nouveaux entrent.
    final known = {for (final i in state.items) i.key: i};
    final fresh = <String, BulkItem>{};
    final errors = <String>[];
    var scanned = 0;
    for (final (t, page, r, failure) in results) {
      _pages[t] = page;
      if (r == null) {
        _more[t] = false;
        errors.add(
            failure!.contains(t.label) ? failure : '${t.label} : $failure');
        continue;
      }
      scanned += r.items.length;
      final max = criteria.sizeMax;
      final api = trackers[t];
      // En taille croissante, une sortie au-delà de la taille max annonce
      // que toutes les suivantes le sont aussi.
      final pastMax = max != null &&
          api != null &&
          plan(api, criteria.order).bySize &&
          r.items.isNotEmpty &&
          r.items.last.size > max;
      _more[t] = page < r.totalPages && r.items.isNotEmpty && !pastMax;
      for (final release in r.items) {
        if (!criteria.accepts(release)) continue;
        final key = '${release.tracker.name}:${release.id}';
        if (known.containsKey(key) || fresh.containsKey(key)) continue;
        final here = release.infoHash != null &&
            present.contains(release.infoHash);
        fresh[key] =
            BulkItem(release: release, selected: !here, present: here);
      }
    }
    final items = [...known.values, ...fresh.values]
      ..sort((a, b) => criteria.order.compare(a.release, b.release));
    state = state.copyWith(
      items: items,
      scanned: state.scanned + scanned,
      error: () => errors.isEmpty ? null : errors.join('\n'),
    );
    return fresh.length;
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
    state = state.copyWith(sending: true, error: () => null);
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