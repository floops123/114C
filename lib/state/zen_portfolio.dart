import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/c411_profile.dart';
import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/zen.dart';
import 'c411_overview.dart';
import 'palliative.dart';

/// Un torrent C411 de Transmission et ce qu'il rapporte.
class ZenHolding {
  const ZenHolding({
    required this.id,
    required this.hash,
    required this.name,
    required this.seeding,
    required this.estimate,
    this.seedersKnown = true,
    this.site,
  });

  final int id;
  final String hash;
  final String name;

  /// En partage (sinon il ne rapporte rien aujourd'hui).
  final bool seeding;
  final ZenEstimate estimate;

  /// Le tracker a donné un nombre de seeders (sinon : 1, soi).
  final bool seedersKnown;

  /// Sa note et ses Zen du jour selon le site, s'il les donne : la note de
  /// [estimate] est alors celle du site.
  final ZenTorrentScore? site;

  bool get crowded => site?.crowded ?? estimate.crowded;

  /// Zen par jour, s'il reste en partage toute la journée.
  double get perDay => seeding ? estimate.perDay : 0;
}

/// Le portefeuille C411 : chaque torrent, et les totaux.
class ZenPortfolio {
  const ZenPortfolio({required this.holdings, required this.bonus});

  /// Par Zen par jour décroissant.
  final List<ZenHolding> holdings;

  /// Bonus appliqué (celui que le site annonce, sinon la grille).
  final double bonus;

  List<ZenHolding> get seeding => [for (final h in holdings) if (h.seeding) h];

  /// Versement d'une journée complète : Σ poids × note × (1 + bonus) ÷ 7 ;
  /// le site l'arrondit au Zen.
  double get perDay => holdings.fold(0, (n, h) => n + h.perDay);

  /// L'indicateur de contribution : la moyenne des notes des torrents en
  /// partage, pondérée par leur poids (un gros torrent y compte plus).
  double get averageNote {
    final s = seeding;
    final weight = s.fold(0.0, (n, h) => n + h.estimate.weight);
    return weight == 0 ? 0 : s.fold(0.0, (n, h) => n + h.estimate.weight * h.estimate.note) / weight;
  }

  /// Coefficient de poids moyen, pondéré comme le site (Σ P × S ÷ Σ P).
  double get averageWeight {
    final s = seeding;
    return s.isEmpty ? 0 : s.fold(0.0, (n, h) => n + h.estimate.weight) / s.length;
  }

  /// Notes au moins à 1,50 et à 2,00 : l'arbre de progression.
  int get atThreeQuarters => seeding.where((h) => h.estimate.note >= maxNote * 0.75).length;
  int get atMax => seeding.where((h) => h.estimate.note >= maxNote).length;

  double get treeBonusNow => treeBonus([for (final h in seeding) h.estimate.note]);

  /// Torrents en partage dont la note est réduite à la base.
  List<ZenHolding> get crowded => [for (final h in seeding) if (h.crowded) h];

  /// Torrents dont la note vient du site.
  int get siteScored => holdings.where((h) => h.site != null).length;

  /// Paliers de durée atteints dans les [days] prochains jours.
  List<ZenHolding> upcoming({double days = 7}) => [
        for (final h in seeding)
          if (h.estimate.nextStep case final s? when s.inDays <= days) h,
      ]..sort((a, b) => a.estimate.nextStep!.inDays.compareTo(b.estimate.nextStep!.inDays));

  /// Depuis la réponse `torrent-get` (champs de [ZenPortfolio.fields]) : les
  /// torrents C411 terminés. [scores] : les notes du site, par info-hash.
  static ZenPortfolio fromTorrents(
    List<Map<String, dynamic>> torrents, {
    double? bonus,
    Map<String, ZenTorrentScore> scores = const {},
  }) {
    final mine = <(Map<String, dynamic>, int?)>[];
    for (final t in torrents) {
      final stats = [
        for (final s in (t['trackerStats'] as List? ?? const []).whereType<Map>())
          s.cast<String, dynamic>(),
      ];
      final c411 = [
        for (final s in stats)
          if (Tracker.fromAnnounces(['${s['announce'] ?? s['host'] ?? ''}']) == Tracker.c411) s,
      ];
      if (c411.isEmpty) continue;
      if (((t['percentDone'] as num?) ?? 0) < 1) continue;
      final counts = [
        for (final s in c411)
          if ((s['seederCount'] as num?)?.toInt() case final n? when n >= 0) n,
      ];
      mine.add((t, counts.isEmpty ? null : counts.reduce((a, b) => a > b ? a : b)));
    }
    final seedingCount = mine.where((m) => m.$1['status'] == 6).length;
    final applied = bonus ?? gridBonus(seedingCount);
    final holdings = [
      for (final (t, seeders) in mine)
        if ((t['hashString'] as String? ?? '').toLowerCase() case final hash)
        ZenHolding(
          id: (t['id'] as num?)?.toInt() ?? 0,
          hash: hash,
          site: scores[hash],
          name: t['name'] as String? ?? '',
          // 6 : en partage. En file d'attente (5) ou arrêté, il ne
          // partage pas : il ne rapporte rien.
          seeding: t['status'] == 6,
          seedersKnown: seeders != null,
          estimate: estimateZen(
            bytes: ((t['sizeWhenDone'] ?? t['totalSize']) as num?)?.toInt() ?? 0,
            seeders: seeders ?? 1,
            seedDays: ((t['secondsSeeding'] as num?)?.toDouble() ?? 0) / 86400,
            bonus: applied,
            note: scores[hash]?.note,
          ),
        ),
    ];
    holdings.sort((a, b) => b.perDay.compareTo(a.perDay));
    return ZenPortfolio(holdings: holdings, bonus: applied);
  }

  static const fields = [
    'id', 'name', 'hashString', 'status', 'percentDone', 'totalSize',
    'sizeWhenDone', 'secondsSeeding', 'trackerStats',
  ];
}

/// Le portefeuille, lu sur Transmission à la demande (champs lourds :
/// trackerStats), avec les notes du site si le cookie de session est
/// configuré. null : Transmission non configurée.
final zenPortfolioProvider = FutureProvider.autoDispose<ZenPortfolio?>((ref) async {
  final client = ref.watch(transmissionProvider);
  if (client == null) return null;
  final site = ref.watch(c411SiteApiProvider);
  // Bonus du site s'il est connu (grille + arbre), sinon la grille seule.
  final overview = ref.read(c411OverviewProvider).value;
  final bonusBp = overview?.forecast?.today.bonusBp ?? overview?.history?.latest?.bonusBp;
  Future<List<ZenTorrentScore>> scores() async {
    if (site == null) return const [];
    try {
      return await site.allTorrentScores();
    } on Object {
      return const []; // Sans les notes du site : l'estimation locale.
    }
  }

  final (result, siteScores) = await (client.torrentGet(ZenPortfolio.fields), scores()).wait;
  return ZenPortfolio.fromTorrents(
    result.torrents,
    bonus: bonusBp == null ? null : bonusBp / 10000,
    scores: {for (final s in siteScores) ?s.infoHash: s},
  );
});
