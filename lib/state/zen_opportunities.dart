import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/zen.dart';
import 'c411_overview.dart';
import 'palliative.dart';
import 'releases.dart';
import 'torrents.dart';

/// Classement des opportunités : selon la contrainte (le nombre de torrents
/// dans Transmission, ou la place disque), ou par note — l'indicateur de
/// contribution est la moyenne des notes, et l'arbre de progression compte
/// les torrents bien notés.
enum ZenRanking {
  perTorrent('Par torrent'),
  perGb('Par Go'),
  note('Par note');

  const ZenRanking(this.label);
  final String label;
}

/// Une sortie C411 à télécharger puis partager.
class ZenOpportunity {
  const ZenOpportunity({
    required this.release,
    required this.estimate,
    this.selected = false,
    this.done = false,
    this.detail,
  });

  final Release release;
  final ZenEstimate estimate;
  final bool selected;
  final bool done;

  /// Motif d'échec de l'envoi.
  final String? detail;

  String get key => release.id;
  bool get freeleech => release.isFreeleech;

  /// Ce que le téléchargement coûte au ratio (rien en freeleech).
  int get ratioCost => freeleech ? 0 : release.size;

  ZenOpportunity copyWith({bool? selected, bool? done, String? Function()? detail}) =>
      ZenOpportunity(
        release: release,
        estimate: estimate,
        selected: selected ?? this.selected,
        done: done ?? this.done,
        detail: detail != null ? detail() : this.detail,
      );
}

/// Limites de la sélection ; null : pas de limite.
class ZenLimits {
  const ZenLimits({this.count = 50, this.diskGb, this.useRatio = true, this.freeleechOnly = false});

  /// Torrents à ajouter au plus.
  final int? count;

  /// Place disque à y consacrer, en Go comme le site (1024³ octets).
  final double? diskGb;

  /// Respecter le budget de ratio (téléchargements hors freeleech).
  final bool useRatio;
  final bool freeleechOnly;

  ZenLimits copyWith({int? Function()? count, double? Function()? diskGb, bool? useRatio, bool? freeleechOnly}) =>
      ZenLimits(
        count: count != null ? count() : this.count,
        diskGb: diskGb != null ? diskGb() : this.diskGb,
        useRatio: useRatio ?? this.useRatio,
        freeleechOnly: freeleechOnly ?? this.freeleechOnly,
      );
}

class ZenOpportunitiesState {
  const ZenOpportunitiesState({
    this.items = const [],
    this.ranking = ZenRanking.perTorrent,
    this.limits = const ZenLimits(),
    this.scanning = false,
    this.scanned = 0,
    this.searched = false,
    this.ratioBudget,
    this.sending = false,
    this.sent = 0,
    this.toSend = 0,
    this.error,
  });

  /// Dans l'ordre du classement.
  final List<ZenOpportunity> items;
  final ZenRanking ranking;
  final ZenLimits limits;
  final bool scanning;

  /// Sorties examinées.
  final int scanned;
  final bool searched;

  /// Octets téléchargeables avant le ratio minimum ; null : inconnu.
  final int? ratioBudget;
  final bool sending;
  final int sent;
  final int toSend;
  final String? error;

  List<ZenOpportunity> get selected => [for (final i in items) if (i.selected && !i.done) i];
  double get selectedPerDay => selected.fold(0, (n, i) => n + i.estimate.perDay);
  int get selectedSize => selected.fold(0, (n, i) => n + i.release.size);
  int get selectedRatioCost => selected.fold(0, (n, i) => n + i.ratioCost);

  ZenOpportunitiesState copyWith({
    List<ZenOpportunity>? items,
    ZenRanking? ranking,
    ZenLimits? limits,
    bool? scanning,
    int? scanned,
    bool? searched,
    int? Function()? ratioBudget,
    bool? sending,
    int? sent,
    int? toSend,
    String? Function()? error,
  }) =>
      ZenOpportunitiesState(
        items: items ?? this.items,
        ranking: ranking ?? this.ranking,
        limits: limits ?? this.limits,
        scanning: scanning ?? this.scanning,
        scanned: scanned ?? this.scanned,
        searched: searched ?? this.searched,
        ratioBudget: ratioBudget != null ? ratioBudget() : this.ratioBudget,
        sending: sending ?? this.sending,
        sent: sent ?? this.sent,
        toSend: toSend ?? this.toSend,
        error: error != null ? error() : this.error,
      );
}

/// Classe les sorties selon [ranking] et coche, dans l'ordre, celles qui
/// tiennent dans les [limits] (nombre, disque, ratio) : une sélection
/// gloutonne, pas forcément optimale, mais lisible.
List<ZenOpportunity> rankAndSelect(
  List<ZenOpportunity> items, {
  required ZenRanking ranking,
  required ZenLimits limits,
  int? ratioBudget,
}) {
  final sorted = [
    for (final i in items)
      if (!limits.freeleechOnly || i.freeleech || i.done) i,
  ]..sort((a, b) => switch (ranking) {
        ZenRanking.perGb => b.estimate.perGb.compareTo(a.estimate.perGb),
        ZenRanking.perTorrent => b.estimate.perDay.compareTo(a.estimate.perDay),
        // À note égale, ce qui rapporte le plus.
        ZenRanking.note => switch (b.estimate.note.compareTo(a.estimate.note)) {
            0 => b.estimate.perDay.compareTo(a.estimate.perDay),
            final c => c,
          },
      });
  var count = 0, disk = 0, cost = 0;
  final diskMax = limits.diskGb == null ? null : (limits.diskGb! * (1 << 30)).round();
  final costMax = limits.useRatio ? ratioBudget : null;
  return [
    for (final i in sorted)
      if (i.done)
        i
      else
        () {
          final fits = (limits.count == null || count < limits.count!) &&
              (diskMax == null || disk + i.release.size <= diskMax) &&
              (costMax == null || cost + i.ratioCost <= costMax) &&
              i.estimate.perDay > 0;
          if (fits) {
            count++;
            disk += i.release.size;
            cost += i.ratioCost;
          }
          return i.copyWith(selected: fits);
        }(),
  ];
}

class ZenOpportunitiesNotifier extends Notifier<ZenOpportunitiesState> {
  /// Sorties demandées par page.
  static const perPage = 100;

  /// Pages lues au plus après la première avec des seeders.
  static const maxPages = 15;

  /// Au-delà, la taille × seeders ne rapporte plus rien (sous 100 Go).
  static const maxSeeders = 50;

  int _generation = 0;

  @override
  ZenOpportunitiesState build() => const ZenOpportunitiesState();

  void _reselect() => state = state.copyWith(
        items: rankAndSelect(state.items,
            ranking: state.ranking, limits: state.limits, ratioBudget: state.ratioBudget),
      );

  void setRanking(ZenRanking ranking) {
    state = state.copyWith(ranking: ranking);
    _reselect();
  }

  void setLimits(ZenLimits limits) {
    state = state.copyWith(limits: limits);
    _reselect();
  }

  void toggle(String key, bool selected) => state = state.copyWith(items: [
        for (final i in state.items) i.key == key ? i.copyWith(selected: selected) : i,
      ]);

  void stop() {
    _generation++;
    state = state.copyWith(scanning: false);
  }

  /// Parcourt les sorties C411 par seeders croissants : saute les sorties
  /// sans seeder (dichotomie), puis lit jusqu'à [maxSeeders] seeders.
  Future<void> scan() async {
    final api = ref.read(trackersProvider)[Tracker.c411];
    if (api == null) {
      state = state.copyWith(error: () => 'Configure la clé API C411 dans les Réglages');
      return;
    }
    final generation = ++_generation;
    final overview = ref.read(c411OverviewProvider).value;
    final account = overview?.account;
    final bonusBp = overview?.forecast?.today.bonusBp ?? overview?.history?.latest?.bonusBp;
    final bonus = bonusBp == null ? 0.25 : bonusBp / 10000;
    final present = ref.read(torrentsProvider).hashes;
    final budget = account == null || account.minRatio == null
        ? null
        : downloadBudget(
            uploaded: account.uploaded,
            downloaded: account.downloaded,
            minRatio: account.minRatio!);
    state = state.copyWith(
      items: const [],
      scanning: true,
      scanned: 0,
      searched: true,
      ratioBudget: () => budget,
      error: () => null,
    );

    Future<ReleasePage> get(int page) => api.releases(
        page: page, perPage: perPage, sort: ReleaseSort.seeders, ascending: true);
    final found = <String, ZenOpportunity>{};
    var scanned = 0;
    try {
      final first = await get(1);
      if (generation != _generation || !ref.mounted) return;
      var page = 1;
      var current = first;
      // Pages entières sans seeder : la première qui en a, par dichotomie.
      if (first.items.isNotEmpty && first.items.last.seeders < 1 && first.totalPages > 1) {
        var lo = 2, hi = first.totalPages;
        final seen = <int, ReleasePage>{};
        for (var probes = 0; lo < hi && probes < 14; probes++) {
          final mid = (lo + hi) ~/ 2;
          final r = seen[mid] = await get(mid);
          if (generation != _generation || !ref.mounted) return;
          if (r.items.isEmpty || r.items.last.seeders >= 1) {
            hi = mid;
          } else {
            lo = mid + 1;
          }
        }
        page = lo;
        current = seen[lo] ?? await get(lo);
      }
      for (var read = 0; read < maxPages; read++) {
        if (generation != _generation || !ref.mounted) return;
        scanned += current.items.length;
        for (final r in current.items) {
          if (r.seeders < 1 || r.seeders > maxSeeders || r.size <= 0) continue;
          if (r.infoHash != null && present.contains(r.infoHash)) continue;
          found[r.id] = ZenOpportunity(
            release: r,
            estimate: estimateZen(bytes: r.size, seeders: r.seeders, bonus: bonus, joining: true),
          );
        }
        state = state.copyWith(
          scanned: scanned,
          items: rankAndSelect(found.values.toList(),
              ranking: state.ranking, limits: state.limits, ratioBudget: budget),
        );
        final more = page < current.totalPages &&
            current.items.isNotEmpty &&
            current.items.last.seeders <= maxSeeders;
        if (!more) break;
        page++;
        current = await get(page);
      }
    } on TrackerException catch (e) {
      if (ref.mounted) state = state.copyWith(error: () => e.message);
    } finally {
      if (ref.mounted && generation == _generation) {
        state = state.copyWith(scanning: false);
      }
    }
  }

  /// Ajoute la sélection à Transmission, une par une.
  Future<int> send() async {
    if (state.sending) return 0;
    final api = ref.read(trackersProvider)[Tracker.c411];
    final transmission = ref.read(transmissionProvider);
    final site = ref.read(c411SiteApiProvider);
    if (api == null || transmission == null) {
      state = state.copyWith(error: () => 'Configure C411 et Transmission dans les Réglages');
      return 0;
    }
    final todo = state.selected;
    state = state.copyWith(sending: true, sent: 0, toSend: todo.length, error: () => null);
    var added = 0;
    for (final (n, item) in todo.indexed) {
      if (!ref.mounted) return added;
      state = state.copyWith(sent: n);
      String? failure;
      try {
        await transmission.addTorrent(metainfo: await fetchTorrentFile(api, site, item.release));
        added++;
      } on TrackerException catch (e) {
        failure = e.message;
      } on TransmissionException catch (e) {
        failure = e.message;
      } on Object catch (e) {
        failure = '$e';
      }
      state = state.copyWith(items: [
        for (final i in state.items)
          i.key == item.key
              ? i.copyWith(done: failure == null, selected: failure != null, detail: () => failure)
              : i,
      ]);
    }
    if (!ref.mounted) return added;
    state = state.copyWith(sending: false);
    if (added > 0) await ref.read(torrentsProvider.notifier).refresh(full: true);
    return added;
  }
}

final zenOpportunitiesProvider =
    NotifierProvider<ZenOpportunitiesNotifier, ZenOpportunitiesState>(
        ZenOpportunitiesNotifier.new);
