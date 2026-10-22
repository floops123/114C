import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/content_kind.dart';
import '../api/tracker.dart';
import '../core/zen.dart';
import '../api/transmission.dart';
import 'palliative.dart';
import 'releases.dart';
import 'torrents.dart';

// Import en masse : on interroge un tracker, on ne garde que ce qui passe les
// bornes (taille, seeders, leechers), on coche ce qui convient, et on envoie
// tout d'un coup à Transmission.
//
// Un seul tracker à la fois : chacun a ses propres catégories, avec ses
// propres identifiants. Les catégories cochées sont transmises au tracker
// (une recherche par catégorie, chacune avec sa pagination). Les bornes, elles,
// sont appliquées ici : aucun indexer ne sait filtrer sur la taille ou les
// seeders. Mais l'ordre de parcours est demandé au tracker quand il sait le
// faire : en taille croissante (le cas d'usage premier : les petits
// torrents), le parcours s'arrête à la taille max et saute à la taille min
// par dichotomie.

// Bornes d'un critère numérique ; null : pas de borne.
typedef Bound = ({int? min, int? max});

/// Une catégorie d'un tracker, ou l'une de ses sous-catégories, désignée par
/// les identifiants de ce tracker.
typedef CategoryRef = ({int category, int? subcategory});

/// Nom affiché d'une catégorie choisie, d'après les catégories du tracker.
String categoryLabel(List<Category> categories, CategoryRef ref) {
  for (final c in categories) {
    if (c.id != ref.category) continue;
    if (ref.subcategory == null) return c.name;
    for (final s in c.subcategories) {
      if (s.id == ref.subcategory) return s.name;
    }
  }
  return '#${ref.subcategory ?? ref.category}';
}

/// Ordre dans lequel le tracker est parcouru et les résultats affichés.
enum BulkOrder {
  smallest('Plus petits'),
  seeders('Plus de seeders'),
  newest('Plus récents'),

  /// Zen par jour estimés (C411, classe Swarm Keeper), en se comptant
  /// parmi les seeders.
  zen('Plus rentables');

  const BulkOrder(this.label);
  final String label;

  int compare(Release a, Release b) => switch (this) {
        smallest => a.size.compareTo(b.size),
        seeders => b.seeders.compareTo(a.seeders),
        newest => b.createdAt.compareTo(a.createdAt),
        zen => zenOf(b).compareTo(zenOf(a)),
      };

  /// Zen par jour que rapporterait la sortie une fois partagée (0 hors
  /// C411), avec le [bonus] du compte, après [seedDays] jours de seed.
  static double zenOf(Release r, {double bonus = 0.25, double seedDays = 0}) => r.tracker != Tracker.c411
      ? 0
      : estimateZen(bytes: r.size, seeders: r.seeders, seedDays: seedDays, bonus: bonus, joining: true).perDay;
}

/// Horizons des gains cumulés, en jours de seed.
const zenHorizons = [7, 30, 60, 90, 180];

/// Zen cumulés par [r] pendant ses [days] premiers jours de seed, partagée
/// [share] de la journée (1 : toute la journée) : la note monte aux paliers
/// de durée (7, 30, 90, 180 j), comptés en jours de seed réels.
double zenOver(Release r, int days, {double bonus = 0.25, double share = 1}) {
  final starts = [0, for (final (from, _) in seedDurationSteps) from];
  var total = 0.0;
  for (final (i, from) in starts.indexed) {
    if (from >= days) break;
    final to = i + 1 < starts.length && starts[i + 1] < days ? starts[i + 1] : days;
    total += BulkOrder.zenOf(r, bonus: bonus, seedDays: from.toDouble()) * (to - from);
  }
  return total * share;
}

/// Ce que rapporterait une sélection une fois partagée [share] de la
/// journée : Zen par jour tout de suite et après six mois, et cumulés sur
/// chaque horizon de [zenHorizons] ; [counted] : les sorties C411, les
/// seules qui rapportent.
///
/// Le site paie chaque torrent au prorata du temps partagé dans la journée.
/// Avec [share] < 1, les paliers de durée arrivent aussi plus tard (ils
/// comptent les jours de seed réels) : 7 jours de seed demandent 7 ÷ share
/// jours de calendrier.
({int counted, double perDay, double perDayLater, Map<int, double> over}) selectionZen(
    Iterable<Release> releases,
    {double bonus = 0.25, double share = 1}) {
  var counted = 0;
  var perDay = 0.0, later = 0.0;
  final over = {for (final d in zenHorizons) d: 0.0};
  for (final r in releases) {
    if (r.tracker != Tracker.c411) continue;
    counted++;
    perDay += BulkOrder.zenOf(r, bonus: bonus) * share;
    // Six mois de calendrier : 180 × share jours de seed.
    later += BulkOrder.zenOf(r, bonus: bonus, seedDays: 180 * share) * share;
    for (final d in zenHorizons) {
      over[d] = over[d]! + _overCalendar(r, d, bonus: bonus, share: share);
    }
  }
  return (counted: counted, perDay: perDay, perDayLater: later, over: over);
}

/// Zen cumulés en [days] jours de calendrier, partagés [share] de chaque
/// journée : chaque jour rapporte au prorata, avec la note de ses jours de
/// seed cumulés (jour × share).
double _overCalendar(Release r, int days, {required double bonus, required double share}) {
  if (share >= 1) return zenOver(r, days, bonus: bonus);
  var total = 0.0;
  for (var d = 0; d < days; d++) {
    total += BulkOrder.zenOf(r, bonus: bonus, seedDays: d * share);
  }
  return total * share;
}

/// Ce qu'on cherche. Toutes les bornes sont facultatives.
class BulkCriteria {
  const BulkCriteria({
    this.name = '',
    this.tracker,
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

  /// Tracker interrogé ; null tant qu'aucun n'est configuré.
  final Tracker? tracker;

  /// Catégories du [tracker] retenues (vide = toutes).
  final Set<CategoryRef> categories;

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
    Tracker? tracker,
    Set<CategoryRef>? categories,
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
        tracker: tracker ?? this.tracker,
        categories: categories ?? this.categories,
        sizeMin: sizeMin ?? this.sizeMin,
        sizeMax: sizeMax ?? this.sizeMax,
        seedersMin: seedersMin ?? this.seedersMin,
        seedersMax: seedersMax ?? this.seedersMax,
        leechersMin: leechersMin ?? this.leechersMin,
        leechersMax: leechersMax ?? this.leechersMax,
        order: order ?? this.order,
      );

  /// La sortie passe-t-elle les bornes ? Le tracker et la catégorie sont
  /// déjà ceux de la requête.
  bool accepts(Release r) =>
      _within(r.size, size) &&
      _within(r.seeders, seeders) &&
      _within(r.leechers, leechers);

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
    this.sent = 0,
    this.toSend = 0,
    this.error,
    this.categories = const [],
    this.loadingCategories = false,
  });

  final List<BulkItem> items;
  final BulkCriteria criteria;

  /// Requêtes en cours.
  final bool loading;

  /// Des pages restent à parcourir (« Encore »).
  final bool hasMore;

  /// Sorties examinées depuis la recherche, retenues ou non.
  final int scanned;

  /// Une recherche a eu lieu (pour distinguer « pas encore cherché » de
  /// « aucun résultat »).
  final bool searched;
  final bool sending;

  /// Progression de l'envoi en cours : traitées (envoyées ou en échec) sur
  /// [toSend]. Les téléchargements sont espacés, l'envoi prend du temps.
  final int sent;
  final int toSend;
  final String? error;

  /// Catégories du tracker choisi, chargées à sa sélection.
  final List<Category> categories;
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
    int? sent,
    int? toSend,
    String? Function()? error,
    List<Category>? categories,
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
        sent: sent ?? this.sent,
        toSend: toSend ?? this.toSend,
        error: error != null ? error() : this.error,
        categories: categories ?? this.categories,
        loadingCategories: loadingCategories ?? this.loadingCategories,
      );
}

class BulkImportNotifier extends Notifier<BulkState> {
  /// Taille d'une page demandée au tracker.
  static const perPage = 50;

  /// Tours de pages enchaînés automatiquement par recherche (ou par
  /// « Encore ») : évite de marteler le tracker (quota C411 : 120 requêtes /
  /// minute) quand les bornes ne laissent presque rien passer.
  static const maxPages = 10;

  /// Résultats retenus au-delà desquels on cesse d'enchaîner les pages.
  static const target = perPage;

  /// Plafond de requêtes pour trouver la page de la taille min.
  static const maxProbes = 14;

  bool _busy = false;
  int _generation = 0;

  /// Pagination de chaque recherche : une par catégorie choisie (null :
  /// toutes les catégories).
  var _pages = <CategoryRef?, int>{};
  var _more = <CategoryRef?, bool>{};

  /// Critères saisis par l'utilisateur. Conservés ici pour survivre au
  /// rebuild déclenché par un changement de la liste des trackers.
  BulkCriteria _criteria = const BulkCriteria();

  /// Catégories déjà chargées, par tracker.
  var _categories = <Tracker, List<Category>>{};

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
    final trackers = ref.watch(trackersProvider);
    _reset();
    _categories = {};
    final tracker = _criteria.tracker;
    if (tracker == null || !trackers.containsKey(tracker)) {
      // Premier tracker configuré ; ses catégories n'ont rien à voir avec
      // celles de l'ancien.
      _criteria = BulkCriteria(
        name: _criteria.name,
        tracker: trackers.keys.firstOrNull,
        sizeMin: _criteria.sizeMin,
        sizeMax: _criteria.sizeMax,
        seedersMin: _criteria.seedersMin,
        seedersMax: _criteria.seedersMax,
        leechersMin: _criteria.leechersMin,
        leechersMax: _criteria.leechersMax,
        order: _criteria.order,
      );
    }
    final current = _criteria.tracker;
    if (current != null) Future.microtask(() => _loadCategories(current));
    return BulkState(criteria: _criteria, loadingCategories: current != null);
  }

  /// Charge les catégories de [t] (une fois par tracker). Un échec laisse la
  /// liste vide : la recherche reste possible, toutes catégories confondues.
  Future<void> _loadCategories(Tracker t) async {
    final load = ++_categoryLoad;
    var categories = _categories[t];
    if (categories == null) {
      final api = ref.read(trackersProvider)[t];
      try {
        categories = await api?.categories() ?? const [];
        _categories[t] = categories;
      } on Object {
        categories = const [];
      }
    }
    // Un autre tracker a été choisi entre-temps, ou un rebuild a relancé le
    // chargement : celui-ci est périmé.
    if (!ref.mounted || load != _categoryLoad) return;
    state = state.copyWith(categories: categories, loadingCategories: false);
  }

  /// Change de tracker : catégories et résultats repartent de zéro.
  void selectTracker(Tracker t) {
    if (t == state.criteria.tracker) return;
    _criteria = BulkCriteria(
      name: _criteria.name,
      tracker: t,
      sizeMin: _criteria.sizeMin,
      sizeMax: _criteria.sizeMax,
      seedersMin: _criteria.seedersMin,
      seedersMax: _criteria.seedersMax,
      leechersMin: _criteria.leechersMin,
      leechersMax: _criteria.leechersMax,
      order: _criteria.order,
    );
    clear();
    state = state.copyWith(
      criteria: _criteria,
      categories: _categories[t] ?? const [],
      loadingCategories: true,
    );
    _loadCategories(t);
  }

  /// Met à jour les critères. Un tracker non précisé garde le tracker
  /// courant ; pour en changer, [selectTracker].
  void update(BulkCriteria criteria) {
    _criteria = criteria.tracker == null
        ? criteria.copyWith(tracker: state.criteria.tracker)
        : criteria;
    state = state.copyWith(criteria: _criteria);
  }

  /// Applique les critères aux résultats déjà là, sans réinterroger le
  /// tracker : retire ce qui ne passe plus (sauf ce qui est déjà envoyé) et
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
  /// reprend là où on en était. Les requêtes HTTP déjà parties vont au bout
  /// (pas d'annulation possible sans `CancelToken` par requête), mais leur
  /// réponse est ignorée. Les résultats déjà accumulés sont conservés.
  void stop() {
    _generation++;
    _busy = false;
    state = state.copyWith(
      loading: false,
      hasMore: _pages.isEmpty || _more.values.any((m) => m),
    );
  }

  /// Parcourt le tracker page par page — une recherche par catégorie
  /// choisie —, en enchaînant tant que moins de [target] sorties ont été
  /// retenues (au plus [maxPages] tours) : avec des bornes serrées, une page
  /// peut ne rien laisser passer.
  Future<void> _load(int generation) async {
    final criteria = state.criteria;
    final api = ref.read(trackersProvider)[criteria.tracker];
    if (api == null) {
      _busy = false;
      state = state.copyWith(
        loading: false,
        hasMore: false,
        error: () => 'Configure un tracker dans les Réglages',
      );
      return;
    }
    final streams = criteria.categories.isEmpty
        ? const <CategoryRef?>[null]
        : <CategoryRef?>[...criteria.categories];
    var retained = 0;
    for (var round = 0; round < maxPages && retained < target; round++) {
      final todo = [
        for (final s in streams)
          if (_pages[s] == null || (_more[s] ?? false)) s,
      ];
      if (todo.isEmpty) break;
      final results = await Future.wait([
        for (final s in todo)
          () async {
            try {
              final (page, r) = await _fetch(api, s, criteria);
              return (s, page, r, null);
            } on Object catch (e) {
              return (s, _pages[s] ?? 1, null, '$e');
            }
          }(),
      ]);
      if (!ref.mounted || generation != _generation) return;
      retained += _merge(api, criteria, results);
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

  /// Page suivante d'une recherche. La toute première, en taille croissante
  /// avec une taille min, est cherchée par dichotomie : les plus petites
  /// sorties (fichiers de quelques Ko) occupent souvent des dizaines de
  /// pages.
  Future<(int, ReleasePage)> _fetch(
      TrackerApi api, CategoryRef? category, BulkCriteria criteria) async {
    final how = plan(api, criteria.order);
    Future<ReleasePage> get(int page) => api.releases(
          page: page,
          perPage: perPage,
          query: criteria.name,
          sort: how.sort,
          ascending: how.ascending,
          categoryId: category?.category,
          subcategoryId: category?.subcategory,
        );

    final previous = _pages[category];
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
  int _merge(TrackerApi api, BulkCriteria criteria,
      List<(CategoryRef?, int, ReleasePage?, String?)> results) {
    final present = ref.read(torrentsProvider).hashes;
    final bySize = plan(api, criteria.order).bySize;
    final label = api.tracker.label;
    // Une sortie déjà là (page précédente, ou autre catégorie choisie) garde
    // son état d'envoi ; seules les nouvelles entrent.
    final known = {for (final i in state.items) i.key: i};
    final fresh = <String, BulkItem>{};
    final errors = <String>{};
    var scanned = 0;
    for (final (stream, page, r, failure) in results) {
      _pages[stream] = page;
      if (r == null) {
        _more[stream] = false;
        errors.add(failure!.contains(label) ? failure : '$label : $failure');
        continue;
      }
      scanned += r.items.length;
      final max = criteria.sizeMax;
      // En taille croissante, une sortie au-delà de la taille max annonce
      // que toutes les suivantes le sont aussi.
      final pastMax = max != null &&
          bySize &&
          r.items.isNotEmpty &&
          r.items.last.size > max;
      _more[stream] = page < r.totalPages && r.items.isNotEmpty && !pastMax;
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
    final site = ref.read(c411SiteApiProvider);
    if (transmission == null) {
      state = state.copyWith(
        error: () => 'Configure Transmission dans les Réglages',
      );
      return 0;
    }
    final todo = state.selected;
    if (todo.isEmpty) return 0;
    state = state.copyWith(
        sending: true, sent: 0, toSend: todo.length, error: () => null);
    var added = 0;
    for (final (n, item) in todo.indexed) {
      if (!ref.mounted) return added;
      if (n > 0) state = state.copyWith(sent: n);
      try {
        final api = trackers[item.release.tracker];
        if (api == null) {
          _patch(item.key,
              (i) => i.copyWith(failed: true, detail: 'Tracker non configuré'));
          continue;
        }
        final link = item.release.downloadUrl;
        final options = AddOptions(labels: ContentKind.of(item.release).labels);
        final ok = link != null && link.startsWith('magnet:')
            ? await transmission.addTorrent(filename: link, options: options)
            : await transmission.addTorrent(
                metainfo: await fetchTorrentFile(api, site, item.release),
                options: options,
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
      } on Object catch (e) {
        // Imprévu : la ligne échoue, l'envoi continue et le bouton se
        // libère (sinon « Envoi… » reste affiché pour toujours).
        _patch(item.key, (i) => i.copyWith(failed: true, detail: '$e'));
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