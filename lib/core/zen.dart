import 'dart:math' as math;

// Ce que rapportent les torrents en Zen, pour la classe Swarm Keeper de C411
// (« payée sur le seed »), d'après les règles publiées sur le site :
//
//   Zen par jour = Σ S × note × (1 + bonus) ÷ 7, arrondi au Zen, chaque
//   torrent au prorata du temps partagé (30 minutes au moins)
//   note = catégorie (1,00) + durée de seed + taille × seeders, 2,00 au plus
//   S (coefficient de poids) = (0,25 + taille) ÷ 4,25 jusqu'à 4 Go, puis
//   monte lentement : 1,24 à 25 Go, 1,38 à 60 Go — (taille ÷ 4)^0,118,
//   ajusté sur ces deux valeurs, les redonne.
//
// Le site l'écrit Σ S × I × (1 + bonus) ÷ 7, où I, l'indicateur de
// contribution, est la moyenne des notes pondérée par le poids (« un gros
// torrent y compte plus qu'un petit ») : c'est la même somme. Chaque torrent
// rapporte donc selon sa propre note, sans rien changer aux autres.
//
// Tailles en milliards d'octets (1 Go = 10⁹ o, soit 0,93 Go affiché en base
// 1024). Toutes les règles sont ici : une autre classe, d'autres tables.

const _gb = 1e9;

/// Meilleure note possible dans la classe.
const maxNote = 2.0;

/// Facteur d'échelle du versement.
const zenScale = 7.0;

/// Coefficient de poids d'un torrent de [bytes] octets : 1 pour 4 Go.
double weightOf(int bytes) {
  final gb = bytes / _gb;
  if (gb <= 0) return 0;
  return gb <= 4 ? (0.25 + gb) / 4.25 : math.pow(gb / 4, 0.118).toDouble();
}

/// Paliers de durée de seed : jours cumulés → points de note.
const seedDurationSteps = [(7, 0.10), (30, 0.25), (90, 0.35), (180, 0.50)];

/// Points de note pour [days] jours de seed cumulés.
double durationBonus(double days) {
  var bonus = 0.0;
  for (final (from, points) in seedDurationSteps) {
    if (days >= from) bonus = points;
  }
  return bonus;
}

/// Prochain palier de durée : jours qui manquent et points gagnés ; null
/// au maximum.
({double inDays, double gain})? nextDurationStep(double days) {
  final current = durationBonus(days);
  for (final (from, points) in seedDurationSteps) {
    if (days < from) return (inDays: from - days, gain: points - current);
  }
  return null;
}

/// Taille × seeders actifs → points de note (tableau du site). Lignes :
/// moins de 1 Go, 1–5, 5–10, 10–50, 50–100, plus de 100 Go ; colonnes :
/// 1–10, 11–24, 25–50, 51–99, 100–199, 200 et plus seeders.
const _sizeSeeders = [
  [0.20, 0.20, 0.00, 0.00, 0.00, 0.00],
  [0.35, 0.20, 0.35, 0.00, 0.00, 0.00],
  [0.35, 0.35, 0.35, 0.00, 0.00, 0.00],
  [0.50, 0.35, 0.35, 0.00, 0.00, 0.00],
  [0.50, 0.50, 0.50, 0.00, 0.00, 0.00],
  [0.50, 0.50, 0.50, 0.35, 0.35, 0.00],
];

/// Points de note d'un torrent de [bytes] octets partagé par [seeders]
/// seeders actifs (soi compris). Aucun seeder : rien.
double sizeSeedersBonus(int bytes, int seeders) {
  if (seeders < 1) return 0;
  final gb = bytes / _gb;
  final row = gb < 1
      ? 0
      : gb < 5
          ? 1
          : gb < 10
              ? 2
              : gb < 50
                  ? 3
                  : gb < 100
                      ? 4
                      : 5;
  final col = seeders <= 10
      ? 0
      : seeders <= 24
          ? 1
          : seeders <= 50
              ? 2
              : seeders <= 99
                  ? 3
                  : seeders <= 199
                      ? 4
                      : 5;
  return _sizeSeeders[row][col];
}

/// Note d'un torrent (catégorie 1,00 pour toutes celles de C411).
double noteOf({required int bytes, required int seeders, double seedDays = 0}) =>
    math.min(maxNote, 1.0 + durationBonus(seedDays) + sizeSeedersBonus(bytes, seeders));

/// Ce que rapporte un torrent, et pourquoi.
class ZenEstimate {
  const ZenEstimate({
    required this.bytes,
    required this.seeders,
    required this.seedDays,
    required this.note,
    required this.weight,
    required this.perDay,
  });

  final int bytes;

  /// Seeders actifs comptés (soi compris).
  final int seeders;
  final double seedDays;
  final double note;
  final double weight;

  /// Zen par jour, partagé toute la journée, bonus compris.
  final double perDay;

  /// Zen par jour et par Go occupé.
  double get perGb => bytes <= 0 ? 0 : perDay / (bytes / _gb);

  /// Note réduite à la base : trop de seeders pour sa taille.
  bool get crowded => sizeSeedersBonus(bytes, seeders) == 0 && seeders > 0;

  /// Ce que rapportera le prochain palier de durée.
  ({double inDays, double gain})? get nextStep => nextDurationStep(seedDays);
}

/// Estimation pour un torrent. [joining] : on n'en est pas encore seedeur,
/// on devient l'un des seeders (10 seeders + soi = 11 : autre colonne).
/// [note] : celle du site, si on la connaît.
ZenEstimate estimateZen({
  required int bytes,
  required int seeders,
  double seedDays = 0,
  double bonus = 0.25,
  bool joining = false,
  double? note,
}) {
  final count = joining ? seeders + 1 : math.max(seeders, 1);
  note ??= noteOf(bytes: bytes, seeders: count, seedDays: seedDays);
  final weight = weightOf(bytes);
  return ZenEstimate(
    bytes: bytes,
    seeders: count,
    seedDays: seedDays,
    note: note,
    weight: weight,
    perDay: weight * note * (1 + bonus) / zenScale,
  );
}

/// Zen versés en terminant le niveau d'XP [level] (le niveau en cours, qui
/// ne paie qu'une fois terminé) ; au-delà de 400, 27 par cycle.
int zenForLevel(int level) {
  if (level < 1) return 0;
  for (final (upTo, zen) in _levelZen) {
    if (level <= upTo) return zen;
  }
  return 27;
}

/// Échelle des niveaux : dernier niveau de la tranche → Zen par niveau.
const _levelZen = [
  (6, 1), (17, 2), (24, 3), (36, 4), (48, 5), (60, 6), (74, 7), (88, 8),
  (103, 9), (122, 10), (152, 12), (182, 14), (214, 16), (248, 18), (283, 20),
  (327, 22), (380, 25),
];

/// Bonus de la grille de la classe selon le nombre de torrents seedés dans
/// la journée (au moins 30 minutes chacun).
double gridBonus(int torrents) {
  // En points de base (1/10 000), pour des pourcentages exacts.
  final bp = torrents < 5
      ? 0
      : torrents < 15
          ? 2000
          : torrents < 50
              ? 2500
              : torrents < 100
                  ? 2000
                  : torrents < 150
                      ? 1750
                      // +1 % par tranche de 50 au-delà de 150, +5 % au plus,
                      // 25 % au plus.
                      : math.min(2500, 2000 + math.min(500, (torrents - 150) ~/ 50 * 100));
  return bp / 10000;
}

/// Arbre de progression : torrents seedés dont la note atteint un seuil.
/// Seul le plus haut niveau atteint compte.
const progressionSteps = [
  (100, 0.75, 0.01),
  (150, 1.0, 0.02),
  (200, 1.0, 0.03),
  (250, 1.0, 0.04),
  (300, 1.0, 0.05),
];

/// Bonus de l'arbre pour ces notes.
double treeBonus(Iterable<double> notes) {
  final atThreeQuarters = notes.where((n) => n >= maxNote * 0.75).length;
  final atMax = notes.where((n) => n >= maxNote).length;
  var bonus = 0.0;
  for (final (count, share, points) in progressionSteps) {
    final have = share < 1 ? atThreeQuarters : atMax;
    if (have >= count) bonus = points;
  }
  return bonus;
}

/// Marge de téléchargement, comme le site : octets qu'on peut encore
/// télécharger (hors freeleech) avant le blocage, soit upload ÷ [minRatio]
/// − download ; 0 si c'est déjà le cas. [uploaded] inclut le crédit de
/// téléchargement (le champ `uploaded` de `/api/auth/me` l'inclut déjà).
int downloadBudget({required int uploaded, required int downloaded, required double minRatio}) {
  if (minRatio <= 0) return 1 << 62;
  return math.max(0, (uploaded / minRatio - downloaded).floor());
}
