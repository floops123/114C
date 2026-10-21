import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/c411_profile.dart';
import '../core/format.dart';
import 'charts.dart';
import 'theme.dart';
import 'widgets.dart';

// Blocs de la page C411 tirés du site (cookie de session) : profil, niveau,
// et le Zen versé chaque nuit pour le partage, avec le détail du calcul.

const _months = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

/// « 21 oct. »
String shortDay(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// Nombre à la française : « 1 091 », « 0,19 », « 23,3 ».
String frNumber(num v, [int digits = 0]) {
  final text = v.toStringAsFixed(digits);
  final dot = text.indexOf('.');
  final whole = dot < 0 ? text : text.substring(0, dot);
  final grouped = whole.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]} ',
  );
  return dot < 0 ? grouped : '$grouped,${text.substring(dot + 1)}';
}

/// Valeur en Zen, sans décimale inutile : « 23,3 », « 29 ».
String _zen(double v) => frNumber(v, v == v.roundToDouble() ? 0 : 1);

/// Titre de bloc : icône, texte en capitales, aide facultative.
class _Caption extends StatelessWidget {
  const _Caption(this.icon, this.text, {this.help});
  final IconData icon;
  final String text;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Icon(icon, size: 16, color: c.muted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: .7,
              fontWeight: FontWeight.w700,
              color: c.muted,
            ),
          ),
        ),
        if (help != null) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: help!,
            child: Icon(Icons.help_outline_rounded, size: 14, color: c.muted),
          ),
        ],
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Panel(
    radius: 16,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

/// Profil : emblème de classe, rang, niveau et série de jours, et ce qui
/// demande attention (avertissements, téléchargement bloqué).
class C411ProfileCard extends StatelessWidget {
  const C411ProfileCard({super.key, this.account, this.level});
  final C411Account? account;
  final C411Level? level;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = account, l = level;
    final small = TextStyle(fontSize: 12.5, color: c.muted);
    return _Block(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (a?.emblemUrl case final url?)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: CachedNetworkImage(
                  imageUrl: url,
                  width: 64,
                  height: 64,
                  memCacheWidth: 128,
                  errorWidget: (_, _, _) =>
                      const SizedBox(width: 64, height: 64),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        a?.username ?? 'Mon compte',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (a?.badge case final b?) Tag(b.toUpperCase()),
                      if (a?.donor == true) Tag('DONATEUR', color: c.warning),
                      if (a?.freeleech == true)
                        Tag('FREELEECH', color: c.success),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (a?.className case final n?)
                        [
                          n,
                          if (a?.classTier case final t?)
                            '${t[0].toUpperCase()}${t.substring(1)} ${a?.classLevel ?? ''}'
                                .trim(),
                        ].join(' · '),
                      if (a?.createdAt case final d?)
                        'membre depuis ${_months[d.month - 1]} ${d.year}',
                    ].join('  ·  '),
                    style: small,
                  ),
                  if (l != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        _Pair(
                          Icons.military_tech_rounded,
                          c.accent,
                          'Niveau ${l.level}',
                          '${frNumber(l.xpToNext)} XP avant le ${l.level + 1}',
                        ),
                        _Pair(
                          Icons.local_fire_department_rounded,
                          c.warning,
                          '${l.streakDays} jour${l.streakDays > 1 ? 's' : ''} d’affilée',
                          'record : ${l.streakDaysMax}',
                        ),
                        if (a != null && a.freeDownloads > 0)
                          _Pair(
                            Icons.redeem_rounded,
                            c.success,
                            '${a.freeDownloads} téléchargement${a.freeDownloads > 1 ? 's' : ''} gratuit${a.freeDownloads > 1 ? 's' : ''}',
                            'à utiliser sur le site',
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (a != null && a.warnings > 0) ...[
          const SizedBox(height: 12),
          _Alert(
            c.danger,
            Icons.report_rounded,
            '${a.warnings} avertissement${a.warnings > 1 ? 's' : ''} sur ton compte',
          ),
        ],
        if (a != null && !a.canDownload) ...[
          const SizedBox(height: 12),
          _Alert(
            c.danger,
            Icons.block_rounded,
            'Téléchargement bloqué${a.canDownloadReason == null ? '' : ' : ${a.canDownloadReason}'}'
            '${a.minRatio == null ? '' : ' (ratio minimum ${formatRatio(a.minRatio!)})'}',
          ),
        ] else if (a?.ratio case final r?
            when a?.minRatio != null && r < a!.minRatio! + 0.1) ...[
          const SizedBox(height: 12),
          _Alert(
            c.warning,
            Icons.warning_amber_rounded,
            'Ratio ${formatRatio(r)} : proche du minimum (${formatRatio(a.minRatio!)}) '
            'sous lequel le téléchargement est bloqué',
          ),
        ],
      ],
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair(this.icon, this.color, this.title, this.subtitle);
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(subtitle, style: TextStyle(fontSize: 11.5, color: c.muted)),
          ],
        ),
      ],
    );
  }
}

class _Alert extends StatelessWidget {
  const _Alert(this.color, this.icon, this.text);
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Color.lerp(color, c.surface, 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Color.lerp(color, c.surface, 0.5)!),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Le Zen : solde, journée en cours, dernier versement, contribution et
/// bonus, moyennes, versements jour par jour et détail du calcul.
class ZenSection extends StatelessWidget {
  const ZenSection({super.key, this.balance, this.forecast, this.history});
  final ZenBalance? balance;
  final ZenForecast? forecast;
  final ZenHistory? history;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = forecast, h = history, b = balance;
    final latest = h?.latest;
    // La journée en cours, à défaut le dernier versement.
    final day = f?.today ?? latest;
    final cap = (f?.bonusCapBp ?? h?.bonusCapBp ?? 0) / 10000;

    final head = _Block(
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 14,
          children: [
            if (b != null)
              _Big(
                caption: const _Caption(
                  Icons.account_balance_wallet_rounded,
                  'Solde de Zen',
                ),
                value: frNumber(b.balance),
                detail:
                    '${frNumber(b.earned)} gagnés · ${frNumber(b.spent)} dépensés',
              ),
            if (f != null)
              _Big(
                caption: const _Caption(
                  Icons.today_rounded,
                  'Acquis aujourd’hui',
                  help: 'Versé chaque nuit après minuit.',
                ),
                value: frNumber(f.today.paid),
                detail: f.projected == null
                    ? null
                    : 'Estimation : ≈ ${f.projected} ce soir, si tes torrents '
                          'restent en partage jusqu’à minuit',
              ),
            if (latest != null)
              _Big(
                caption: const _Caption(
                  Icons.nightlight_round,
                  'Versé cette nuit',
                ),
                value: frNumber(latest.paid),
                detail: latest.date == null
                    ? null
                    : 'le ${shortDay(latest.date!)}',
              ),
          ],
        ),
        if (day != null) ...[
          const SizedBox(height: 14),
          Text(
            '${formatPercent(day.share)} de la journée partagée · '
            'coefficient de poids ${frNumber(day.weight, 2)}',
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
          const SizedBox(height: 6),
          Meter(value: day.share, color: c.accent),
        ],
      ],
    );

    final gauges = day == null
        ? null
        : _Pairwise(
            children: [
              _Gauge(
                caption: const _Caption(
                  Icons.insights_rounded,
                  'Indicateur de contribution',
                  help:
                      'La note moyenne de tes torrents, 2,00 au plus dans ta '
                      'classe ; chacun est noté selon sa catégorie et les critères '
                      'de la classe.',
                ),
                value: day.contribution / maxContribution,
                big: '${frNumber(day.contribution / maxContribution * 100)} %',
                detail:
                    'du maximum de ta classe (${frNumber(day.contribution, 2)} sur 2,00)',
                color: c.accent,
              ),
              _Gauge(
                caption: const _Caption(
                  Icons.trending_up_rounded,
                  'Bonus',
                  help:
                      'Bonus de pondération : le palier de ta classe, plafonné au '
                      'maximum de sa grille, plus l’arbre de progression.',
                ),
                value: cap == 0 ? 0 : day.bonus / cap,
                big: '+${frNumber(day.bonus * 100)} %',
                detail: cap == 0
                    ? ''
                    : 'sur ${frNumber(cap * 100)} % au maximum',
                color: c.accent,
              ),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        if (gauges != null) ...[const SizedBox(height: 12), gauges],
        if (h != null && h.entries.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Period(history: h),
        ],
        if (f != null) ...[
          const SizedBox(height: 12),
          _Formula(title: 'Le calcul en cours', day: f.today),
        ],
        if (h != null && h.entries.isNotEmpty) ...[
          const SizedBox(height: 12),
          _History(history: h),
        ],
      ],
    );
  }
}

/// Deux blocs côte à côte s'il y a la place, l'un sous l'autre sinon.
class _Pairwise extends StatelessWidget {
  const _Pairwise({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => box.maxWidth >= 600
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, w) in children.indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: w),
                ],
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, w) in children.indexed) ...[
                if (i > 0) const SizedBox(height: 12),
                w,
              ],
            ],
          ),
  );
}

class _Big extends StatelessWidget {
  const _Big({required this.caption, required this.value, this.detail});
  final Widget caption;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          caption,
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: ' Zen',
                  style: TextStyle(
                    fontSize: 13,
                    color: c.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (detail != null)
            Text(detail!, style: TextStyle(fontSize: 12, color: c.muted)),
        ],
      ),
    );
  }
}

class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.caption,
    required this.value,
    required this.big,
    required this.detail,
    required this.color,
  });
  final Widget caption;
  final double value;
  final String big;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Block(
      children: [
        caption,
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox.square(
              dimension: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: value.clamp(0, 1),
                      strokeWidth: 6,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.18),
                    ),
                  ),
                  Text(
                    big,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                detail,
                style: TextStyle(fontSize: 12.5, color: c.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Moyennes sur la période et versements jour par jour.
class _Period extends StatelessWidget {
  const _Period({required this.history});
  final ZenHistory history;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final perDay = history.perDay;
    final rates = [
      ('Par minute', frNumber(perDay / 1440, 3)),
      ('Par heure', frNumber(perDay / 24, 3)),
      ('Par jour', frNumber(perDay)),
      ('Par mois', frNumber(perDay * 30)),
    ];
    // Une barre par jour de la fenêtre, à 0 les jours sans versement.
    final byDay = {
      for (final e in history.entries)
        if (e.date != null) DateUtils.dateOnly(e.date!): e.paid,
    };
    final last = history.entries.first.date ?? DateTime.now();
    final days = [
      for (var i = history.days - 1; i >= 0; i--)
        DateUtils.dateOnly(last).subtract(Duration(days: i)),
    ];
    final bars = [for (final d in days) (d, byDay[d] ?? 0)];

    return _Block(
      children: [
        _Caption(
          Icons.calendar_month_rounded,
          'Sur ${history.days} jours',
          help: 'Moyenne des jours versés.',
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, box) {
            final perRow = box.maxWidth >= 560 ? 4 : 2;
            final width = (box.maxWidth - (perRow - 1) * 10) / perRow;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (label, value) in rates)
                  Container(
                    width: width,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: .6,
                            color: c.muted,
                          ),
                        ),
                        Text(
                          '$value Zen',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Zen versés, jour par jour',
          style: TextStyle(fontSize: 12.5, color: c.muted),
        ),
        const SizedBox(height: 8),
        DailyBars(bars: bars, color: c.accent),
      ],
    );
  }
}

/// Barres verticales d'une seule série, une par jour : valeur au survol,
/// maximum et dates aux extrémités.
class DailyBars extends StatelessWidget {
  const DailyBars({
    super.key,
    required this.bars,
    required this.color,
    this.height = 120,
  });
  final List<(DateTime, int)> bars;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final max = bars.fold(0, (m, b) => b.$2 > m ? b.$2 : m);
    final axis = TextStyle(
      fontSize: 11,
      color: c.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$max', style: axis),
                    Text('0', style: axis),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DecoratedBox(
                  // Ligne de base discrète.
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.border)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (day, value) in bars)
                        Expanded(
                          child: Tooltip(
                            message: '${shortDay(day)} : $value Zen',
                            // Cible de survol sur toute la hauteur, plus grande
                            // que la barre.
                            child: Container(
                              color: Colors.transparent,
                              alignment: Alignment.bottomCenter,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 1,
                              ),
                              child: FractionallySizedBox(
                                heightFactor: max == 0 ? 0 : value / max,
                                widthFactor: 1,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (bars.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 34, top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(shortDay(bars.first.$1), style: axis),
                Text(shortDay(bars.last.$1), style: axis),
              ],
            ),
          ),
      ],
    );
  }
}

/// Le calcul d'une journée, comme sur le site.
class _Formula extends StatelessWidget {
  const _Formula({required this.title, required this.day});
  final String title;
  final ZenDay day;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mono = TextStyle(
      fontSize: 12.5,
      color: c.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final before = day.beforeBonus;
    return _Block(
      children: [
        _Caption(
          Icons.functions_rounded,
          title,
          help:
              'versement = arrondi( T × P × S × I ÷ 7 × (1 + B) )\n'
              'T torrents comptés · P part de la journée partagée · '
              'S coefficient de poids · I indicateur de contribution · '
              '7 facteur d’échelle · B bonus',
        ),
        const SizedBox(height: 10),
        Text(
          '${frNumber(day.torrents)} torrents × ${formatPercent(day.share)} de la journée '
          'partagée × coefficient de poids ${frNumber(day.weight, 2)} × indicateur '
          '${frNumber(day.contribution, 2)} ÷ 7',
          style: mono,
        ),
        Text(
          '= ${_zen(before)} Zen avant bonus',
          style: mono.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '${_zen(before)} + bonus de ${frNumber(day.bonus * 100)} %',
          style: mono,
        ),
        Text(
          '= ${day.paid} Zen ${day.date == null ? 'acquis' : 'versés'} après arrondi',
          style: mono.copyWith(fontWeight: FontWeight.w700, color: c.accent),
        ),
      ],
    );
  }
}

/// Le détail des derniers versements, jour par jour.
class _History extends StatelessWidget {
  const _History({required this.history});
  final ZenHistory history;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final head = TextStyle(
      fontSize: 11,
      color: c.muted,
      fontWeight: FontWeight.w700,
    );
    const cell = TextStyle(
      fontSize: 12.5,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    DataColumn col(String label, {bool numeric = true, String? help}) =>
        DataColumn(
          numeric: numeric,
          label: Tooltip(
            message: help ?? label,
            child: Text(label, style: head),
          ),
        );
    return Panel(
      radius: 16,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          title: const _Caption(Icons.table_rows_rounded, 'Détail par jour'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 34,
                  dataRowMaxHeight: 38,
                  columnSpacing: 22,
                  horizontalMargin: 12,
                  columns: [
                    col('Date', numeric: false),
                    col('Torrents', help: 'Torrents comptés (T)'),
                    col('Partage', help: 'Part de la journée partagée (P)'),
                    col('Coef. poids', help: 'Coefficient de poids moyen (S)'),
                    col('Contribution', help: 'Indicateur de contribution (I)'),
                    col(
                      'Avant bonus',
                      help: 'Zen avant bonus : T × P × S × I ÷ 7',
                    ),
                    col('Bonus', help: 'Bonus de pondération (B)'),
                    col('Versé', help: 'Zen versés après arrondi'),
                  ],
                  rows: [
                    for (final e in history.entries)
                      DataRow(
                        cells: [
                          DataCell(
                            Text(
                              e.date == null ? '—' : shortDay(e.date!),
                              style: cell,
                            ),
                          ),
                          DataCell(Text(frNumber(e.torrents), style: cell)),
                          DataCell(Text(formatPercent(e.share), style: cell)),
                          DataCell(Text(frNumber(e.weight, 2), style: cell)),
                          DataCell(
                            Text(frNumber(e.contribution, 2), style: cell),
                          ),
                          DataCell(Text(_zen(e.beforeBonus), style: cell)),
                          DataCell(
                            Text('+${frNumber(e.bonus * 100)} %', style: cell),
                          ),
                          DataCell(
                            Text(
                              '${e.paid}',
                              style: cell.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Réanimations : bilan, celles en cours (temps de partage, date limite,
/// présence dans Transmission) et les dernières terminées.
class RevivalsCard extends StatelessWidget {
  const RevivalsCard({super.key, required this.revivals, this.inTransmission});
  final List<C411Revival> revivals;

  /// Infohash des torrents de Transmission ; null : inconnu.
  final Set<String>? inTransmission;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final paid = revivals.where((r) => r.paid).toList();
    final zen = paid.fold(0, (n, r) => n + r.zen);
    final running = revivals.where((r) => r.inProgress).toList();
    final done = revivals.where((r) => !r.inProgress).take(5).toList();
    final small = TextStyle(fontSize: 12, color: c.muted);

    Widget row(C411Revival r) {
      final here = r.infoHash == null || inTransmission == null
          ? null
          : inTransmission!.contains(r.infoHash);
      String hours(Duration d) => (d.inMinutes / 60).toStringAsFixed(0);
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            if (r.paid)
              Tag('PAYÉE · ${r.zen} ZEN', color: c.success)
            else if (r.ineligible)
              Tag('NON ÉLIGIBLE', color: c.danger)
            else if (r.qualifiedAt != null)
              Tag('QUALIFIÉE', color: c.info)
            else
              Tag('EN COURS', color: c.accent),
          ]),
          const SizedBox(height: 3),
          Text(
            [
              formatBytes(r.size),
              if (r.revivedAt case final d?) 'réanimée le ${shortDay(d)}',
              if (r.inProgress && r.required > Duration.zero)
                '${hours(r.seeded)} h partagées sur ${hours(r.required)} h',
              if (r.inProgress && r.deadline != null) 'avant le ${shortDay(r.deadline!)}',
              ?r.ineligibleReason,
            ].join(' · '),
            style: small,
          ),
          if (r.inProgress) ...[
            const SizedBox(height: 6),
            Meter(value: r.progress, color: c.accent),
            if (here == false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _Alert(c.warning, Icons.warning_amber_rounded,
                    'Plus dans Transmission : sans partage, elle ne sera pas payée'),
              ),
          ],
        ]),
      );
    }

    return _Block(children: [
      const _Caption(Icons.healing_rounded, 'Réanimations',
          help: 'Un torrent sans seeder relancé : payé en Zen une fois partagé '
              'assez longtemps avant la date limite.'),
      const SizedBox(height: 8),
      Text.rich(TextSpan(children: [
        TextSpan(text: '$zen', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        TextSpan(
            text: ' Zen versés sur ${paid.length} réanimation${paid.length > 1 ? 's' : ''} '
                'payée${paid.length > 1 ? 's' : ''}',
            style: TextStyle(fontSize: 13, color: c.muted)),
      ])),
      if (running.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Aucune réanimation en cours.', style: small),
        )
      else ...[
        const SizedBox(height: 4),
        for (final r in running) row(r),
      ],
      if (done.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Dernières', style: small.copyWith(fontWeight: FontWeight.w700)),
        for (final r in done) row(r),
      ],
    ]);
  }
}

/// Classement : sa place, puis le haut du tableau.
class LeaderboardCard extends StatelessWidget {
  const LeaderboardCard({super.key, required this.board, this.me});
  final C411Leaderboard board;

  /// Son pseudo, pour se repérer dans le haut du tableau.
  final String? me;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(fontSize: 12, color: c.muted);
    return _Block(children: [
      const _Caption(Icons.leaderboard_rounded, 'Classement'),
      const SizedBox(height: 8),
      if (board.rank != null)
        Text.rich(TextSpan(children: [
          TextSpan(
              text: '${frNumber(board.rank!)}ᵉ',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          TextSpan(
              text: [
                if (board.total != null) ' sur ${frNumber(board.total!)}',
                if (board.xp != null) ' · ${frNumber(board.xp!)} XP',
                if (board.dailyXp != null) ' · ${board.dailyXp} XP par jour en moyenne',
              ].join(),
              style: TextStyle(fontSize: 13, color: c.muted)),
        ])),
      if (board.top.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final e in board.top)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: e.username == me ? Color.lerp(c.accent, c.surface, 0.85) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              SizedBox(
                width: 28,
                child: Text('${e.rank}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: e.rank <= 3 ? c.warning : c.muted,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              _Avatar(url: e.avatarUrl, name: e.username),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text([?e.className, ?e.grade].join(' · '), style: small),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Niv. ${e.level}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text('${frNumber(e.xp)} XP', style: small),
              ]),
            ]),
          ),
      ],
    ]);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});
  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fallback = CircleAvatar(
      radius: 15,
      backgroundColor: c.surfaceAlt,
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.muted)),
    );
    if (url == null) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: 30,
        height: 30,
        fit: BoxFit.cover,
        memCacheWidth: 60,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
