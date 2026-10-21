import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/jellyfin.dart';
import '../api/tmdb.dart';
import '../api/transmission.dart';
import '../api/tracker.dart';
import '../core/format.dart';
import '../state/media_library.dart';
import '../state/wishlist.dart';
import 'disk_page.dart';
import 'on_disk.dart';
import 'series_page.dart';
import 'theme.dart';
import 'widgets.dart';
import 'wishlist_page.dart';

/// Fiche d'un titre : image de fond, infos, dates françaises, bande-annonce,
/// équipe, distribution, recommandations ; ajout à la liste et recherche sur
/// les trackers.
class TitleDetailPage extends ConsumerWidget {
  const TitleDetailPage({super.key, required this.title});
  final TmdbTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = title;
    final details = ref.watch(tmdbDetailsProvider(t));
    final d = details.value;
    final inList =
        ref.watch(wishlistProvider.select((l) => l.any((i) => i.title == t)));
    final small = TextStyle(fontSize: 12.5, color: c.muted);
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    // Image de fond proportionnée à la largeur ; l'affiche et le titre
    // viennent se poser sur son bas, en fondu (façon Seerr).
    final backdrop = d?.backdropUrl;
    final backdropHeight =
        (MediaQuery.sizeOf(context).width * 0.45).clamp(220.0, 420.0);

    // Déjà chez soi : lecture depuis l'affiche (un seul bouton dans la fiche).
    final local = localForTmdb(ref, t);
    final jellyfin = local == null ? ref.watch(jellyfinItemProvider(t)).value : null;
    final series = local?.isSeries ?? jellyfin?.isSeries ?? false;
    final VoidCallback? play = local != null
        ? () => playLocal(context, local)
        : jellyfin != null
            ? () => playOnJellyfin(context, jellyfin)
            : null;

    String hours(int minutes) => minutes < 60
        ? '$minutes min'
        : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';

    final header = Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16),
          ],
        ),
        child: Stack(alignment: Alignment.center, children: [
          Poster(t.posterUrl, width: 120, height: 180, radius: 10),
          if (play != null)
            RoundAction(
              icon: series ? Icons.video_library_rounded : Icons.play_arrow_rounded,
              color: c.success,
              tooltip: series ? 'Épisodes' : 'Lire',
              size: 52,
              onTap: play,
            ),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            if (t.originalTitle != null && t.originalTitle != t.title)
              Text(t.originalTitle!, style: small),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 6, children: [
              _Meta(t.type == TmdbType.movie
                  ? Icons.movie_outlined
                  : Icons.live_tv_rounded, t.type.label),
              if (t.year != null) _Meta(Icons.calendar_month_outlined, '${t.year}'),
              if (d?.runtime case final r? when r > 0)
                _Meta(Icons.schedule_rounded, hours(r)),
              if (d?.seasons case final s?)
                _Meta(Icons.video_library_outlined,
                    '$s saison${s > 1 ? 's' : ''}'
                    '${d!.episodes == null ? '' : ' · ${d.episodes} ép.'}'),
              if (d?.rating case final r?)
                _Meta(Icons.star_rounded,
                    '${r.toStringAsFixed(1).replaceAll('.', ',')} · ${d!.votes} votes',
                    color: c.warning),
              if (d?.certification case final cert? when cert.isNotEmpty)
                _Meta(Icons.shield_outlined, cert),
              if (d?.status case final s?) _Meta(Icons.info_outline_rounded, s),
              if (d != null && d.networks.isNotEmpty)
                _Meta(Icons.cell_tower_rounded, d.networks.take(2).join(', ')),
            ]),
          ],
        ),
      ),
    ]);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        // Bouton retour lisible sur l'image comme sur le fond uni.
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle),
            child: const BackButton(color: Colors.white),
          ),
        ),
      ),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Stack(children: [
            if (backdrop != null)
              SizedBox(
                height: backdropHeight,
                width: double.infinity,
                child: Stack(fit: StackFit.expand, children: [
                  // Recadrée par le haut : on garde les visages.
                  Poster(backdrop, radius: 0, alignment: Alignment.topCenter),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.35, 1],
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                          Theme.of(context).scaffoldBackgroundColor,
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(16,
                  backdrop == null ? topInset + 8 : backdropHeight - 130, 16, 0),
              child: header,
            ),
          ]),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d != null && d.genres.isNotEmpty) ...[
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final g in d.genres) Tag(g, color: c.accent),
                  ]),
                  const SizedBox(height: 14),
                ],
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: () =>
                        ref.read(wishlistProvider.notifier).toggle(t),
                    icon: Icon(inList
                        ? Icons.bookmark_remove_outlined
                        : Icons.bookmark_add_outlined),
                    label: Text(inList ? 'Retirer de la liste' : 'Ajouter à la liste'),
                  ),
                  if (d?.trailer case final url?)
                    FilledButton.icon(
                      style: _tinted(c, c.danger),
                      onPressed: () =>
                          launchUrl(url, mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.smart_display_rounded),
                      label: const Text('Bande-annonce'),
                    ),
                ]),
                if (details.hasError) ...[
                  const SizedBox(height: 8),
                  ErrorBanner('${details.error}',
                      onRetry: () => ref.invalidate(tmdbDetailsProvider(t))),
                ],
                _InfoBlocks(
                    title: t, dates: d?.french, loading: details.isLoading),
                if (d?.tagline case final tagline?) ...[
                  const SizedBox(height: 16),
                  Text('« $tagline »',
                      style: const TextStyle(
                          fontSize: 14, fontStyle: FontStyle.italic)),
                ],
                if (t.overview != null) ...[
                  const SizedBox(height: 10),
                  Text(t.overview!,
                      style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.5)),
                ],
                if (d != null && (d.directors.isNotEmpty || d.writers.isNotEmpty)) ...[
                  const SizedBox(height: 14),
                  if (d.directors.isNotEmpty)
                    _Credit(
                        Icons.movie_creation_outlined,
                        t.type == TmdbType.movie ? 'Réalisation' : 'Création',
                        d.directors),
                  if (d.writers.isNotEmpty)
                    _Credit(Icons.edit_note_rounded, 'Scénario', d.writers),
                ],
              ],
            ),
          ),
        ),
        if (details.isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        // Série : les épisodes directement dans la fiche, de notre base, sinon
        // de Jellyfin s'il est configuré.
        if (t.type == TmdbType.tv && localForTmdb(ref, t) != null)
          SliverToBoxAdapter(
              child: LocalEpisodesSection(title: localForTmdb(ref, t)!))
        else if (t.type == TmdbType.tv && ref.watch(jellyfinProvider) != null)
          SliverToBoxAdapter(
            child: SeriesEpisodesSection(
              series: ref.watch(jellyfinItemProvider(t)).value,
              loading: ref.watch(jellyfinItemProvider(t)).isLoading,
            ),
          ),
        if (d != null && d.cast.isNotEmpty) ...[
          const SliverToBoxAdapter(
              child: SectionTitle('Distribution', icon: Icons.groups_outlined)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: _PersonCard.height(context),
              child: posterCarousel(
                  d.cast.length, (i) => _PersonCard(person: d.cast[i])),
            ),
          ),
        ],
        if (d != null && d.recommendations.isNotEmpty) ...[
          const SliverToBoxAdapter(
              child: SectionTitle('Recommandations',
                  icon: Icons.recommend_outlined)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: PosterCard.height(context),
              child: posterCarousel(d.recommendations.length,
                  (i) => PosterCard(title: d.recommendations[i])),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}

/// Ce qu'on a déjà : le titre dans Jellyfin, et ses torrents dans
/// Transmission (téléchargés ou en cours). Rien n'est affiché s'il n'y a rien.
/// « Déjà chez toi », « Sorties en France » et « Sur les trackers » : côte à
/// côte sur PC (assez de largeur), les uns sous les autres sinon. Seuls les
/// encadrés qui ont quelque chose à montrer prennent une colonne.
class _InfoBlocks extends ConsumerWidget {
  const _InfoBlocks(
      {required this.title, required this.dates, required this.loading});
  final TmdbTitle title;
  final FrenchDates? dates;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = [
      if (_OwnedBlock.visible(ref, title)) _OwnedBlock(title: title),
      if (title.type == TmdbType.movie)
        _FrenchDatesBlock(title: title, dates: dates, loading: loading),
      if (ref.watch(trackersProvider).isNotEmpty) _TrackersBlock(title: title),
    ];
    if (blocks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 860 || blocks.length < 2) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, b) in blocks.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              b,
            ],
          ]);
        }
        // Côte à côte, tous à la hauteur du plus grand.
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, b) in blocks.indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: b),
            ],
          ]),
        );
      }),
    );
  }
}

class _OwnedBlock extends ConsumerWidget {
  const _OwnedBlock({required this.title});
  final TmdbTitle title;

  /// Quelque chose à montrer : élément Jellyfin, torrents, ou erreur.
  static bool visible(WidgetRef ref, TmdbTitle t) {
    final jellyfin = ref.watch(jellyfinItemProvider(t));
    return localForTmdb(ref, t) != null ||
        jellyfin.value != null ||
        jellyfin.hasError ||
        ref.watch(localTorrentsProvider(t)).isNotEmpty;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final jellyfin = ref.watch(jellyfinItemProvider(title));
    final item = jellyfin.value;
    final torrents = ref.watch(localTorrentsProvider(title));
    final local = localForTmdb(ref, title);
    if (local == null && item == null && torrents.isEmpty && !jellyfin.hasError) {
      return const SizedBox.shrink();
    }
    return _InfoCard(
      icon: Icons.inventory_2_rounded,
      title: 'Déjà chez toi',
      color: c.success,
      children: [
        if (local != null)
          _InfoRow(
            leading: Icon(Icons.dns_rounded, size: 20, color: c.success),
            title: 'Sur le disque',
            subtitle: local.isSeries
                ? '${local.files.length} épisode${local.files.length > 1 ? 's' : ''}'
                    ' · ${local.seasons.length} saison${local.seasons.length > 1 ? 's' : ''}'
                : [
                    for (final f in MediaTitle.best(local.files).take(3))
                      [?f.guess.resolution, formatBytes(f.size)].join(' '),
                  ].join(' · '),
          ),
        if (item != null && local == null)
          _InfoRow(
            leading: Icon(Icons.video_library_rounded, size: 20, color: c.success),
            title: 'Dans la bibliothèque Jellyfin',
            subtitle: [
              item.name,
              if (item.year != null) '${item.year}',
              if (item.played)
                'déjà vu'
              else if (item.progress case final p?)
                'vu à ${(p * 100).round()} %',
            ].join(' · '),
          ),
        if (jellyfin.hasError && local == null)
          _InfoRow(
            leading: Icon(Icons.error_outline_rounded, size: 20, color: c.danger),
            title: 'Jellyfin',
            subtitle: '${jellyfin.error}',
          ),
        for (final torrent in torrents) _LocalTorrent(torrent: torrent),
      ],
    );
  }
}

/// Encadré de la fiche (« Déjà chez toi », « Sorties en France », « Sur les
/// trackers ») : même carte, même en-tête, mêmes marges pour tous.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.children,
  });
  final IconData icon;
  final String title;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Color.lerp(color, c.surface, 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 4),
          ...children,
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Ligne d'un encadré : icône, titre, détail, et à droite une action.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.leading,
    required this.title,
    this.subtitle,
    this.detail,
    this.trailing,
  });
  /// Icône (20 px) ou indicateur de chargement.
  final Widget leading;
  final String title;
  final String? subtitle;

  /// Sous le titre, à la place de [subtitle] (barre de progression…).
  final Widget? detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: Center(child: leading),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.muted)),
            ],
            if (detail != null) ...[const SizedBox(height: 4), detail!],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}

/// Pastilles d'un souhait déjà présent : Jellyfin, Transmission.
class OwnedTags extends ConsumerWidget {
  const OwnedTags({super.key, required this.title});
  final TmdbTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final inJellyfin = ref.watch(jellyfinItemProvider(title)).value != null;
    final torrents = ref.watch(localTorrentsProvider(title));
    final done = torrents.any((t) => t.percentDone >= 1);
    final progress = torrents.isEmpty
        ? null
        : torrents.map((t) => t.percentDone).reduce(math.max);
    final onDisk = localForTmdb(ref, title) != null;
    return Wrap(spacing: 6, children: [
      if (onDisk) Tag('Sur le disque', color: c.success)
      else if (inJellyfin) Tag('Dans Jellyfin', color: c.success),
      if (done)
        Tag('Téléchargé', color: c.success)
      else if (progress != null)
        Tag('En cours ${formatPercent(progress)}', color: c.info),
    ]);
  }
}

class _LocalTorrent extends StatelessWidget {
  const _LocalTorrent({required this.torrent});
  final Torrent torrent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = torrent.percentDone >= 1;
    return _InfoRow(
      leading: Icon(done ? Icons.download_done_rounded : Icons.downloading_rounded,
          size: 20, color: done ? c.success : c.info),
      title: torrent.name,
      subtitle: done
          ? 'Téléchargé dans Transmission · ${formatBytes(torrent.totalSize)}'
          : null,
      detail: done
          ? null
          : Row(children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: torrent.percentDone,
                  color: c.download,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(formatPercent(torrent.percentDone),
                  style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
    );
  }
}

/// Bouton teinté : fond doux et bord de la couleur, texte et icône francs.
/// Couleurs opaques (mélange avec la surface), sans transparence.
ButtonStyle _tinted(AppColors c, Color color) => FilledButton.styleFrom(
      backgroundColor: Color.lerp(color, c.surface, 0.78),
      foregroundColor: Color.lerp(color, c.text, 0.25),
      side: BorderSide(color: Color.lerp(color, c.surface, 0.45)!),
    );

/// Petite info à icône (durée, note…).
class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text, {this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.colors.muted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 4),
      Text(text,
          style: TextStyle(
              fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// Disponibilité sur chaque tracker : nombre de sorties, meilleure qualité,
/// langues, seeders, freeleech. Lancée d'office pour un titre déjà sorti, à
/// la demande pour un titre à venir (inutile de solliciter les trackers).
class _TrackersBlock extends ConsumerStatefulWidget {
  const _TrackersBlock({required this.title});
  final TmdbTitle title;

  @override
  ConsumerState<_TrackersBlock> createState() => _TrackersBlockState();
}

class _TrackersBlockState extends ConsumerState<_TrackersBlock> {
  late bool _started = !widget.title.upcoming;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final trackers = ref.watch(trackersProvider).keys.toList();
    if (trackers.isEmpty) return const SizedBox.shrink();
    return _InfoCard(
      icon: Icons.travel_explore_rounded,
      title: 'Sur les trackers',
      color: c.download,
      children: [
        if (!_started)
          _InfoRow(
            leading: Icon(Icons.manage_search_rounded, size: 20, color: c.muted),
            title: 'Pas encore sorti',
            subtitle: 'La recherche se lance à la demande.',
            trailing: TextButton(
              onPressed: () => setState(() => _started = true),
              child: const Text('Vérifier la disponibilité'),
            ),
          )
        else
          for (final tr in trackers)
            _TrackerSummary(tracker: tr, title: widget.title),
      ],
    );
  }
}

/// Un tracker dans « Sur les trackers », dessiné comme un torrent des
/// Transferts : pastille d'état colorée, nom, ligne d'état, infos à icônes.
class _TrackerSummary extends ConsumerWidget {
  const _TrackerSummary({required this.tracker, required this.title});
  final Tracker tracker;
  final TmdbTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final results = ref.watch(wishSearchProvider((tracker, title)));
    final items = results.value ?? const <Release>[];
    final small = TextStyle(fontSize: 12, height: 1.3, color: c.muted);
    const mono = [FontFeature.tabularFigures()];

    Widget info(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: c.muted),
            const SizedBox(width: 4),
            Text(text, style: small.copyWith(fontFeatures: mono)),
          ]),
        );

    final Color color;
    final IconData icon;
    final String status;
    final details = <Widget>[];
    final tags = <Widget>[];
    if (results.isLoading) {
      color = c.info;
      icon = Icons.manage_search_rounded;
      status = 'Recherche…';
    } else if (results.hasError) {
      color = c.danger;
      icon = Icons.error_outline_rounded;
      status = '${results.error}';
    } else if (items.isEmpty) {
      color = c.muted;
      icon = Icons.remove_circle_outline_rounded;
      status = 'Rien pour l’instant';
    } else {
      final sum = summarizeReleases(items);
      color = c.success;
      icon = Icons.check_circle_rounded;
      status = '${items.length} sortie${items.length > 1 ? 's' : ''}';
      details.addAll([
        if (sum.bestQuality != null) info(Icons.hd_rounded, sum.bestQuality!),
        if (sum.languages.isNotEmpty)
          info(Icons.translate_rounded, sum.languages.take(3).join('/')),
        info(Icons.arrow_upward_rounded, '${sum.maxSeeders}'),
      ]);
      tags.addAll([
        if (sum.hdr) Tag('HDR', color: c.info),
        if (sum.atmos) Tag('Atmos', color: c.info),
        if (sum.freeleech > 0) Tag('FL ${sum.freeleech}', color: c.success),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
        child: InkWell(
          onTap: () => openWishSearch(context, title, tracker),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: Row(children: [
              // Pastille d'état, comme celle d'un torrent.
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: results.isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2, color: color))
                    : Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(tracker.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, height: 1.3, fontWeight: FontWeight.w700)),
                    ),
                    for (final t in tags)
                      Padding(padding: const EdgeInsets.only(left: 4), child: t),
                  ]),
                  const SizedBox(height: 4),
                  // Une ligne, coupée à droite si besoin.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Row(children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(status,
                            maxLines: 1,
                            style: small.copyWith(
                                color: color, fontWeight: FontWeight.w700)),
                      ),
                      ...details,
                    ]),
                  ),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FrenchDatesBlock extends StatelessWidget {
  const _FrenchDatesBlock(
      {required this.title, required this.dates, required this.loading});
  final TmdbTitle title;
  final FrenchDates? dates;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = dates;
    final now = DateTime.now();
    Widget cell(IconData icon, String label, DateTime? d) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 14, color: c.muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: c.muted)),
              ),
            ]),
            Text(d == null ? '—' : dayLabel(d),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: d != null && d.isAfter(now) ? c.accent : c.text)),
          ]),
        );

    return _InfoCard(
      icon: Icons.flag_rounded,
      title: 'Sorties en France',
      color: c.accent,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: loading && f == null
              ? Text('…', style: TextStyle(color: c.muted))
              : f == null || f.isEmpty
                  ? Text(
                      'Pas encore de date en France'
                      '${title.date == null ? '' : ' (sortie mondiale : ${dayLabel(title.date!)})'}',
                      style: TextStyle(fontSize: 12.5, color: c.muted))
                  : Row(children: [
                      cell(Icons.theaters_outlined, 'Cinéma', f.cinema),
                      cell(Icons.ondemand_video_rounded, 'VOD', f.digital),
                      cell(Icons.album_outlined, 'DVD / Blu-ray', f.physical),
                    ]),
        ),
      ],
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit(this.icon, this.label, this.people);
  final IconData icon;
  final String label;
  final List<TmdbPerson> people;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: context.colors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text.rich(TextSpan(children: [
          TextSpan(
              text: '$label : ',
              style: TextStyle(fontSize: 12.5, color: context.colors.muted)),
          TextSpan(
              text: people.take(4).map((p) => p.name).join(', '),
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]))),
        ]),
      );
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person});
  final TmdbPerson person;

  static const _line = 1.3;

  /// Photo, puis nom et rôle sur deux lignes chacun au plus, d'après la
  /// taille de texte du système.
  static double height(BuildContext context) {
    final s = MediaQuery.textScalerOf(context);
    return 110 + 5 + (s.scale(11.5) + s.scale(11)) * _line * 2 + 4;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 88,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        person.photoUrl == null
            ? Container(
                width: 88,
                height: 110,
                decoration: BoxDecoration(
                    color: c.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.person_outline_rounded, color: c.muted),
              )
            : Poster(person.photoUrl, width: 88, height: 110, radius: 8),
        const SizedBox(height: 5),
        Text(person.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11.5, height: _line, fontWeight: FontWeight.w600)),
        if (person.role case final role? when role.isNotEmpty)
          Text(role,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: _line, color: c.muted)),
      ]),
    );
  }
}
