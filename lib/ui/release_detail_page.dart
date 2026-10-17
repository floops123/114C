import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../core/format.dart';
import 'content_art.dart';
import 'on_disk.dart';
import 'send_button.dart';
import 'theme.dart';
import 'widgets.dart';

class ReleaseDetailPage extends ConsumerWidget {
  const ReleaseDetailPage({super.key, required this.release});
  final Release release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = release;
    final playable = playableFor(ref, r);
    final downloaded = downloadedFor(ref, r);
    final c = context.colors;
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;

    final meta = [
      if (r.year != null) '${r.year}',
      if (r.runtime != null) '${r.runtime} min',
      r.subcategory,
    ].join('  ·  ');

    final tech = <(String, String?)>[
      ('Résolution', r.resolution),
      ('Source', r.source),
      ('Vidéo', [r.videoCodec, r.hdrFormat].nonNulls.join(' · ')),
      ('Audio', [r.audioCodec, r.audioChannels].nonNulls.join(' ')),
      ('Langues', r.languages.join(', ')),
      ('Taille', formatBytes(r.size)),
      ('Seeders / Leechers', '${r.seeders} / ${r.leechers}'),
      ('Complétés', '${r.completions}'),
      ('Uploader', r.uploader),
      ('Publié', formatDate(r.createdAt)),
    ];

    final header = Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Poster(r.posterUrl,
            width: wide ? 150 : 110,
            height: wide ? 225 : 165,
            radius: 12,
            fallback: ContentArt(ContentKind.of(r), radius: 12)),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.title ?? r.name,
              style: TextStyle(
                  fontSize: wide ? 30 : 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.1)),
          if (r.originalTitle != null && r.originalTitle != r.title) ...[
            const SizedBox(height: 4),
            Text(r.originalTitle!, style: TextStyle(color: c.muted)),
          ],
          const SizedBox(height: 8),
          Row(children: [
            if (r.rating != null) ...[
              Icon(Icons.star_rounded, size: 18, color: c.warning),
              const SizedBox(width: 2),
              Text(r.rating!.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(meta,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final g in r.genres) Tag(g),
            if (r.isFreeleech) Tag('FREELEECH', color: c.success),
            if (r.isExclusive) Tag('EXCLU', color: c.info),
          ]),
          const SizedBox(height: 14),
          if (playable != null || downloaded) ...[
            Row(children: [
              Icon(Icons.inventory_2_outlined, size: 16, color: c.success),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                    playable != null
                        ? '${playable.description}'
                            '${downloaded ? ' et téléchargé dans Transmission' : ''}'
                        : 'Sur le disque : téléchargé dans Transmission',
                    style: TextStyle(
                        color: c.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 10),
          ],
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (playable != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: c.success),
                onPressed: () => playable.play(context),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(playable.isSeries ? 'Épisodes' : 'Lire'),
              ),
            SendButton(release: r, large: true),
          ]),
        ]),
      ),
    ]);

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: r.backdropUrl != null ? (wide ? 340 : 240) : null,
          backgroundColor: c.bg,
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: IconButton.filled(
              style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.4),
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          flexibleSpace: r.backdropUrl == null
              ? null
              : FlexibleSpaceBar(
                  background: Stack(fit: StackFit.expand, children: [
                    CachedNetworkImage(
                        imageUrl: r.backdropUrl!, fit: BoxFit.cover),
                    // Fondu vers la couleur de fond pour enchaîner sur le contenu.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0, 0.5, 1],
                          colors: [
                            c.bg.withValues(alpha: 0.1),
                            c.bg.withValues(alpha: 0.4),
                            c.bg,
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
        ),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 20),
                    SelectableText(r.name,
                        style: TextStyle(
                            fontSize: 12,
                            color: c.muted,
                            fontFamily: 'monospace')),
                    if (r.overview != null) ...[
                      const SizedBox(height: 16),
                      Text(r.overview!,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.55)),
                    ],
                    const SizedBox(height: 20),
                    Section(title: 'Fiche technique', children: [
                      for (final (label, value) in tech)
                        if (value != null && value.isNotEmpty)
                          InfoRow(label, value),
                    ]),
                    if (r.directors.isNotEmpty || r.cast.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Section(title: 'Équipe', children: [
                        if (r.directors.isNotEmpty)
                          InfoRow('Réalisation', r.directors.join(', ')),
                        if (r.cast.isNotEmpty)
                          InfoRow('Distribution', r.cast.join(', ')),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
