import 'dart:typed_data';

import 'package:c411_remote/api/c411_profile.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/zen.dart';
import 'package:c411_remote/state/bulk_import.dart';
import 'package:c411_remote/state/c411_overview.dart';
import 'package:c411_remote/state/palliative.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:c411_remote/state/zen_opportunities.dart';
import 'package:c411_remote/state/zen_portfolio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _go = 1000000000;
const _mo = 1000000;

void main() {
  group('règles Swarm Keeper', () {
    test('coefficient de poids : les exemples du site', () {
      expect(weightOf(1 * _mo), closeTo(0.06, 0.005));
      expect(weightOf(100 * _mo), closeTo(0.08, 0.005));
      expect(weightOf(500 * _mo), closeTo(0.18, 0.005));
      expect(weightOf(_go), closeTo(0.29, 0.005));
      expect(weightOf(4 * _go), 1.0);
      expect(weightOf(25 * _go), closeTo(1.24, 0.005));
      expect(weightOf(60 * _go), closeTo(1.38, 0.005));
      // « 4,00 Go » et « 1,00 Go » affichés (base 1024).
      expect(weightOf(4 << 30), closeTo(1.01, 0.005));
      expect(weightOf(1 << 30), closeTo(0.31, 0.005));
    });

    test('durée de seed : paliers et le suivant', () {
      expect([for (final d in [0, 6.9, 7, 29, 30, 89, 90, 179, 180, 400]) durationBonus(d.toDouble())],
          [0, 0, 0.10, 0.10, 0.25, 0.25, 0.35, 0.35, 0.50, 0.50]);
      final next = nextDurationStep(4)!;
      expect(next.inDays, 3);
      expect(next.gain, 0.10);
      expect(nextDurationStep(30)!.gain, closeTo(0.10, 1e-9), reason: '0,25 → 0,35');
      expect(nextDurationStep(200), isNull);
    });

    test('taille × seeders : le tableau du site', () {
      expect(sizeSeedersBonus(500 * _mo, 5), 0.20);
      expect(sizeSeedersBonus(500 * _mo, 30), 0, reason: 'petit et trop seedé');
      expect(sizeSeedersBonus(4 * _go, 10), 0.35);
      expect(sizeSeedersBonus(4 * _go, 11), 0.20);
      expect(sizeSeedersBonus(4 * _go, 30), 0.35, reason: 'oui, comme sur le site');
      expect(sizeSeedersBonus(12 * _go, 5), 0.50);
      expect(sizeSeedersBonus(60 * _go, 50), 0.50);
      expect(sizeSeedersBonus(60 * _go, 51), 0);
      expect(sizeSeedersBonus(150 * _go, 120), 0.35);
      expect(sizeSeedersBonus(150 * _go, 200), 0);
      expect(sizeSeedersBonus(12 * _go, 0), 0, reason: 'sans seeder : rien');
    });

    test('note plafonnée, gain par jour', () {
      expect(noteOf(bytes: 12 * _go, seeders: 5, seedDays: 400), maxNote);
      final e = estimateZen(bytes: 4 * _go, seeders: 5, bonus: 0.25);
      expect(e.note, 1.35);
      expect(e.perDay, closeTo(1.0 * 1.35 * 1.25 / 7, 1e-9));
      expect(e.perGb, closeTo(e.perDay / 4, 1e-9));
    });

    test('en arrivant, on compte parmi les seeders (10 + soi = 11)', () {
      expect(estimateZen(bytes: 4 * _go, seeders: 10).note, 1.35);
      expect(estimateZen(bytes: 4 * _go, seeders: 10, joining: true).note, 1.20);
      expect(estimateZen(bytes: 4 * _go, seeders: 0, joining: true).seeders, 1,
          reason: 'réanimation : seul seeder');
    });

    test('grille de bonus et arbre de progression', () {
      expect([for (final n in [4, 5, 15, 50, 100, 150, 199, 200, 400, 734]) gridBonus(n)],
          [0, 0.20, 0.25, 0.20, 0.175, 0.20, 0.20, 0.21, 0.25, 0.25]);
      expect(treeBonus(List.filled(99, 1.6)), 0);
      expect(treeBonus(List.filled(100, 1.6)), 0.01);
      expect(treeBonus(List.filled(200, 2.0)), 0.03);
    });

    test('marge de téléchargement : l’exemple du site', () {
      // Upload 1 To (crédit de 180 Go inclus), download 982,8 Go → 276,9 Go,
      // en Go du site (base 1024).
      const gio = 1 << 30;
      final m = downloadBudget(
          uploaded: (1007.76 * gio).round(), downloaded: (982.8 * gio).round(), minRatio: 0.8);
      expect(m / gio, closeTo(276.9, 0.05));
    });

    test('budget de ratio : vos chiffres', () {
      final b = downloadBudget(uploaded: 1024897929290, downloaded: 958604757127, minRatio: 0.8);
      expect(b / 1e9, closeTo(322.5, 0.5));
      expect(downloadBudget(uploaded: 10, downloaded: 100, minRatio: 0.8), 0);
    });
  });

  test('portefeuille : les torrents C411 de Transmission', () {
    Map<String, dynamic> t(int id, {String announce = 'https://c411.org/announce/x',
            int status = 6, double done = 1, int seeders = 5, double days = 40, int size = 12 * _go}) =>
        {
          'id': id,
          'name': 'T$id',
          'hashString': 'H$id',
          'status': status,
          'percentDone': done,
          'sizeWhenDone': size,
          'secondsSeeding': days * 86400,
          'trackerStats': [
            {'announce': announce, 'seederCount': seeders},
          ],
        };
    final p = ZenPortfolio.fromTorrents([
      t(1),
      t(2, announce: 'https://tr4ker.net/announce'), // autre tracker
      t(3, done: 0.5), // pas fini
      t(4, status: 0), // à l'arrêt
      t(5, seeders: -1, size: 500 * _mo, days: 3), // seeders inconnus
      t(6, seeders: 80, size: 2 * _go, days: 5), // trop seedé
    ], bonus: 0.25);
    expect(p.holdings.map((h) => h.id), unorderedEquals([1, 4, 5, 6]));
    expect(p.seeding.map((h) => h.id), unorderedEquals([1, 5, 6]));
    final one = p.holdings.firstWhere((h) => h.id == 1);
    expect(one.hash, 'h1');
    expect(one.estimate.note, closeTo(1 + 0.25 + 0.50, 1e-9));
    expect(p.holdings.firstWhere((h) => h.id == 4).perDay, 0, reason: 'à l’arrêt');
    expect(p.holdings.firstWhere((h) => h.id == 5).seedersKnown, isFalse);
    expect(p.crowded.map((h) => h.id), [6]);
    expect(p.upcoming(days: 7).map((h) => h.id), unorderedEquals([5, 6]),
        reason: 'paliers de 7 jours dans 4 et 2 jours');
    // Σ poids × note moyenne × (1 + bonus) ÷ 7.
    final seeding = [for (final h in p.seeding) h.estimate];
    expect(
        p.perDay,
        closeTo(
            seeding.fold(0.0, (n, e) => n + e.weight) *
                seeding.fold(0.0, (n, e) => n + e.note) /
                3 *
                1.25 /
                7,
            1e-9));
    final stopped = p.holdings.firstWhere((h) => h.id == 4);
    expect(stopped.contribution, greaterThan(0), reason: 'ce qu’il rapporterait relancé');
    expect(p.holdings.where((h) => h.seeding).fold(0.0, (n, h) => n + h.perDay),
        isNot(closeTo(p.perDay, 1e-6)),
        reason: 'chaque torrent pèse aussi sur la note moyenne');
    expect(ZenPortfolio.fromTorrents([t(1)]).bonus, 0, reason: 'grille : moins de 5');
  });

  test('sélection gloutonne : nombre, disque, ratio, freeleech', () {
    ZenOpportunity o(String id, int size, int seeders, {bool fl = false}) => ZenOpportunity(
          release: Release(
              tracker: Tracker.c411, id: id, name: id, size: size, seeders: seeders,
              isFreeleech: fl, createdAt: DateTime(2026)),
          estimate: estimateZen(bytes: size, seeders: seeders, joining: true),
        );
    final items = [
      o('gros', 40 * _go, 3),
      o('moyen', 12 * _go, 3, fl: true),
      o('petit', 300 * _mo, 3),
    ];
    List<String> pick(ZenLimits limits, {ZenRanking ranking = ZenRanking.perTorrent, int? budget}) => [
          for (final i in rankAndSelect(items, ranking: ranking, limits: limits, ratioBudget: budget))
            if (i.selected) i.key,
        ];
    expect(pick(const ZenLimits(count: null, useRatio: false)), ['gros', 'moyen'],
        reason: 'le petit (note 1,20) ferait baisser la moyenne (1,50) plus qu’il ne rapporte');
    expect(pick(const ZenLimits(count: 1, useRatio: false)), ['gros']);
    expect(pick(const ZenLimits(count: null, diskGb: 20, useRatio: false)), ['moyen', 'petit']);
    expect(pick(const ZenLimits(count: null), budget: 1 * _go), ['moyen', 'petit'],
        reason: 'le freeleech ne coûte rien au ratio');
    expect(pick(const ZenLimits(count: null, useRatio: false, freeleechOnly: true)), ['moyen']);
    // Un portefeuille de 100 torrents à 1,50 de moyenne.
    const big = ZenBase(count: 100, weight: 100, note: 1.5);
    final withBase = rankAndSelect(items,
        ranking: ZenRanking.perGb, limits: const ZenLimits(count: null, useRatio: false), base: big);
    expect([for (final i in withBase) if (i.selected) i.key], unorderedEquals(['gros', 'moyen']));
    expect(
        rankAndSelect(items, ranking: ZenRanking.perGb, limits: const ZenLimits(useRatio: false))
            .first
            .key,
        'petit',
        reason: 'par Go, le petit gagne');
    // Par note : 12 Go et 40 Go à 3 seeders (+0,50) passent devant le petit
    // (+0,20) ; à note égale, le plus rentable (40 Go) d'abord.
    expect([
      for (final i in rankAndSelect(items, ranking: ZenRanking.note, limits: const ZenLimits(useRatio: false)))
        (i.key, i.estimate.note)
    ], [('gros', 1.5), ('moyen', 1.5), ('petit', 1.2)]);
  });

  test('note moyenne : un ajout la fait monter ou baisser pour tous', () {
    const base = ZenBase(count: 100, weight: 100, note: 1.5);
    final low = estimateZen(bytes: 500 * _mo, seeders: 3, joining: true); // 1,20
    final even = estimateZen(bytes: 40 * _go, seeders: 3, joining: true); // 1,50
    final high = estimateZen(bytes: 40 * _go, seeders: 3, seedDays: 200, joining: true); // 2,00
    expect(low.perDay, greaterThan(0));
    expect(base.gain(low, 0.25), lessThan(0), reason: 'il dilue la note des 100 autres');
    expect(base.gain(even, 0.25), closeTo(even.perDay, 1e-9), reason: 'à la moyenne : son poids seul');
    expect(base.gain(high, 0.25), greaterThan(base.gain(even, 0.25) * 1.25),
        reason: 'il fait monter la note des 100 autres');
    expect(base.add(low).contribution(low, 0.25), closeTo(base.gain(low, 0.25), 1e-9));
    expect(ZenBase.empty.gain(low, 0.25), closeTo(low.perDay, 1e-9));
    expect(ZenBase.of([even, low]).note, closeTo(1.35, 1e-9));
  });

  test('notes du site : forecast-torrents', () {
    final page = ZenTorrentScores.parse({
      'forecastRq': 25,
      'projectedRq': 34,
      'countedTorrents': 1535,
      'releases': {
        'total': 1535,
        'items': [
          {
            'torrent': {'id': 41243, 'name': 'Black.Lightning', 'infoHash': '99D924F6', 'categoryId': 1},
            'zen': 0.23424976677499976,
            'projectedZen': 0.3127136728135664,
            'weightBp': 7938,
            'sizeWeightBp': 13268,
            'score': {
              'categorySlug': 'films-videos',
              'durationBand': 0,
              'sizeBand': 3,
              'seedersBand': 1,
              'baseBp': 100,
              'criteriaBp': [0, 35],
            },
          },
        ],
      },
    });
    expect((page.forecast, page.projected, page.counted, page.total), (25, 34, 1535, 1535));
    final s = page.items.single;
    expect(s.infoHash, '99d924f6');
    expect(s.note, 1.35);
    expect(s.share, closeTo(0.7938, 1e-9));
    expect(s.weight, closeTo(1.3268, 1e-9));
    expect(s.crowded, isFalse);
    // Le site paie chaque torrent à sa note : P × S × note, au même facteur.
    final p = ZenPortfolio.fromTorrents([
      {
        'id': 1,
        'name': 'Black.Lightning',
        'hashString': '99D924F6',
        'status': 6,
        'percentDone': 1,
        'sizeWhenDone': 12 * _go,
        'secondsSeeding': 400 * 86400, // Transmission dirait 2,00
        'trackerStats': [
          {'announce': 'https://c411.org/announce/x', 'seederCount': 3},
        ],
      },
    ], bonus: 0.25, scores: {'99d924f6': s});
    expect(p.holdings.single.estimate.note, 1.35, reason: 'la note du site prime');
    expect(p.siteScored, 1);
  });

  test('Zen des niveaux d’XP : l’échelle du site', () {
    expect(zenForLevel(1), 1);
    expect(zenForLevel(7), 2);
    expect(zenForLevel(152), 12);
    expect(zenForLevel(450), 27);
    int upTo(int n) => [for (var l = 1; l <= n; l++) zenForLevel(l)].fold(0, (a, b) => a + b);
    expect(upTo(399), 6174, reason: 'en arrivant au niveau 400');
    expect(upTo(400), 6201);
  });

  test('import en masse : ordre « Plus rentables »', () {
    Release r(String id, int size, int seeders, {Tracker t = Tracker.c411}) =>
        Release(tracker: t, id: id, name: id, size: size, seeders: seeders, createdAt: DateTime(2026));
    final list = [r('a', 300 * _mo, 30), r('b', 12 * _go, 3), r('c', 12 * _go, 3, t: Tracker.tr4ker)]
      ..sort(BulkOrder.zen.compare);
    expect(list.map((x) => x.id), ['b', 'a', 'c']);
    expect(BulkOrder.zenOf(list.last), 0, reason: 'Zen : C411 seulement');
  });

  group('opportunités : recherche et ajout', () {
    test('saute les sorties sans seeder, garde 1 à 50, sans ce qui est déjà là', () async {
      final c411 = _Catalog();
      final transmission = _Transmission();
      final container = ProviderContainer(overrides: [
        trackersProvider.overrideWithValue({Tracker.c411: c411}),
        transmissionProvider.overrideWithValue(transmission),
        torrentsProvider.overrideWith(_Torrents.new),
        c411SiteApiProvider.overrideWithValue(null),
        c411OverviewProvider.overrideWith((ref) async => _overview),
      ]);
      addTearDown(container.dispose);
      await container.read(c411OverviewProvider.future);
      final notifier = container.read(zenOpportunitiesProvider.notifier);
      notifier.setLimits(const ZenLimits(count: 3, useRatio: true));
      await notifier.scan();

      final state = container.read(zenOpportunitiesProvider);
      expect(state.error, isNull);
      expect(state.ratioBudget! / 1e9, closeTo(322.5, 0.5));
      final seeders = [for (final i in state.items) i.release.seeders];
      expect(seeders.every((s) => s >= 1 && s <= 50), isTrue);
      expect(state.items.any((i) => i.release.infoHash == 'h105'), isFalse,
          reason: 'déjà dans Transmission');
      expect(c411.asked.length, lessThan(20), reason: 'dichotomie, pas toutes les pages');
      expect(state.selected, hasLength(3));
      // Classement par Zen/j décroissant.
      final perDay = [for (final i in state.items) i.gain];
      expect(perDay, [...perDay]..sort((a, b) => b.compareTo(a)));

      expect(await notifier.send(), 3);
      expect(transmission.added, 3);
      expect(container.read(zenOpportunitiesProvider).items.where((i) => i.done), hasLength(3));
    });
  });
}

final _overview = C411Overview(
  account: C411Account(
      username: 'moi', uploaded: 1024897929290, downloaded: 958604757127, minRatio: 0.8),
);

/// 2 000 sorties triées par seeders croissants : les 1 200 premières sans
/// seeder, puis 1, 2, 3… seeders.
class _Catalog implements TrackerApi {
  final asked = <int>[];
  late final all = [
    for (var i = 0; i < 2000; i++)
      Release(
        tracker: Tracker.c411,
        id: '$i',
        name: 'R$i',
        infoHash: 'h$i',
        size: (1 + i % 30) * _go,
        seeders: i < 1200 ? 0 : (i - 1200) ~/ 10 + 1,
        createdAt: DateTime(2026),
      ),
  ];

  @override
  Tracker get tracker => Tracker.c411;
  @override
  void close() {}
  @override
  List<ReleaseSort> get sorts => ReleaseSort.values;
  @override
  Set<ReleaseSort> get serverSorts => ReleaseSort.values.toSet();
  @override
  Future<List<Category>> categories() async => const [];
  @override
  Future<ReleasePage> releases(
      {int page = 1,
      int perPage = 50,
      int? categoryId,
      int? subcategoryId,
      String query = '',
      ReleaseSort sort = ReleaseSort.date,
      bool ascending = false}) async {
    asked.add(page);
    expect((sort, ascending), (ReleaseSort.seeders, true));
    final items = all.skip((page - 1) * perPage).take(perPage).toList();
    return ReleasePage(items, page, (all.length / perPage).ceil(), all.length);
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async =>
      Uint8List.fromList('d4:infod4:name1:xee'.codeUnits);
}

class _Torrents extends TorrentsNotifier {
  @override
  TorrentsState build() => const TorrentsState(loaded: true, hashes: {'h105', 'h1205'});
}

class _Transmission extends TransmissionClient {
  _Transmission() : super(url: 'http://x');
  var added = 0;
  @override
  Future<({bool added, String? hash})> addTorrentWithHash({
    Uint8List? metainfo,
    String? filename,
    AddOptions options = const AddOptions(),
  }) async {
    added++;
    return (added: true, hash: null);
  }

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async =>
      (torrents: <Map<String, dynamic>>[], removed: <int>[]);
}
