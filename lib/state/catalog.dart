import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/tmdb.dart';
import '../api/tracker.dart';
import '../core/preferences.dart';
import '../core/release_name.dart';
import '../core/titles.dart';
import 'wishlist.dart';

// Deux vues : les tops TMDB (avec leur disponibilité sur les trackers) et les
// tops des trackers, regroupés par film ou série (avec leur fiche TMDB).

/// Exécute les tâches une à une, espacées d'au moins [interval] : les
/// vérifications de disponibilité respectent ainsi le quota des trackers.
class RateLimiter {
  RateLimiter(this.interval);
  final Duration interval;
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) => Future<void>.delayed(interval),
        onError: (_) => Future<void>.delayed(interval));
    return result;
  }
}

/// Un limiteur par tracker. C411 : 120 requêtes / minute pour toute
/// l'application, on en garde la moitié pour le reste.
final trackerLimitersProvider = Provider<Map<Tracker, RateLimiter>>((ref) => {
      for (final t in Tracker.values)
        t: RateLimiter(t == Tracker.c411
            ? const Duration(milliseconds: 1100)
            : const Duration(milliseconds: 400)),
    });

/// Filtre commun aux deux vues.
enum DiskFilter {
  all('Tout'),
  onDisk('Sur le disque'),
  toDownload('À télécharger');

  const DiskFilter(this.label);
  final String label;
}

// ---------------------------------------------------------------------------
// Disponibilité d'un titre TMDB sur les trackers

/// Trackers qui ont le titre ; [checkedAt] pour l'expiration du cache.
class Availability {
  const Availability(this.trackers, this.checkedAt);
  final Set<Tracker> trackers;
  final DateTime checkedAt;
  bool get any => trackers.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'trackers': [for (final t in trackers) t.name],
        'at': checkedAt.toIso8601String(),
      };

  static Availability? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (at == null) return null;
    return Availability({
      for (final n in (json['trackers'] as List? ?? const []))
        ?Tracker.values.asNameMap()[n],
    }, at);
  }
}

/// Recherche légère : le titre est-il sur ce tracker ? Au plus deux requêtes
/// (titre français puis original, en nom à points), arrêt au premier
/// résultat. La recherche complète ([searchWish]) reste pour la page des
/// résultats.
Future<bool> quickAvailable(TrackerApi api, TmdbTitle t,
    {RateLimiter? limiter}) async {
  final queries = {
    for (final title in [t.title, ?t.originalTitle])
      ?releaseQueries(title).firstOrNull,
  };
  for (final q in queries) {
    Future<ReleasePage> search() => api.releases(query: q, perPage: 50);
    final page = await (limiter?.run(search) ?? search());
    if (page.items.any((r) => matchesMedia(r, t) && _sameYear(r, t))) return true;
  }
  return false;
}

bool _sameYear(Release r, TmdbTitle t) =>
    t.type != TmdbType.movie ||
    t.year == null ||
    r.year == null ||
    (r.year! - t.year!).abs() <= 1;

/// Ordre de vérification : les trackers les moins sollicités d'abord, C411
/// (quota partagé avec tout le reste) en dernier.
const _checkOrder = [Tracker.astra, Tracker.tr4ker, Tracker.nostradamus, Tracker.v3x, Tracker.c411];

abstract class AvailabilityStore {
  Map<String, Availability> load();
  void save(Map<String, Availability> entries);
}

class PrefsAvailabilityStore implements AvailabilityStore {
  PrefsAvailabilityStore(this._prefs);
  final SharedPreferencesWithCache _prefs;
  static const key = 'availability';

  @override
  Map<String, Availability> load() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return {};
      return {
        for (final MapEntry(:key, :value)
            in (jsonDecode(raw) as Map<String, dynamic>).entries)
          key: ?Availability.fromJson(value),
      };
    } on Object {
      return {};
    }
  }

  @override
  void save(Map<String, Availability> entries) => _prefs.setString(
      key, jsonEncode({for (final e in entries.entries) e.key: e.value.toJson()}));
}

class MemoryAvailabilityStore implements AvailabilityStore {
  var _entries = <String, Availability>{};
  @override
  Map<String, Availability> load() => {..._entries};
  @override
  void save(Map<String, Availability> entries) => _entries = {...entries};
}

final availabilityStoreProvider = Provider<AvailabilityStore>((ref) {
  try {
    return PrefsAvailabilityStore(ref.watch(sharedPrefsProvider));
  } on Object {
    return MemoryAvailabilityStore(); // Préférences non initialisées (tests).
  }
});

/// Disponibilité des titres TMDB, par clé de titre. Vérifiée à la demande
/// (une affiche affichée la demande), mémorisée 12 h.
class AvailabilityNotifier extends Notifier<Map<String, Availability>> {
  static const ttl = Duration(hours: 12);
  final _pending = <String>{};

  @override
  Map<String, Availability> build() {
    // Nouveaux trackers : tout est à revérifier.
    ref.watch(trackersProvider);
    _pending.clear();
    final now = DateTime.now();
    return {
      for (final e in ref.read(availabilityStoreProvider).load().entries)
        if (now.difference(e.value.checkedAt) < ttl) e.key: e.value,
    };
  }

  /// Lance la vérification de [t] si elle n'est ni faite ni en cours. Les
  /// films pas encore sortis ne sont pas vérifiés (rien à trouver).
  void request(TmdbTitle t) {
    if (state.containsKey(t.key) || _pending.contains(t.key)) return;
    if (t.type == TmdbType.movie && t.upcoming) return;
    _pending.add(t.key);
    unawaited(_check(t));
  }

  Future<void> _check(TmdbTitle t) async {
    final trackers = ref.read(trackersProvider);
    final limiters = ref.read(trackerLimitersProvider);
    final found = <Tracker>{};
    for (final tracker in _checkOrder) {
      final api = trackers[tracker];
      if (api == null) continue;
      try {
        if (await quickAvailable(api, t, limiter: limiters[tracker])) {
          found.add(tracker);
          break; // Un tracker suffit pour proposer le téléchargement.
        }
      } on Object {
        // Tracker en erreur : on passe au suivant.
      }
      if (!ref.mounted) return;
    }
    if (!ref.mounted) return;
    _pending.remove(t.key);
    state = {...state, t.key: Availability(found, DateTime.now())};
    ref.read(availabilityStoreProvider).save(state);
  }

  /// Oublie le résultat (après un téléchargement, ou pour revérifier).
  void forget(TmdbTitle t) {
    state = {...state}..remove(t.key);
    ref.read(availabilityStoreProvider).save(state);
  }
}

final availabilityProvider =
    NotifierProvider<AvailabilityNotifier, Map<String, Availability>>(
        AvailabilityNotifier.new);

// ---------------------------------------------------------------------------
// Tops des trackers, regroupés par titre

/// Un film ou une série et ses sorties, tous trackers confondus ; pour le
/// reste (musique, livre, jeu…), une sortie seule.
class ReleaseGroup {
  ReleaseGroup(this.key, this.type, this.title, this.year, this.originalTitle);

  final String key;

  /// Film ou série (rattachable à TMDB) ; null pour le reste.
  final TmdbType? type;

  /// Titre tel que les trackers le donnent (fiche C411, sinon nom).
  final String title;
  final String? originalTitle;
  final int? year;
  final releases = <Release>[];

  Set<Tracker> get trackers => {for (final r in releases) r.tracker};
  int get maxSeeders =>
      releases.fold(0, (m, r) => r.seeders > m ? r.seeders : m);
  DateTime get latest => releases
      .map((r) => r.createdAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  /// Sortie à télécharger en un clic depuis la fiche : la première du
  /// groupe. Pour les jeux, livres, albums, etc. le groupe ne contient
  /// qu'une sortie, c'est donc celle-là. Pour les films et séries, c'est
  /// la version chargée en premier (typiquement C411, qui sert de pivot
  /// au regroupement). Pour choisir une autre qualité, il faut passer par
  /// la page des versions (clic sur la carte).
  Release get primaryRelease => releases.first;

  /// Affiche fournie par un tracker (C411), faute de fiche TMDB.
  String? get posterUrl =>
      releases.map((r) => r.posterUrl).nonNulls.firstOrNull;

  /// Meilleure résolution parmi les sorties (« 2160p »).
  String? get bestResolution {
    int rank(String? r) =>
        int.tryParse(RegExp(r'\d+').stringMatch(r ?? '') ?? '') ?? 0;
    String? best;
    for (final r in releases) {
      final res = r.resolution ?? ReleaseName.parse(r.name).resolution;
      if (rank(res) > rank(best)) best = res;
    }
    return best;
  }

  /// Requête de rattachement à TMDB ; null hors films et séries.
  ({TmdbType type, String title, int? year})? get tmdbQuery => switch (type) {
        final t? => (type: t, title: originalTitle ?? title, year: year),
        null => null,
      };
}

/// Type d'une sortie : fiche du tracker, sinon marqueur d'épisode dans le
/// nom ; null pour ce qui n'est ni un film ni une série (musique, livre…).
TmdbType? releaseType(Release r) {
  switch (r.mediaKind) {
    case 'movie':
      return TmdbType.movie;
    case 'tv':
      return TmdbType.tv;
    case null:
      break;
    default:
      return null;
  }
  final name = ReleaseName.parse(r.name);
  if (name.kind == 'Série') return TmdbType.tv;
  return name.resolution != null ? TmdbType.movie : null;
}

/// Regroupe les films et séries par titre. Une sortie C411 apporte son
/// titre français et son titre original : les sorties des autres trackers,
/// nommées d'après l'un ou l'autre, rejoignent le même groupe. Le reste
/// (musique, livre, jeu, logiciel…) reste une sortie par groupe.
List<ReleaseGroup> groupReleases(Iterable<Release> releases) {
  final byKey = <String, ReleaseGroup>{};
  final groups = <ReleaseGroup>[];
  for (final r in releases) {
    final type = releaseType(r);
    if (type == null) {
      groups.add(ReleaseGroup('other:${r.tracker.name}:${r.id}', null,
          r.title ?? r.name, r.year, r.originalTitle)
        ..releases.add(r));
      continue;
    }
    final parsed = ReleaseName.parse(r.name);
    final year = r.year ?? parsed.year;
    final titles = [?r.title, ?r.originalTitle, parsed.title];
    String key(String title) =>
        '${type.name}:${titleKey(title)}${type == TmdbType.movie ? ':${year ?? ''}' : ''}';
    final keys = {for (final t in titles) if (titleKey(t).isNotEmpty) key(t)};
    var group = keys.map((k) => byKey[k]).nonNulls.firstOrNull;
    if (group == null) {
      group = ReleaseGroup(keys.first, type, r.title ?? parsed.title, year,
          r.originalTitle);
      groups.add(group);
    }
    for (final k in keys) {
      byKey.putIfAbsent(k, () => group!);
    }
    group.releases.add(r);
  }
  return groups;
}

enum TopSort {
  date('Nouveautés', ReleaseSort.date),
  seeders('Les plus seedées', ReleaseSort.seeders);

  const TopSort(this.label, this.sort);
  final String label;
  final ReleaseSort sort;
}

class TopTrackersState {
  const TopTrackersState({
    this.releases = const [],
    this.pages = const {},
    this.more = const {},
    this.loading = false,
    this.errors = const {},
    this.sort = TopSort.date,
    this.query = '',
  });

  final List<Release> releases;

  /// Dernière page chargée et « il en reste » par tracker.
  final Map<Tracker, int> pages;
  final Map<Tracker, bool> more;
  final bool loading;
  final Map<Tracker, String> errors;
  final TopSort sort;
  final String query;

  bool get hasMore => more.values.any((m) => m);

  TopTrackersState copyWith({
    List<Release>? releases,
    Map<Tracker, int>? pages,
    Map<Tracker, bool>? more,
    bool? loading,
    Map<Tracker, String>? errors,
  }) =>
      TopTrackersState(
        releases: releases ?? this.releases,
        pages: pages ?? this.pages,
        more: more ?? this.more,
        loading: loading ?? this.loading,
        errors: errors ?? this.errors,
        sort: sort,
        query: query,
      );
}

/// Sorties de tous les trackers configurés, chargées page par page
/// (une page de chaque tracker à la fois).
class TopTrackersNotifier extends Notifier<TopTrackersState> {
  static const perPage = 50;
  int _generation = 0;
  bool _busy = false;

  @override
  TopTrackersState build() {
    ref.watch(trackersProvider);
    Future(loadMore);
    return const TopTrackersState(loading: true);
  }

  /// Change le tri ou la recherche : tout est rechargé.
  void configure({TopSort? sort, String? query}) {
    _generation++;
    _busy = false;
    state = TopTrackersState(
        sort: sort ?? state.sort, query: query ?? state.query, loading: true);
    Future(loadMore);
  }

  Future<void> reload() async {
    configure();
  }

  Future<void> loadMore() async {
    final generation = _generation;
    final trackers = ref.read(trackersProvider);
    final s = state;
    final todo = [
      for (final t in trackers.keys)
        if (s.pages[t] == null || (s.more[t] ?? false)) t,
    ];
    if (todo.isEmpty) {
      if (s.loading) state = s.copyWith(loading: false);
      return;
    }
    if (_busy) return; // Une page déjà en cours de chargement.
    _busy = true;
    state = s.copyWith(loading: true);
    final results = await Future.wait([
      for (final t in todo)
        () async {
          final page = (s.pages[t] ?? 0) + 1;
          try {
            final api = trackers[t]!;
            final sort = api.sorts.contains(s.sort.sort) ? s.sort.sort : ReleaseSort.date;
            final r = await api.releases(
                page: page, perPage: perPage, query: s.query, sort: sort);
            return (t, page, r, null);
          } on Object catch (e) {
            return (t, page, null, '$e');
          }
        }(),
    ]);
    if (!ref.mounted || generation != _generation) return;
    _busy = false;
    final releases = [...state.releases];
    final pages = {...state.pages}, more = {...state.more}, errors = {...state.errors};
    for (final (t, page, r, error) in results) {
      pages[t] = page;
      if (r == null) {
        more[t] = false;
        errors[t] = error!;
        continue;
      }
      errors.remove(t);
      releases.addAll(r.items);
      more[t] = page < r.totalPages && r.items.isNotEmpty;
    }
    state = state.copyWith(
        releases: releases, pages: pages, more: more, errors: errors, loading: false);
  }
}

final topTrackersProvider =
    NotifierProvider<TopTrackersNotifier, TopTrackersState>(TopTrackersNotifier.new);

/// Groupes triés selon le tri choisi ; [only] : les sorties d'un seul
/// tracker (versions, seeders et qualité ne portent alors que sur lui).
List<ReleaseGroup> sortedGroups(TopTrackersState s, {Tracker? only}) {
  final groups = groupReleases(
      only == null ? s.releases : s.releases.where((r) => r.tracker == only));
  return switch (s.sort) {
    TopSort.date => groups..sort((a, b) => b.latest.compareTo(a.latest)),
    TopSort.seeders => groups..sort((a, b) => b.maxSeeders.compareTo(a.maxSeeders)),
  };
}

// ---------------------------------------------------------------------------
// Fiche TMDB d'un groupe

abstract class TmdbMatchStore {
  Map<String, TmdbTitle?> load();
  void save(Map<String, TmdbTitle?> matches);
}

class PrefsTmdbMatchStore implements TmdbMatchStore {
  PrefsTmdbMatchStore(this._prefs);
  final SharedPreferencesWithCache _prefs;
  static const key = 'tmdbMatches';

  @override
  Map<String, TmdbTitle?> load() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return {};
      return {
        for (final MapEntry(:key, :value)
            in (jsonDecode(raw) as Map<String, dynamic>).entries)
          key: value == null
              ? null
              : TmdbTitle.fromJson((value as Map).cast<String, dynamic>()),
      };
    } on Object {
      return {};
    }
  }

  @override
  void save(Map<String, TmdbTitle?> matches) => _prefs.setString(key,
      jsonEncode({for (final e in matches.entries) e.key: e.value?.toJson()}));
}

class MemoryTmdbMatchStore implements TmdbMatchStore {
  var _matches = <String, TmdbTitle?>{};
  @override
  Map<String, TmdbTitle?> load() => {..._matches};
  @override
  void save(Map<String, TmdbTitle?> matches) => _matches = {...matches};
}

final tmdbMatchStoreProvider = Provider<TmdbMatchStore>((ref) {
  try {
    return PrefsTmdbMatchStore(ref.watch(sharedPrefsProvider));
  } on Object {
    return MemoryTmdbMatchStore();
  }
});

/// Fiches TMDB des groupes, par clé de groupe ; null : cherchée, rien trouvé.
/// Gardées sur l'appareil (les 1 000 dernières).
class TmdbMatchNotifier extends Notifier<Map<String, TmdbTitle?>> {
  final _pending = <String>{};

  @override
  Map<String, TmdbTitle?> build() => ref.read(tmdbMatchStoreProvider).load();

  void request(ReleaseGroup g) {
    // Déjà cherchée (fiche gardée avec sa note, ou rien trouvé) ou en cours.
    final known = state.containsKey(g.key) && state[g.key]?.votes != null ||
        state.containsKey(g.key) && state[g.key] == null;
    if (known || _pending.contains(g.key)) return;
    final q = g.tmdbQuery;
    final tmdb = ref.read(tmdbProvider);
    if (q == null || tmdb == null) return; // Ni film ni série : pas de fiche.
    _pending.add(g.key);
    unawaited(() async {
      TmdbTitle? found;
      try {
        found = await tmdb.identify(q.title, q.type, year: q.year);
      } on TmdbException {
        _pending.remove(g.key); // Réessayé plus tard.
        return;
      }
      if (!ref.mounted) return;
      _pending.remove(g.key);
      final entries = {...state, g.key: found}.entries.toList();
      state = Map.fromEntries(
          entries.length > 1000 ? entries.sublist(entries.length - 1000) : entries);
      ref.read(tmdbMatchStoreProvider).save(state);
    }());
  }
}

final tmdbMatchProvider =
    NotifierProvider<TmdbMatchNotifier, Map<String, TmdbTitle?>>(TmdbMatchNotifier.new);

// ---------------------------------------------------------------------------
// Filtres choisis (un par vue)

class DiskFilterNotifier extends Notifier<DiskFilter> {
  @override
  DiskFilter build() => DiskFilter.all;
  void set(DiskFilter f) => state = f;
}

final tmdbDiskFilterProvider =
    NotifierProvider<DiskFilterNotifier, DiskFilter>(DiskFilterNotifier.new);
final trackersDiskFilterProvider =
    NotifierProvider<DiskFilterNotifier, DiskFilter>(DiskFilterNotifier.new);

/// Catégorie choisie dans la vue Trackers (nom d'une catégorie de contenu,
/// commune à tous les trackers) ; null : toutes.
class CategoryFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? category) => state = category;
}

final categoryFilterProvider =
    NotifierProvider<CategoryFilterNotifier, String?>(CategoryFilterNotifier.new);

/// Le filtre laisse-t-il passer ce titre ?
bool passesDiskFilter(DiskFilter f, {required bool onDisk, required bool? available}) =>
    switch (f) {
      DiskFilter.all => true,
      DiskFilter.onDisk => onDisk,
      DiskFilter.toDownload => !onDisk && (available ?? false),
    };

/// Tracker choisi dans la vue Trackers ; null : tous.
class TrackerFilterNotifier extends Notifier<Tracker?> {
  @override
  Tracker? build() => null;
  void set(Tracker? t) => state = t;
}

final trackerFilterProvider =
    NotifierProvider<TrackerFilterNotifier, Tracker?>(TrackerFilterNotifier.new);
