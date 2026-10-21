// Compte C411 vu par le site (cookie de session) : profil, niveau, et le
// « Zen » — la monnaie versée chaque nuit pour le partage.
//
// Versement d'une journée, tel que le site l'explique :
//   versement = arrondi( T × P × S × I ÷ 7 × (1 + B) )
// T : torrents comptés ; P : part de la journée partagée ; S : coefficient de
// poids moyen ; I : indicateur de contribution (2,00 au plus dans la classe) ;
// B : bonus de pondération. L'API donne T, et en points de base (1/10 000)
// la somme des parts (Σ P) et des poids (Σ P × S) : P = ΣP ÷ T, S = ΣPS ÷ ΣP.

import '../core/zen.dart';

/// Valeur entière ou décimale d'un JSON.
double _num(Object? v) => (v as num?)?.toDouble() ?? 0;
int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// `/api/auth/me` : le compte.
class C411Account {
  const C411Account({
    required this.username,
    this.badge,
    this.classSlug,
    this.classTier,
    this.classLevel,
    this.emblemUrl,
    this.uploaded = 0,
    this.downloaded = 0,
    this.uploadCredit = 0,
    this.downloadCredit = 0,
    this.ratio,
    this.minRatio,
    this.canDownload = true,
    this.canDownloadReason,
    this.warnings = 0,
    this.freeleech = false,
    this.freeDownloads = 0,
    this.donor = false,
    this.createdAt,
  });

  final String username;

  /// Rang affiché (« Membre »…).
  final String? badge;

  /// Classe de jeu (`swarm_keeper`…), palier (`bronze`) et niveau.
  final String? classSlug;
  final String? classTier;
  final int? classLevel;
  final String? emblemUrl;
  final int uploaded;
  final int downloaded;
  final int uploadCredit;
  final int downloadCredit;
  final double? ratio;

  /// Ratio sous lequel le téléchargement est bloqué.
  final double? minRatio;
  final bool canDownload;
  final String? canDownloadReason;
  final int warnings;
  final bool freeleech;

  /// Téléchargements gratuits restants (effet `free_dl_units`).
  final int freeDownloads;
  final bool donor;
  final DateTime? createdAt;

  /// `swarm_keeper` → « Swarm Keeper ».
  String? get className => classSlug
      ?.split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  static C411Account parse(Map<String, dynamic> json, {String site = 'https://c411.org'}) {
    final u = (json['user'] as Map?)?.cast<String, dynamic>() ?? json;
    final klass = (u['gamificationClass'] as Map?)?.cast<String, dynamic>();
    final emblem = (klass?['emblem'] as Map?)?.cast<String, dynamic>();
    final src = emblem?['src'] as String?;
    return C411Account(
      username: u['username'] as String? ?? '',
      badge: (u['badge'] as Map?)?['label'] as String?,
      classSlug: (klass?['effectiveSlug'] ?? klass?['slug']) as String?,
      classTier: emblem?['tier'] as String?,
      classLevel: (emblem?['level'] as num?)?.toInt(),
      emblemUrl: src == null ? null : (src.startsWith('http') ? src : '$site$src'),
      uploaded: _int(u['uploaded']),
      downloaded: _int(u['downloaded']),
      uploadCredit: _int(u['uploadCredit']),
      downloadCredit: _int(u['downloadCredit']),
      ratio: (u['ratio'] as num?)?.toDouble(),
      minRatio: (u['minRatioForDownload'] as num?)?.toDouble(),
      canDownload: u['canDownload'] as bool? ?? true,
      canDownloadReason: u['canDownloadReason'] as String?,
      warnings: _int(u['warnings']),
      freeleech: u['isFreeleech'] == true || u['isPersonalFreeleech'] == true,
      freeDownloads: [
        for (final e in (u['activeEffects'] as List? ?? const []).whereType<Map>())
          if (e['type'] == 'free_dl_units') _int(e['remainingCount']),
      ].fold(0, (a, b) => a + b),
      donor: u['isDonor'] == true,
      createdAt: DateTime.tryParse(u['createdAt'] as String? ?? ''),
    );
  }
}

/// `/api/ic/level` : niveau et série de jours.
class C411Level {
  const C411Level({
    required this.level,
    required this.xp,
    required this.xpToNext,
    this.streakDays = 0,
    this.streakDaysMax = 0,
  });

  final int level;
  final int xp;

  /// XP qui manquent pour le niveau suivant.
  final int xpToNext;
  final int streakDays;
  final int streakDaysMax;

  static C411Level parse(Map<String, dynamic> j) => C411Level(
        level: _int(j['level']),
        xp: _int(j['xp']),
        xpToNext: _int(j['xpToNext']),
        streakDays: _int(j['streakDays']),
        streakDaysMax: _int(j['streakDaysMax']),
      );
}

/// `/api/tokens/balance` : le portefeuille de Zen.
class ZenBalance {
  const ZenBalance({
    required this.balance,
    this.earned = 0,
    this.spent = 0,
    this.lastDaily,
  });

  final int balance;
  final int earned;
  final int spent;

  /// Dernier versement quotidien.
  final int? lastDaily;

  static ZenBalance parse(Map<String, dynamic> j) => ZenBalance(
        balance: _int(j['balance']),
        earned: _int(j['totalEarned']),
        spent: _int(j['totalSpent']),
        lastDaily: (j['lastDailyRq'] as num?)?.toInt(),
      );
}

/// Le calcul d'une journée : versée (`daily-stats`) ou en cours (`forecast`).
class ZenDay {
  const ZenDay({
    this.date,
    required this.torrents,
    required this.shareBp,
    required this.weightBp,
    required this.contribution,
    required this.bonusBp,
    required this.paid,
  });

  final DateTime? date;

  /// T : torrents comptés.
  final int torrents;

  /// Σ P et Σ P × S, en points de base.
  final int shareBp;
  final int weightBp;

  /// I : indicateur de contribution.
  final double contribution;

  /// B : bonus de pondération, en points de base.
  final int bonusBp;

  /// Zen versés (ou acquis jusqu'ici, pour la journée en cours).
  final int paid;

  /// P : part de la journée partagée, de 0 à 1.
  double get share => torrents == 0 ? 0 : shareBp / 10000 / torrents;

  /// S : coefficient de poids moyen.
  double get weight => shareBp == 0 ? 0 : weightBp / shareBp;

  double get bonus => bonusBp / 10000;

  /// Zen avant bonus : T × P × S × I ÷ 7.
  double get beforeBonus => weightBp / 10000 * contribution / 7;

  /// Le portefeuille de ce versement, pour estimer un ajout.
  ZenBase get base => ZenBase(count: torrents, weight: weightBp / 10000, note: contribution);

  static ZenDay parse(Map<String, dynamic> j) => ZenDay(
        date: DateTime.tryParse(j['date'] as String? ?? ''),
        torrents: _int(j['releasesConcerned']),
        shareBp: _int(j['releasesShareBp']),
        weightBp: _int(j['releasesWeightBp']),
        contribution: _num(j['vmtr']),
        bonusBp: _int(j['ponderationBonusBp']),
        paid: _int(j['rq']),
      );
}

/// Indicateur de contribution maximal d'une classe (2,00 selon le site).
const maxContribution = 2.0;

/// `/api/tokens/daily-stats` : les versements des derniers jours.
class ZenHistory {
  const ZenHistory({required this.days, this.entries = const [], this.bonusCapBp = 0});

  /// Fenêtre demandée.
  final int days;

  /// Les plus récentes d'abord.
  final List<ZenDay> entries;

  /// Plafond du bonus de la classe, en points de base.
  final int bonusCapBp;

  ZenDay? get latest => entries.firstOrNull;

  /// Versement moyen par jour, sur les jours versés (comme le site).
  double get perDay => entries.isEmpty
      ? 0
      : entries.fold(0, (n, e) => n + e.paid) / entries.length;

  static ZenHistory parse(Map<String, dynamic> j) {
    final entries = [
      for (final e in (j['entries'] as List? ?? const []).whereType<Map>())
        ZenDay.parse(e.cast<String, dynamic>()),
    ]..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
    return ZenHistory(
      days: _int(j['days']),
      entries: entries,
      bonusCapBp: _int(j['ponderationCapBp']),
    );
  }
}

/// `/api/tokens/forecast` : la journée en cours.
class ZenForecast {
  const ZenForecast({
    required this.today,
    this.projected,
    this.bonusCapBp = 0,
    this.computedAt,
  });

  /// Acquis jusqu'ici (`rq`) et le calcul correspondant.
  final ZenDay today;

  /// Estimation ce soir, si les torrents restent en partage jusqu'à minuit.
  final int? projected;
  final int bonusCapBp;
  final DateTime? computedAt;

  /// null : prévision désactivée par le site.
  static ZenForecast? parse(Map<String, dynamic> j) {
    final f = (j['forecast'] as Map?)?.cast<String, dynamic>();
    if (j['enabled'] == false || f == null) return null;
    final at = (f['computedAt'] as num?)?.toInt();
    return ZenForecast(
      today: ZenDay.parse(f),
      projected: ((f['projected'] as Map?)?['rq'] as num?)?.toInt(),
      bonusCapBp: _int(f['ponderationCapBp']),
      computedAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

/// Une réanimation (`/api/profile/revivals`) : un torrent sans seeder
/// relancé, payé en Zen une fois partagé assez longtemps.
class C411Revival {
  const C411Revival({
    required this.id,
    required this.name,
    this.infoHash,
    this.size = 0,
    this.revivedAt,
    this.bounty = 0,
    this.keeperBonus = 0,
    this.status = '',
    this.ineligibleReason,
    this.seeded = Duration.zero,
    this.required = Duration.zero,
    this.deadline,
    this.qualifiedAt,
    this.paidAt,
  });

  final int id;
  final String name;

  /// En minuscules.
  final String? infoHash;
  final int size;
  final DateTime? revivedAt;

  /// Prime de la réanimation et bonus du gardien, en Zen.
  final int bounty;
  final int keeperBonus;

  /// `paid`, ou un autre état du site (en cours, non éligible…).
  final String status;
  final String? ineligibleReason;

  /// Temps de partage accumulé, et celui exigé.
  final Duration seeded;
  final Duration required;

  /// Date limite pour atteindre [required].
  final DateTime? deadline;
  final DateTime? qualifiedAt;
  final DateTime? paidAt;

  int get zen => bounty + keeperBonus;
  bool get paid => status == 'paid' || paidAt != null;
  bool get ineligible => status.contains('ineligible') || ineligibleReason != null;

  /// En cours : ni payée, ni qualifiée, ni écartée.
  bool get inProgress => !paid && qualifiedAt == null && !ineligible;

  double get progress => required == Duration.zero
      ? 0
      : (seeded.inSeconds / required.inSeconds).clamp(0, 1).toDouble();

  static C411Revival parse(Map<String, dynamic> j) {
    final t = (j['torrent'] as Map?)?.cast<String, dynamic>() ?? const {};
    DateTime? date(String k) => DateTime.tryParse(j[k] as String? ?? '');
    return C411Revival(
      id: _int(j['id']),
      name: t['name'] as String? ?? '',
      infoHash: (t['infoHash'] as String?)?.toLowerCase(),
      size: _int(t['sizeBytes']),
      revivedAt: date('revivedAt'),
      bounty: _int(j['bountyZen']),
      keeperBonus: _int(j['keeperBonusZen']),
      status: j['status'] as String? ?? '',
      ineligibleReason: j['ineligibleReason'] as String?,
      seeded: Duration(seconds: _int(j['seedProgressSecs'])),
      required: Duration(seconds: _int(j['requiredSeedSecs'])),
      deadline: date('qualifyDeadline'),
      qualifiedAt: date('qualifiedAt'),
      paidAt: date('paidAt'),
    );
  }

  static List<C411Revival> parseList(Map<String, dynamic> j) => [
        for (final r in (j['data'] as List? ?? const []).whereType<Map>())
          parse(r.cast<String, dynamic>()),
      ]..sort((a, b) => (b.revivedAt ?? DateTime(0)).compareTo(a.revivedAt ?? DateTime(0)));
}

/// Une ligne du classement (`/api/ic/leaderboard`).
class C411Rank {
  const C411Rank({
    required this.rank,
    required this.username,
    this.avatarUrl,
    this.className,
    this.grade,
    this.xp = 0,
    this.level = 0,
  });

  final int rank;
  final String username;
  final String? avatarUrl;

  /// Classe et grade tels que le site les affiche (« Tanker », « Bronze IV »).
  final String? className;
  final String? grade;
  final int xp;
  final int level;
}

/// Le classement : le haut du tableau, et sa propre place.
class C411Leaderboard {
  const C411Leaderboard({
    this.top = const [],
    this.rank,
    this.total,
    this.xp,
    this.dailyXp,
  });

  final List<C411Rank> top;
  final int? rank;
  final int? total;
  final int? xp;

  /// XP gagnés par jour en moyenne.
  final int? dailyXp;

  static C411Leaderboard parse(Map<String, dynamic> j, {String site = 'https://c411.org'}) {
    final self = (j['self'] as Map?)?.cast<String, dynamic>() ?? const {};
    return C411Leaderboard(
      top: [
        for (final e in (j['entries'] as List? ?? const []).whereType<Map>())
          C411Rank(
            rank: _int(e['rank']),
            username: e['username'] as String? ?? '',
            avatarUrl: switch (e['avatarUrl']) {
              final String u when u.startsWith('http') => u,
              final String u => '$site$u',
              _ => null,
            },
            className: e['className'] as String?,
            grade: e['gradeLabel'] as String?,
            xp: _int(e['xp']),
            level: _int(e['level']),
          ),
      ]..sort((a, b) => a.rank.compareTo(b.rank)),
      rank: (self['rank'] as num?)?.toInt(),
      total: (self['total'] as num?)?.toInt(),
      xp: (self['xp'] as num?)?.toInt(),
      dailyXp: (self['dailyXpAverage'] as num?)?.toInt(),
    );
  }
}

/// Tout ce que la page C411 montre du compte ; chaque partie peut manquer
/// (endpoint en échec ou absent).
class C411Overview {
  const C411Overview({
    this.account,
    this.level,
    this.balance,
    this.history,
    this.forecast,
    this.revivals,
    this.leaderboard,
  });
  final C411Account? account;
  final C411Level? level;
  final ZenBalance? balance;
  final ZenHistory? history;
  final ZenForecast? forecast;
  final List<C411Revival>? revivals;
  final C411Leaderboard? leaderboard;

  bool get isEmpty =>
      account == null &&
      level == null &&
      balance == null &&
      history == null &&
      forecast == null &&
      revivals == null &&
      leaderboard == null;
}
