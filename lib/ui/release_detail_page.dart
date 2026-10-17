import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/c411.dart';
import '../core/format.dart';
import '../state/releases.dart';
import '../state/torrents.dart';
import 'widgets.dart';

class ReleaseDetailPage extends ConsumerWidget {
  const ReleaseDetailPage({super.key, required this.release});
  final Release release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = release;
    final theme = Theme.of(context);
    final inClient = ref.watch(
        torrentsProvider.select((s) => s.hashes.contains(r.infoHash)));

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

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: r.backdropUrl != null ? 220 : null,
          title: Text(r.title ?? r.name, overflow: TextOverflow.ellipsis),
          flexibleSpace: r.backdropUrl == null
              ? null
              : FlexibleSpaceBar(
                  background: CachedNetworkImage(
                    imageUrl: r.backdropUrl!,
                    fit: BoxFit.cover,
                    color: Colors.black38,
                    colorBlendMode: BlendMode.darken,
                  ),
                ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Poster(r.posterUrl, width: 100, height: 150),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [r.title ?? r.name, if (r.year != null) '(${r.year})']
                          .join(' '),
                      style: theme.textTheme.titleLarge,
                    ),
                    if (r.originalTitle != null && r.originalTitle != r.title)
                      Text(r.originalTitle!,
                          style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Wrap(spacing: 4, runSpacing: 4, children: [
                      if (r.rating != null)
                        Badge411('★ ${r.rating!.toStringAsFixed(1)}',
                            color: Colors.amber.shade700),
                      if (r.runtime != null) Badge411('${r.runtime} min'),
                      for (final g in r.genres) Badge411(g),
                      if (r.isFreeleech)
                        const Badge411('FREELEECH', color: Colors.green),
                      if (r.isExclusive)
                        const Badge411('EXCLU', color: Colors.orange),
                    ]),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: inClient
                          ? null
                          : () => sendToTransmission(context, ref, r),
                      icon: Icon(inClient ? Icons.check : Icons.download),
                      label: Text(inClient
                          ? 'Déjà dans Transmission'
                          : 'Envoyer à Transmission'),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            SelectableText(r.name, style: theme.textTheme.bodySmall),
            if (r.overview != null) ...[
              const SizedBox(height: 16),
              Text(r.overview!),
            ],
            if (r.directors.isNotEmpty || r.cast.isNotEmpty) ...[
              const SizedBox(height: 16),
              if (r.directors.isNotEmpty)
                Text('Réalisation : ${r.directors.join(', ')}'),
              if (r.cast.isNotEmpty) Text('Avec : ${r.cast.join(', ')}'),
            ],
            const SizedBox(height: 16),
            Text('Détails', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final (label, value) in tech)
              if (value != null && value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(
                        width: 160,
                        child: Text(label, style: theme.textTheme.bodySmall)),
                    Expanded(child: Text(value)),
                  ]),
                ),
          ]),
        ),
      ]),
    );
  }
}
