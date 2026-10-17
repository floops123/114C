import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/tmdb.dart';
import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/preferences.dart';
import '../core/release_name.dart';
import '../core/release_profile.dart';
import '../core/titles.dart';
import 'torrents.dart';

// Liste de souhaits : films et séries choisis sur TMDB, mémorisés sur
// l'appareil, avec les dates de sortie françaises des films (salles, VOD,
// DVD) relues une fois par jour. La recherche sur les trackers est lancée à
// la main, film par film, sur tous les trackers configurés.

class WishItem {
  const WishItem(this.title, this.addedAt, {this.datesAt});
  final TmdbTitle title;
  final DateTime addedAt;

  /// Dernière lecture des dates françaises.
  final DateTime? datesAt;
}

abstract class WishlistStore {
  List<WishItem> load();
  void save(List<WishItem> items);
}

class PrefsWishlistStore implements WishlistStore {
  PrefsWishlistStore(this._prefs);
  final SharedPreferencesWithCache _prefs;
  static const key = 'wishlist';

  @override
  List<WishItem> load() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return [];
      return [
        for (final e in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
          WishItem(
            TmdbTitle.fromJson((e['title'] as Map).cast<String, dynamic>()),
            DateTime.tryParse(e['added'] as String? ?? '') ?? DateTime(2000),
            datesAt: DateTime.tryParse(e['dates'] as String? ?? ''),
          ),
      ];
    } on Object {
      return [];
    }
  }

  @override
  void save(List<WishItem> items) => _prefs.setString(
      key,
      jsonEncode([
        for (final i in items)
          {
            'title': i.title.toJson(),
            'added': i.addedAt.toIso8601String(),
            'dates': ?i.datesAt?.toIso8601String(),
          },
      ]));
}

class MemoryWishlistStore implements WishlistStore {
  var _items = <WishItem>[];
  @override
  List<WishItem> load() => [..._items];
  @override
  void save(List<WishItem> items) => _items = [...items];
}

final wishlistStoreProvider = Provider<WishlistStore>((ref) {
  try {
    return PrefsWishlistStore(ref.watch(sharedPrefsProvider));
  } on Object {
    return MemoryWishlistStore(); // Préférences non initialisées (tests).
  }
});

/// Souhaits, les prochaines sorties d'abord (dates inconnues à la fin).
class WishlistNotifier extends Notifier<List<WishItem>> {
  static const refreshAfter = Duration(days: 1);

  @override
  List<WishItem> build() => _sorted(ref.watch(wishlistStoreProvider).load());

  static List<WishItem> _sorted(List<WishItem> items) => items
    ..sort((a, b) {
      final da = a.title.nextDate, db = b.title.nextDate;
      if (da == null || db == null) {
        return (da == null ? 1 : 0) - (db == null ? 1 : 0);
      }
      return da.compareTo(db);
    });

  bool contains(TmdbTitle t) => state.any((i) => i.title.key == t.key);

  void toggle(TmdbTitle t) => contains(t) ? remove(t) : add(t);

  void add(TmdbTitle t) {
    if (contains(t)) return;
    _save([...state, WishItem(t, DateTime.now())]);
    if (t.type == TmdbType.movie) _readDates([t]);
  }

  /// Relit les dates françaises des films vues il y a plus de [refreshAfter]
  /// (elles se précisent à l'approche de la sortie, la VOD arrive après).
  Future<void> refreshDates() => _readDates([
        for (final i in state)
          if (i.title.type == TmdbType.movie &&
              (i.datesAt == null ||
                  DateTime.now().difference(i.datesAt!) > refreshAfter))
            i.title,
      ]);

  Future<void> _readDates(List<TmdbTitle> titles) async {
    final api = ref.read(tmdbProvider);
    if (api == null) return;
    for (final t in titles) {
      final FrenchDates dates;
      try {
        dates = await api.frenchDates(t.id);
      } on TmdbException {
        continue; // Nouvel essai au prochain rafraîchissement.
      }
      if (!ref.mounted) return;
      _save([
        for (final i in state)
          i.title.key == t.key
              ? WishItem(i.title.withFrench(dates), i.addedAt,
                  datesAt: DateTime.now())
              : i,
      ]);
    }
  }

  void remove(TmdbTitle t) =>
      _save([for (final i in state) if (i.title.key != t.key) i]);

  void _save(List<WishItem> items) {
    ref.read(wishlistStoreProvider).save(items);
    state = _sorted(items);
  }
}

final wishlistProvider =
    NotifierProvider<WishlistNotifier, List<WishItem>>(WishlistNotifier.new);

TmdbApi _tmdb(Ref ref) =>
    ref.watch(tmdbProvider) ??
    (throw const TmdbException('Ajoute une clé TMDB dans Réglages'));

final tmdbSearchProvider = FutureProvider.autoDispose
    .family<List<TmdbTitle>, String>((ref, query) => _tmdb(ref).search(query));

/// Première page d'une rangée de la page Découvrir.
final tmdbFeedProvider = FutureProvider.autoDispose
    .family<List<TmdbTitle>, TmdbFeed>(
        (ref, feed) async => (await _tmdb(ref).feed(feed)).items);

final tmdbGenresProvider = FutureProvider.autoDispose
    .family<List<TmdbGenre>, TmdbType>((ref, type) => _tmdb(ref).genres(type));

final tmdbDetailsProvider = FutureProvider.autoDispose
    .family<TmdbDetails, TmdbTitle>((ref, t) => _tmdb(ref).details(t));

/// Recherches à essayer pour un titre, dans l'ordre : au format des noms de
/// release (« Dune.Deuxieme.partie » : C411 cherche un morceau du nom), avec
/// des espaces (noms écrits ainsi sur AstraTorrent), puis le titre tel quel.
List<String> releaseQueries(String title) {
  final words = titleWords(title);
  return {
    if (words.isNotEmpty) words.join('.'),
    if (words.isNotEmpty) words.join(' '),
    title.trim(),
  }.where((q) => q.isNotEmpty).toList();
}

/// Sortie rattachée par le tracker à une fiche (C411) : même type, même
/// titre (français ou original) et même année à un an près. Chez C411, films
/// et séries ont toujours leur fiche : une sortie sans fiche (livre, logiciel…)
/// est écartée. Les autres trackers n'en ont pas : [searchWish] se fie alors
/// au nom.
bool matchesMedia(Release r, TmdbTitle t) {
  final kind = r.mediaKind;
  if (kind == null) return r.tracker != Tracker.c411;
  if (kind != t.type.name) return false;
  final wanted = {titleKey(t.title), if (t.originalTitle != null) titleKey(t.originalTitle!)};
  final titles = {
    if (r.title != null) titleKey(r.title!),
    if (r.originalTitle != null) titleKey(r.originalTitle!),
  };
  if (!titles.any(wanted.contains)) return false;
  final year = t.year;
  return t.type != TmdbType.movie ||
      year == null ||
      r.year == null ||
      (r.year! - year).abs() <= 1;
}

/// Sorties d'un tracker pour un souhait : recherche par titre français puis
/// original (voir [releaseQueries] ; on passe à la variante suivante tant
/// qu'il n'y a rien). Les sorties rattachées à une autre fiche sont écartées
/// ([matchesMedia]) ; pour un film sans fiche, celles d'une autre année (à un
/// an près) aussi. La bonne année passe devant, puis les plus seedées.
Future<List<Release>> searchWish(TrackerApi api, TmdbTitle t) async {
  final found = <String, Release>{};
  final titles = {
    t.title.trim(),
    if (t.originalTitle != null) t.originalTitle!.trim(),
  }..remove('');
  final tried = <String>{};
  for (final title in titles) {
    for (final q in releaseQueries(title)) {
      if (!tried.add(q)) continue;
      final items = [
        for (final r in (await api.releases(query: q, perPage: 50)).items)
          if (matchesMedia(r, t)) r,
      ];
      for (final r in items) {
        found.putIfAbsent(r.id, () => r);
      }
      if (items.isNotEmpty) break;
    }
  }
  final year = t.year;
  bool sameYear(Release r) => year != null && r.year == year;
  return [
    for (final r in found.values)
      if (t.type != TmdbType.movie ||
          year == null ||
          r.year == null ||
          (r.year! - year).abs() <= 1)
        r,
  ]..sort((a, b) {
      if (sameYear(a) != sameYear(b)) return sameYear(a) ? -1 : 1;
      return b.seeders.compareTo(a.seeders);
    });
}

final wishSearchProvider = FutureProvider.autoDispose
    .family<List<Release>, (Tracker, TmdbTitle)>((ref, args) {
  final (tracker, title) = args;
  final api = ref.watch(trackersProvider)[tracker];
  if (api == null) return const [];
  return searchWish(api, title);
});

/// Classement des résultats d'un souhait. [quality] et [type] regroupent les
/// sorties sous des intertitres ; dans un groupe, les plus seedées d'abord.
enum WishSort {
  relevance('Pertinence'),
  quality('Qualité'),
  profile('Profil C411'),
  size('Taille'),
  seeders('Seeders'),
  date('Date');

  const WishSort(this.label);
  final String label;

  /// Sens par défaut : les meilleures, les plus grosses, les plus récentes
  /// d'abord.
  bool get ascendingByDefault => false;
  bool get grouped => this == quality || this == profile;
}

/// Sources de la meilleure à la moins bonne.
const releaseTypes = [
  'Remux', 'BluRay', 'WEB-DL', 'WEB', 'WEBRip', 'HDLight', 'BDRip', 'HDTV',
  'HDRip', 'DVDRip',
];

const _resolutions = {
  '2160p': 4, '1080p': 3, '1080i': 3, '720p': 2, '576p': 1, '480p': 1,
};

/// Résolution d'après le nom (plus fiable d'un tracker à l'autre que les
/// métadonnées), sinon celle du tracker.
String? qualityOf(Release r) {
  final parsed = ReleaseName.parse(r.name).resolution ?? r.resolution;
  return _resolutions.containsKey(parsed?.toLowerCase())
      ? parsed!.toLowerCase()
      : null;
}

final _remux = RegExp(r'(^|[.\s_-])remux([.\s_-]|$)', caseSensitive: false);

/// Source normalisée (« BluRay », « WEB-DL »…), ou null si inconnue. Un
/// Remux s'écrit souvent après « BluRay » : il est cherché à part.
String? typeOf(Release r) {
  if (_remux.hasMatch(r.name)) return 'Remux';
  final parsed = ReleaseName.parse(r.name).source ?? r.source;
  if (parsed == null) return null;
  final upper = parsed.toUpperCase().replaceAll(' ', '');
  for (final t in releaseTypes) {
    if (t.toUpperCase() == upper) return t;
  }
  return upper == 'WEBDL' ? 'WEB-DL' : null;
}

int _qualityRank(Release r) => _resolutions[qualityOf(r)] ?? 0;

/// Rang de profil C411 : du plus exigeant (Home Cinéma Pure) au plus léger,
/// les sorties non classées à la fin.
int _profileRank(Release r) =>
    profileOf(r)?.index ?? C411Profile.values.length;

/// Rang de source : 0 pour la meilleure, la liste entière pour une inconnue.
int _typeRank(Release r) {
  final i = releaseTypes.indexOf(typeOf(r) ?? '');
  return i < 0 ? releaseTypes.length : i;
}

/// Résultats classés, éventuellement en groupes titrés (titre null : pas de
/// groupe). [items] arrive dans l'ordre de pertinence de [searchWish].
List<(String?, List<Release>)> sortWish(
    List<Release> items, WishSort sort, bool ascending) {
  int bySeeders(Release a, Release b) => b.seeders.compareTo(a.seeders);
  final sign = ascending ? -1 : 1;
  final list = [...items];
  switch (sort) {
    case WishSort.relevance:
      if (ascending) return [(null, list.reversed.toList())];
      return [(null, list)];
    case WishSort.size:
      list.sort((a, b) => sign * b.size.compareTo(a.size));
    case WishSort.seeders:
      list.sort((a, b) => sign * bySeeders(a, b));
    case WishSort.date:
      list.sort((a, b) => sign * b.createdAt.compareTo(a.createdAt));
    case WishSort.quality:
      list.sort((a, b) {
        final q = sign * (_qualityRank(b) - _qualityRank(a));
        if (q != 0) return q;
        final t = _typeRank(a) - _typeRank(b);
        return t != 0 ? t : bySeeders(a, b);
      });
    case WishSort.profile:
      list.sort((a, b) {
        final p = sign * (_profileRank(a) - _profileRank(b));
        if (p != 0) return p;
        final q = _qualityRank(b) - _qualityRank(a);
        if (q != 0) return q;
        final t = _typeRank(a) - _typeRank(b);
        return t != 0 ? t : bySeeders(a, b);
      });
  }
  if (!sort.grouped) return [(null, list)];

  // Groupes consécutifs (la liste est déjà triée par la clé du groupe).
  String key(Release r) => sort == WishSort.quality
      ? qualityOf(r) ?? 'Qualité inconnue'
      : profileOf(r)?.label ?? 'Non classé';
  final groups = <(String?, List<Release>)>[];
  for (final r in list) {
    if (groups.isEmpty || groups.last.$1 != key(r)) groups.add((key(r), []));
    groups.last.$2.add(r);
  }
  return groups;
}

/// Classement choisi sur la page de résultats (commun à tous les onglets).
class WishSortNotifier extends Notifier<(WishSort, bool)> {
  @override
  (WishSort, bool) build() => (WishSort.relevance, false);

  void set(WishSort sort, bool ascending) => state = (sort, ascending);
}

final wishSortProvider =
    NotifierProvider<WishSortNotifier, (WishSort, bool)>(WishSortNotifier.new);

/// Résumé des sorties d'un tracker pour la fiche d'un titre.
({
  String? bestQuality,
  List<String> languages,
  int maxSeeders,
  int freeleech,
  bool hdr,
  bool atmos,
}) summarizeReleases(List<Release> items) {
  String? best;
  var bestRank = 0;
  final languages = <String>{};
  var maxSeeders = 0, freeleech = 0;
  var hdr = false, atmos = false;
  for (final r in items) {
    final rank = _qualityRank(r);
    if (rank > bestRank) {
      bestRank = rank;
      best = qualityOf(r);
    }
    languages.addAll(r.languages.isNotEmpty
        ? r.languages
        : ReleaseName.parse(r.name).languages);
    if (r.seeders > maxSeeders) maxSeeders = r.seeders;
    if (r.isFreeleech) freeleech++;
    final f = r.hdrFormat?.toUpperCase();
    hdr |= f != null && f.isNotEmpty && f != 'SDR' ||
        RegExp(r'(^|[.\s_-])(HDR|HDR10|DV|DoVi)', caseSensitive: false)
            .hasMatch(r.name);
    atmos |= (r.audioCodec ?? r.name).toLowerCase().contains('atmos');
  }
  return (
    bestQuality: best,
    languages: languages.toList(),
    maxSeeders: maxSeeders,
    freeleech: freeleech,
    hdr: hdr,
    atmos: atmos,
  );
}

/// Torrents de Transmission correspondant à un titre : même infohash qu'une
/// sortie déjà trouvée sur un tracker ([known]), ou nom de torrent donnant le
/// même titre (français ou original) et, pour un film, la même année à un an
/// près.
List<Torrent> torrentsForTitle(Iterable<Torrent> torrents, TmdbTitle t,
    {Set<String> known = const {}}) {
  final wanted = {titleKey(t.title), if (t.originalTitle != null) titleKey(t.originalTitle!)}
    ..remove('');
  return [
    for (final torrent in torrents)
      if (known.contains(torrent.hash) || _nameMatches(torrent.name, t, wanted))
        torrent,
  ];
}

bool _nameMatches(String name, TmdbTitle t, Set<String> wanted) {
  final parsed = ReleaseName.parse(name);
  if (!wanted.contains(titleKey(parsed.title))) return false;
  final year = t.year;
  return t.type != TmdbType.movie ||
      year == null ||
      parsed.year == null ||
      (parsed.year! - year).abs() <= 1;
}

/// Torrents de Transmission pour un titre, mis à jour avec la liste. Les
/// recherches sur les trackers déjà faites pour ce titre servent aussi
/// (infohash), sans en lancer de nouvelles.
final localTorrentsProvider =
    Provider.autoDispose.family<List<Torrent>, TmdbTitle>((ref, t) {
  final torrents = ref.watch(torrentsProvider.select((s) => s.byId));
  final known = <String>{};
  for (final tracker in ref.watch(trackersProvider).keys) {
    final search = wishSearchProvider((tracker, t));
    if (!ref.exists(search)) continue;
    for (final r in ref.watch(search).value ?? const <Release>[]) {
      if (r.infoHash != null) known.add(r.infoHash!);
    }
  }
  return torrentsForTitle(torrents.values, t, known: known);
});
