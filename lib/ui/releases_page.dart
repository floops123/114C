import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../core/format.dart';
import '../core/release_profile.dart';
import '../core/release_quality.dart';
import 'release_detail_page.dart';
import 'content_art.dart';
import 'on_disk.dart';
import 'send_button.dart';
import 'theme.dart';
import 'widgets.dart';

/// Grille des sorties : sur PC des tuiles lisibles (affiche + infos), hauteur
/// calculée d'après la largeur de colonne et la taille du texte ; sur
/// téléphone 3 colonnes de cartes ; entre les deux, des cartes de 170 px au
/// plus. [item] construit la case [i] (sortie ou indicateur de chargement).
Widget releaseGrid(BuildContext context, double maxWidth, int count,
    NullableIndexedWidgetBuilder item) {
  final width = MediaQuery.sizeOf(context).width;
  final SliverGridDelegate delegate;
  final EdgeInsets padding;
  if (width >= 720) {
    const spacing = 16.0;
    padding = const EdgeInsets.fromLTRB(16, 8, 16, 0);
    final usable = maxWidth - padding.horizontal;
    final columns = math.max(2, ((usable + spacing) / (220 + spacing)).floor());
    final tile = (usable - (columns - 1) * spacing) / columns;
    delegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: 18,
      crossAxisSpacing: spacing,
      mainAxisExtent: ReleaseTile.height(context, tile),
    );
  } else if (width < 600) {
    padding = const EdgeInsets.fromLTRB(12, 12, 12, 0);
    delegate = const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 10,
      childAspectRatio: 0.52,
    );
  } else {
    padding = const EdgeInsets.fromLTRB(12, 12, 12, 0);
    delegate = const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 170,
      mainAxisSpacing: 16,
      crossAxisSpacing: 12,
      childAspectRatio: 0.55,
    );
  }
  return SliverPadding(
    padding: padding,
    sliver: SliverGrid(
      gridDelegate: delegate,
      delegate: SliverChildBuilderDelegate(item, childCount: count),
    ),
  );
}

/// Case de grille d'une sortie : tuile sur PC, carte « affiche » sinon.
Widget releaseGridItem(BuildContext context, Release r) =>
    MediaQuery.sizeOf(context).width >= 720
        ? ReleaseTile(release: r)
        : ReleaseCard(release: r);

void _openDetail(BuildContext context, Release r) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ReleaseDetailPage(release: r)));

String _displayTitle(Release r) => r.title ?? r.name;

/// Carte « affiche » pour la vue grille.
class ReleaseCard extends ConsumerWidget {
  const ReleaseCard({super.key, required this.release});
  final Release release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = release;
    final c = context.colors;
    final playable = playableFor(ref, r);
    final onDisk = playable != null || downloadedFor(ref, r);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openDetail(context, r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Poster(r.posterUrl,
                    radius: 10,
                    fallback: ContentArt(ContentKind.of(r), radius: 10)),
                Positioned(
                  left: 6,
                  top: 6,
                  right: playable != null ? 42 : 6,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (onDisk && playable == null)
                        Tag('SUR LE DISQUE', solid: true, color: c.success),
                      if (r.resolution != null) Tag(r.resolution!, solid: true),
                      if (r.isFreeleech)
                        Tag('FL', solid: true, color: c.success),
                      if (r.isExclusive)
                        Tag('EXCLU', solid: true, color: c.info),
                    ],
                  ),
                ),
                if (playable != null)
                  Positioned(right: 6, top: 6, child: PlayBadge(item: playable)),
                Positioned(right: 6, bottom: 6, child: SendButton(release: r)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _displayTitle(r),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (r.year != null) '${r.year}',
              formatBytes(r.size),
              '▲ ${r.seeders}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: c.muted),
          ),
        ],
      ),
    );
  }
}

/// Tuile de la grille sur PC : affiche, puis panneau avec titre sur
/// deux lignes, année et catégorie, étiquettes techniques, et une ligne
/// taille / seeders avec le bouton d'envoi (qui ne masque plus l'affiche).
class ReleaseTile extends ConsumerWidget {
  const ReleaseTile({super.key, required this.release});
  final Release release;

  static const _line = 1.3;

  /// Hauteur pour une colonne de [width] : affiche 2:3 + panneau d'infos.
  static double height(BuildContext context, double width) {
    final s = MediaQuery.textScalerOf(context);
    final info = 12 + // marges
        s.scale(14) * 1.25 * 2 + // titre, 2 lignes
        4 +
        s.scale(12) * _line + // année · catégorie
        8 +
        math.max(18, s.scale(10.5) * 1.3 + 4) + // étiquettes
        8 +
        math.max(30, s.scale(12) * _line) + // taille, seeders, bouton
        10;
    return width * 1.5 + info;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = release;
    final c = context.colors;
    final playable = playableFor(ref, r);
    final onDisk = playable != null || downloadedFor(ref, r);
    final profile = profileOf(r);
    final hdr = hdrLabel(r);
    final small = TextStyle(fontSize: 12, height: _line, color: c.muted);

    final tile = Panel(
      radius: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(fit: StackFit.expand, children: [
            Poster(r.posterUrl,
                radius: 0, fallback: ContentArt(ContentKind.of(r), radius: 0)),
            Positioned(
              left: 8,
              top: 8,
              right: playable != null ? 44 : 8,
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                if (onDisk && playable == null)
                  Tag('SUR LE DISQUE', solid: true, color: c.success),
                if (r.resolution != null) Tag(r.resolution!, solid: true),
                if (r.isFreeleech) Tag('FL', solid: true, color: c.success),
                if (r.isExclusive) Tag('EXCLU', solid: true, color: c.info),
              ]),
            ),
            if (playable != null)
              Positioned(right: 8, top: 8, child: PlayBadge(item: playable)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_displayTitle(r),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, height: 1.25, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                [if (r.year != null) '${r.year}', r.subcategory]
                    .where((t) => t.isNotEmpty)
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small),
            const SizedBox(height: 8),
            // Une ligne d'étiquettes, coupée à droite si besoin.
            SizedBox(
              height: math.max(18, MediaQuery.textScalerOf(context).scale(10.5) * 1.3 + 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(spacing: 4, children: [
                  if (profile != null)
                    Tooltip(
                      message: profile.description,
                      child: Tag(profile.short, color: profileColor(c, profile)),
                    ),
                  if (isBonus(r.name)) Tag('BONUS', color: c.warning),
                  if (r.source != null)
                    Tooltip(
                        message: sourceDescription(r.source!),
                        child: Tag(r.source!)),
                  if (hdr != null)
                    Tooltip(
                        message: hdrDescription(r.hdrFormat!),
                        child: Tag(hdr, color: c.info)),
                  if (r.languages.isNotEmpty) LanguageTag(r.languages),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${formatBytes(r.size)}  '),
                    TextSpan(
                        text: '▲ ${r.seeders}',
                        style: TextStyle(color: c.success, fontWeight: FontWeight.w600)),
                    TextSpan(text: '  ▼ ${r.leechers}'),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small,
                ),
              ),
              SendButton(release: r),
            ]),
          ]),
        ),
      ]),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: () => _openDetail(context, r), child: tile),
    );
  }
}

/// Couleur d'un profil de qualité C411.
Color profileColor(AppColors c, C411Profile p) => switch (p) {
      C411Profile.hcPure => c.warning,
      C411Profile.hcOptimized => c.info,
      C411Profile.optimization => c.success,
      C411Profile.compatibility => c.muted,
    };

/// HDR d'une sortie (« DV · HDR10+ »), ou null en SDR / inconnu.
/// Langues résumées comme sur C411 (« MULTI.VF2 »), détail au survol.
class LanguageTag extends StatelessWidget {
  const LanguageTag(this.languages, {super.key});
  final List<String> languages;

  @override
  Widget build(BuildContext context) {
    final label = languageLabel(languages);
    return Tooltip(
      message: '${languageDescription(label)}\n${languages.join(', ')}',
      child: Tag(label),
    );
  }
}

String? hdrLabel(Release r) {
  final f = r.hdrFormat?.trim();
  if (f == null || f.isEmpty || f.toUpperCase() == 'SDR') return null;
  return f.split('.').join(' · ');
}

/// Ligne compacte pour la vue liste.
class ReleaseRow extends ConsumerWidget {
  const ReleaseRow({super.key, required this.release});
  final Release release;

  static const _posterWidth = 60.0, _posterHeight = 90.0;

  /// Hauteur de ligne : fixe pour la fluidité du défilement, mais calculée
  /// d'après la taille de police du système (texte agrandi sur Android).
  /// Carte : marges 5 + 5, intérieur 12 + 12 ; textes : titre 14, nom 12,
  /// étiquettes 10,5 (+ 4), infos 12 (icônes 14) ; interligne 1,25 (1,3 pour
  /// les étiquettes) ; espacements 2 + 7 + 7.
  static double extent(BuildContext context) {
    final s = MediaQuery.textScalerOf(context).scale(100) / 100;
    final text = (14 + 12) * _line * s +
        (10.5 * 1.3 * s + 4) +
        math.max(14, 12 * _line * s) +
        16 +
        // Marge : hauteur réelle des étiquettes et icônes au texte agrandi.
        4 * s;
    return 10 + 24 + math.max(_posterHeight, text);
  }

  static const _line = 1.25;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = release;
    final c = context.colors;
    final playable = playableFor(ref, r);
    final onDisk = playable != null || downloadedFor(ref, r);
    final small = TextStyle(fontSize: 12, height: _line, color: c.muted);
    Widget stat(IconData icon, String text, {Color? color}) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color ?? c.muted),
          const SizedBox(width: 3),
          Text(text,
              style: small.copyWith(
                  color: color ?? c.muted,
                  fontWeight: color == null ? null : FontWeight.w600)),
        ]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: onDisk ? c.success.withValues(alpha: 0.55) : c.border),
        ),
        child: InkWell(
          onTap: () => _openDetail(context, r),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: Row(children: [
              Poster(r.posterUrl,
                  width: _posterWidth,
                  height: _posterHeight,
                  radius: 8,
                  fallback: ContentArt(ContentKind.of(r), radius: 8)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      [_displayTitle(r), if (r.year != null) '(${r.year})'].join(' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, height: _line, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(r.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                    const SizedBox(height: 7),
                    // Une seule ligne d'étiquettes, coupée à droite si besoin
                    // (un retour à la ligne ferait déborder la ligne de liste).
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        spacing: 5,
                        children: [
                          if (onDisk)
                            Tag(playable?.label ?? 'SUR LE DISQUE',
                                solid: true, color: c.success),
                          if (profileOf(r) case final p?)
                            Tooltip(
                              message: p.description,
                              child: Tag(p.short,
                                  solid: true, color: profileColor(c, p)),
                            ),
                          if (isBonus(r.name)) Tag('BONUS', color: c.warning),
                          Tag(r.subcategory, color: c.accent),
                          if (r.resolution != null) Tag(r.resolution!),
                          if (r.source != null) Tag(r.source!),
                          if (hdrLabel(r) case final hdr?) Tag(hdr, color: c.info),
                          if (r.languages.isNotEmpty) LanguageTag(r.languages),
                          if (r.audioCodec != null)
                            Tag([r.audioCodec!, ?r.audioChannels].join(' ')),
                          if (r.isFreeleech) Tag('FREELEECH', color: c.success),
                          if (r.isExclusive) Tag('EXCLU', color: c.info),
                        ],
                      ),
                    ),
                    const SizedBox(height: 7),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(spacing: 14, children: [
                        stat(Icons.storage_rounded, formatBytes(r.size)),
                        stat(Icons.arrow_upward_rounded, '${r.seeders}',
                            color: r.seeders > 0 ? c.success : c.danger),
                        stat(Icons.arrow_downward_rounded, '${r.leechers}',
                            color: r.leechers > 0 ? c.download : null),
                        stat(Icons.schedule_rounded, formatAgo(r.createdAt)),
                      ]),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (playable != null) ...[
                PlayBadge(item: playable),
                const SizedBox(width: 6),
              ],
              SendButton(release: r),
            ]),
          ),
        ),
      ),
    );
  }
}
