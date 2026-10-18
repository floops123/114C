import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/jellyfin.dart';
import '../core/format.dart';
import '../state/playback.dart';
import 'content_art.dart';
import 'player_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Épisode à proposer : celui en cours (reprise locale ou Jellyfin), sinon le
/// premier non vu après le dernier vu, sinon le premier.
JellyfinItem? nextEpisode(List<JellyfinItem> episodes, Set<String> resumed) {
  for (final e in episodes) {
    if (!e.played && (resumed.contains(e.id) || e.resume != null)) return e;
  }
  final lastPlayed = episodes.lastIndexWhere((e) => e.played);
  for (final e in episodes.skip(lastPlayed + 1)) {
    if (!e.played) return e;
  }
  return episodes.firstOrNull;
}

/// Avancement d'un épisode (0 à 1), d'après la reprise locale, sinon Jellyfin.
double? episodeProgress(JellyfinItem e, Map<String, Duration> local) {
  if (e.played) return 1;
  final runtime = e.runtime;
  final position = local[e.id] ?? e.resume;
  if (runtime != null && position != null && runtime > Duration.zero) {
    return (position.inSeconds / runtime.inSeconds).clamp(0.0, 1.0);
  }
  return e.progress;
}

String _durationLabel(Duration d) => d.inMinutes < 60
    ? '${d.inMinutes} min'
    : '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';

String _code(JellyfinItem e) {
  String two(int? n) => (n ?? 0).toString().padLeft(2, '0');
  return e.season == null && e.episode == null
      ? ''
      : 'S${two(e.season)}E${two(e.episode)}';
}

void playEpisode(BuildContext context, JellyfinItem series, JellyfinItem e) =>
    playVersions(context, [e], episodeTitle(series, e));

/// Détail d'un épisode dans une fenêtre en bas, avec son bouton de lecture.
Future<void> showEpisodeDetail(
        BuildContext context, JellyfinItem series, JellyfinItem e) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _EpisodeDetail(
              series: series,
              episode: e,
              onPlay: () {
                Navigator.of(sheet).pop();
                playEpisode(context, series, e);
              }),
        ),
      ),
    );

/// Section « Épisodes sur le disque » de la fiche d'une série : saisons et
/// épisodes directement dans la fiche, sinon ce qui manque. [series] null :
/// série non reconnue dans Jellyfin.
class SeriesEpisodesSection extends ConsumerStatefulWidget {
  const SeriesEpisodesSection(
      {super.key, required this.series, this.loading = false});
  final JellyfinItem? series;

  /// Index Jellyfin encore en chargement (rien à conclure).
  final bool loading;

  @override
  ConsumerState<SeriesEpisodesSection> createState() =>
      _SeriesEpisodesSectionState();
}

class _SeriesEpisodesSectionState extends ConsumerState<SeriesEpisodesSection> {
  int? _season;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final series = widget.series;
    Widget message(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(text, style: TextStyle(fontSize: 13, color: c.muted)),
        );

    final Widget body;
    if (series == null && widget.loading) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (series == null) {
      body = message('Série pas trouvée dans ta bibliothèque Jellyfin.');
    } else {
      final show = ref.watch(jellyfinShowProvider(series));
      final local = ref.watch(playbackStoreProvider).load();
      body = show.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => message('Jellyfin : $e'),
        data: (show) {
          final episodes = show.episodes;
          if (episodes.isEmpty) {
            return message('Jellyfin ne renvoie aucun épisode pour cette série.');
          }
          final next = nextEpisode(episodes, local.keys.toSet());
          final numbers = {for (final e in episodes) e.season ?? 0}.toList()
            ..sort();
          final season = numbers.contains(_season)
              ? _season!
              : (next?.season ?? numbers.first);
          final names = {for (final s in show.seasons) s.number: s.name};
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ChipRow<int>(
              items: numbers,
              selected: season,
              label: (n) =>
                  '${names[n] ?? (n == 0 ? 'Épisodes spéciaux' : 'Saison $n')} '
                  '(${episodes.where((e) => (e.season ?? 0) == n).length})',
              icon: (_) => Icons.video_library_rounded,
              onSelected: (n) => setState(() => _season = n),
            ),
            const SizedBox(height: 8),
            for (final e in episodes)
              if ((e.season ?? 0) == season)
                _EpisodeCard(
                  series: show.series,
                  episode: e,
                  progress: episodeProgress(e, local),
                  isNext: e == next,
                  selected: false,
                  onTap: () => showEpisodeDetail(context, show.series, e),
                  onPlay: () => playEpisode(context, show.series, e),
                ),
          ]);
        },
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
        child: Row(children: [
          Icon(Icons.video_library_outlined, size: 18, color: c.muted),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Épisodes sur le disque',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          if (series != null)
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EpisodesPage(series: series))),
              child: const Text('Tout voir'),
            ),
        ]),
      ),
      body,
    ]);
  }
}

/// Une série Jellyfin : fiche, saisons, épisodes avec leurs détails ; on
/// choisit l'épisode à regarder (lecteur intégré, choix de la version).
class EpisodesPage extends ConsumerStatefulWidget {
  const EpisodesPage({super.key, required this.series});
  final JellyfinItem series;

  @override
  ConsumerState<EpisodesPage> createState() => _EpisodesPageState();
}

class _EpisodesPageState extends ConsumerState<EpisodesPage> {
  int? _season;
  JellyfinItem? _selected;

  void _play(JellyfinItem series, JellyfinItem e) =>
      playEpisode(context, series, e);

  Future<void> _showDetail(JellyfinItem series, JellyfinItem e) =>
      showEpisodeDetail(context, series, e);

  @override
  Widget build(BuildContext context) {
    final show = ref.watch(jellyfinShowProvider(widget.series));
    final local = ref.watch(playbackStoreProvider).load();

    return Scaffold(
      appBar: AppBar(title: Text(widget.series.name)),
      body: show.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(Icons.error_outline_rounded, '$e',
            action: OutlinedButton(
              onPressed: () => ref.invalidate(jellyfinShowProvider(widget.series)),
              child: const Text('Réessayer'),
            )),
        data: (show) {
          final episodes = show.episodes;
          if (episodes.isEmpty) {
            return const EmptyState(
              Icons.video_library_outlined,
              'Jellyfin ne renvoie aucun épisode pour cette série.',
            );
          }
          final next = nextEpisode(episodes, local.keys.toSet());
          final numbers = {for (final e in episodes) e.season ?? 0}.toList()..sort();
          final season = numbers.contains(_season)
              ? _season!
              : (next?.season ?? numbers.first);
          final names = {for (final s in show.seasons) s.number: s.name};
          String seasonName(int n) =>
              names[n] ?? (n == 0 ? 'Épisodes spéciaux' : 'Saison $n');
          final inSeason = [
            for (final e in episodes)
              if ((e.season ?? 0) == season) e,
          ];
          final selected = inSeason.contains(_selected)
              ? _selected!
              : (inSeason.contains(next) ? next! : inSeason.first);

          return LayoutBuilder(builder: (context, constraints) {
            // PC : détail de l'épisode choisi à droite de la liste.
            final wide = constraints.maxWidth >= 1000;
            final list = ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _SeriesHeader(
                    show: show, seasons: numbers.length, onPlayNext: next == null
                        ? null
                        : () => _play(show.series, next),
                    next: next),
                ChipRow<int>(
                  items: numbers,
                  selected: season,
                  label: (n) =>
                      '${seasonName(n)} (${episodes.where((e) => (e.season ?? 0) == n).length})',
                  onSelected: (n) => setState(() {
                    _season = n;
                    _selected = null;
                  }),
                ),
                const SizedBox(height: 8),
                for (final e in inSeason)
                  _EpisodeCard(
                    series: show.series,
                    episode: e,
                    progress: episodeProgress(e, local),
                    isNext: e == next,
                    selected: wide && e == selected,
                    onTap: () => wide
                        ? setState(() => _selected = e)
                        : _showDetail(show.series, e),
                    onPlay: () => _play(show.series, e),
                  ),
              ],
            );
            if (!wide) return list;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: list),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 24),
                  child: Panel(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _EpisodeDetail(
                          series: show.series,
                          episode: selected,
                          onPlay: () => _play(show.series, selected)),
                    ),
                  ),
                ),
              ),
            ]);
          });
        },
      ),
    );
  }
}

class _SeriesHeader extends ConsumerWidget {
  const _SeriesHeader(
      {required this.show,
      required this.seasons,
      required this.next,
      required this.onPlayNext});
  final JellyfinShow show;
  final int seasons;
  final JellyfinItem? next;
  final VoidCallback? onPlayNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final client = ref.watch(jellyfinProvider);
    final s = show.series;
    final poster = client?.imageUrl(s.id, tag: s.imageTag, maxWidth: 300).toString();
    final watched = show.episodes.where((e) => e.played).length;
    final n = next;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Poster(poster,
            width: 100,
            height: 150,
            radius: 10,
            fallback: const ContentArt(ContentKind.series, radius: 10)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                [s.name, if (s.year != null) '(${s.year})'].join(' '),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
                [
                  '$seasons saison${seasons > 1 ? 's' : ''}',
                  '${show.episodes.length} épisode${show.episodes.length > 1 ? 's' : ''} sur le disque',
                  if (watched > 0) '$watched vu${watched > 1 ? 's' : ''}',
                  ...s.genres.take(3),
                ].join(' · '),
                style: TextStyle(fontSize: 12.5, color: c.muted)),
            if (s.overview != null) ...[
              const SizedBox(height: 8),
              Text(s.overview!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.muted, height: 1.45)),
            ],
            if (n != null && onPlayNext != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: onPlayNext,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('${n.resume != null ? 'Reprendre' : 'Regarder'} '
                    '${_code(n)}'),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Carte d'un épisode : vignette (avancement, « vu »), numéro, titre, durée,
/// date, note et résumé ; bouton de lecture.
class _EpisodeCard extends ConsumerWidget {
  const _EpisodeCard({
    required this.series,
    required this.episode,
    required this.progress,
    required this.isNext,
    required this.selected,
    required this.onTap,
    required this.onPlay,
  });
  final JellyfinItem series;
  final JellyfinItem episode;
  final double? progress;
  final bool isNext;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final e = episode;
    final client = ref.watch(jellyfinProvider);
    final thumb = client == null || e.imageTag == null
        ? null
        : client.imageUrl(e.id, tag: e.imageTag, maxWidth: 400).toString();
    final width = MediaQuery.sizeOf(context).width >= 720 ? 200.0 : 140.0;
    final p = progress;
    final meta = [
      if (e.runtime != null) _durationLabel(e.runtime!),
      if (e.premiere != null) formatDate(e.premiere!).substring(0, 10),
      if (e.rating case final r? when r > 0)
        '★ ${r.toStringAsFixed(1).replaceAll('.', ',')}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: selected ? c.accent.withValues(alpha: 0.10) : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? c.accent : c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: width,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(fit: StackFit.expand, children: [
                    Poster(thumb,
                        radius: 8,
                        fallback: const ContentArt(ContentKind.series, radius: 8)),
                    if (e.played)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Tag('VU', solid: true, color: c.success),
                      ),
                    if (p != null && p > 0 && p < 1)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                            value: p, minHeight: 4, color: c.download),
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                          '${e.episode == null ? '' : '${e.episode}. '}${e.name}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    if (isNext) Tag('À SUIVRE', color: c.accent),
                  ]),
                  if (meta.isNotEmpty)
                    Text(meta, style: TextStyle(fontSize: 12, color: c.muted)),
                  if (e.overview != null) ...[
                    const SizedBox(height: 4),
                    Text(e.overview!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4)),
                  ],
                ]),
              ),
              IconButton(
                tooltip: p != null && p > 0 && p < 1 ? 'Reprendre' : 'Lire',
                icon: Icon(Icons.play_circle_fill_rounded, size: 32, color: c.accent),
                onPressed: onPlay,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Détail d'un épisode : grande vignette, titre, infos, résumé complet.
class _EpisodeDetail extends ConsumerWidget {
  const _EpisodeDetail(
      {required this.series, required this.episode, required this.onPlay});
  final JellyfinItem series;
  final JellyfinItem episode;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final e = episode;
    final client = ref.watch(jellyfinProvider);
    final thumb = client == null || e.imageTag == null
        ? null
        : client.imageUrl(e.id, tag: e.imageTag, maxWidth: 960).toString();
    final local = ref.watch(playbackStoreProvider).load();
    final p = episodeProgress(e, local);
    final resumable = p != null && p > 0 && p < 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AspectRatio(
        aspectRatio: 16 / 9,
        child: Poster(thumb,
            radius: 10, fallback: const ContentArt(ContentKind.series, radius: 10)),
      ),
      const SizedBox(height: 12),
      Text(
          [_code(e), series.name].where((t) => t.isNotEmpty).join(' · '),
          style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(e.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Wrap(spacing: 12, runSpacing: 4, children: [
        if (e.runtime != null) _info(c, Icons.schedule_rounded, _durationLabel(e.runtime!)),
        if (e.premiere != null)
          _info(c, Icons.event_outlined, formatDate(e.premiere!).substring(0, 10)),
        if (e.rating case final r? when r > 0)
          _info(c, Icons.star_rounded, r.toStringAsFixed(1).replaceAll('.', ',')),
        if (e.played) _info(c, Icons.check_circle_rounded, 'Vu')
        else if (resumable) _info(c, Icons.timelapse_rounded, 'Vu à ${(p * 100).round()} %'),
      ]),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: onPlay,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(resumable ? 'Reprendre' : 'Lire'),
        ),
      ),
      if (e.overview != null) ...[
        const SizedBox(height: 12),
        Text(e.overview!,
            style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.5)),
      ],
    ]);
  }

  static Widget _info(AppColors c, IconData icon, String text) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: c.muted),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12.5, color: c.muted)),
      ]);
}
