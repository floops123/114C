import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tmdb.dart';
import '../core/format.dart';
import '../state/media_library.dart';
import '../state/playback.dart';
import 'content_art.dart';
import 'player_page.dart';
import 'theme.dart';
import 'widgets.dart';
import 'wishlist_page.dart' show openTitle;

// Notre base : films et séries trouvés sur le FTP du serveur, lus directement
// par le lecteur intégré.

/// Le titre de la base pour une fiche TMDB, ou null.
MediaTitle? localForTmdb(WidgetRef ref, TmdbTitle t) =>
    ref.watch(mediaLibraryProvider.select((s) => s.library.forTmdb(t)));

String _two(int? n) => (n ?? 0).toString().padLeft(2, '0');

String _code(MediaFile f) =>
    'S${_two(f.guess.season)}E${_two(f.guess.episode)}';

String _versionLabel(MediaFile f) => [
      ?f.guess.resolution,
      ?f.guess.source,
      ?f.guess.videoCodec,
      formatBytes(f.size),
    ].join(' · ');

/// Lit un film (choix de la version s'il y en a plusieurs) ; pour une série,
/// ouvre la liste des épisodes.
void playLocal(BuildContext context, MediaTitle title) {
  if (title.isSeries) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LocalSeriesPage(title: title)));
    return;
  }
  playFiles(context, title.files,
      [title.title, if (title.year != null) '(${title.year})'].join(' '));
}

/// Une version → lecture directe ; plusieurs → choix, la meilleure d'abord.
Future<void> playFiles(
    BuildContext context, List<MediaFile> files, String title) async {
  final navigator = Navigator.of(context);
  void play(MediaFile f) => navigator.push(MaterialPageRoute(
      builder: (_) => PlayerPage(file: f, title: title)));
  if (files.length == 1) {
    play(files.single);
    return;
  }
  final resume = ProviderScope.containerOf(context).read(playbackStoreProvider).load();
  final sorted = MediaTitle.best(files);
  final chosen = await showModalBottomSheet<MediaFile>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      final c = sheet.colors;
      return SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Quelle version ?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text('$title · ${files.length} versions sur le disque',
                    style: TextStyle(fontSize: 12.5, color: c.muted)),
              ]),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final f in sorted)
                  ListTile(
                    leading: Icon(
                        resume.containsKey(f.resumeKey)
                            ? Icons.play_circle_outline_rounded
                            : Icons.play_arrow_rounded,
                        color: c.accent),
                    title: Text(_versionLabel(f),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        [
                          f.name,
                          if (resume.containsKey(f.resumeKey)) 'lecture entamée',
                        ].join('\n'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(sheet).pop(f),
                  ),
              ]),
            ),
          ]),
        ),
      );
    },
  );
  if (chosen != null) play(chosen);
}

/// État du parcours : en cours, erreur, ou date du dernier parcours ; et le
/// bouton pour relancer.
class LibraryStatus extends ConsumerWidget {
  const LibraryStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final state = ref.watch(mediaLibraryProvider);
    final library = state.library;
    final films = library.titles.where((t) => !t.isSeries).length;
    final series = library.titles.length - films;
    final text = state.scanning
        ? state.status ?? 'Parcours du serveur…'
        : state.stale
            ? 'Accès aux fichiers modifié : Actualiser pour reparcourir'
            : [
            '$films film${films > 1 ? 's' : ''}',
            '$series série${series > 1 ? 's' : ''}',
            if (library.scannedAt != null) 'à jour ${formatAgo(library.scannedAt!)}',
          ].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
        child: Row(children: [
          if (state.scanning)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: SizedBox.square(
                  dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(state.stale ? Icons.sync_problem_rounded : Icons.dns_rounded,
                  size: 18, color: state.stale ? c.warning : c.success),
            ),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: c.muted)),
          ),
          TextButton.icon(
            onPressed: state.scanning
                ? null
                : () => ref.read(mediaLibraryProvider.notifier).scan(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Actualiser'),
          ),
        ]),
      ),
      if (state.error != null)
        ErrorBanner(state.error!,
            onRetry: () => ref.read(mediaLibraryProvider.notifier).scan()),
    ]);
  }
}

/// Carte d'un titre de notre base : affiche TMDB (ou image du type),
/// nombre d'épisodes ou de versions, bouton de lecture.
class LocalTitleCard extends StatelessWidget {
  const LocalTitleCard({super.key, required this.title});
  final MediaTitle title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = title;
    final count = t.isSeries
        ? '${t.files.length} épisode${t.files.length > 1 ? 's' : ''}'
        : t.files.length > 1
            ? '${t.files.length} versions'
            : t.files.first.guess.resolution;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      // Fiche complète si TMDB la connaît ; sinon lecture ou épisodes.
      onTap: () => t.tmdb != null ? openTitle(context, t.tmdb!) : playLocal(context, t),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(fit: StackFit.expand, children: [
            Poster(t.tmdb?.posterUrl,
                radius: 8,
                fallback: ContentArt(
                    t.isSeries ? ContentKind.series : ContentKind.movie)),
            Positioned(
              left: 5,
              top: 5,
              child: Tag(t.type.label,
                  solid: true, color: t.isSeries ? c.info : null),
            ),
            Positioned(
              right: 5,
              top: 5,
              child: Material(
                color: c.success,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => playLocal(context, t),
                  child: SizedBox.square(
                    dimension: 32,
                    child: Icon(
                        t.isSeries ? Icons.video_library_rounded : Icons.play_arrow_rounded,
                        size: 20,
                        color: Colors.white),
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 5),
        Text(t.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w600)),
        Builder(builder: (context) {
          final style = TextStyle(fontSize: 11.5, height: 1.3, color: c.muted);
          return Text.rich(
            TextSpan(children: [
              TextSpan(text: [if (t.year != null) '${t.year}', ?count].join(' · ')),
              if (t.tmdb?.rating case final r?) ...[
                const TextSpan(text: ' · '),
                ratingSpan(context, r, style),
              ],
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }),
      ]),
    );
  }
}

/// Une série de notre base, en page entière.
class LocalSeriesPage extends StatelessWidget {
  const LocalSeriesPage({super.key, required this.title});
  final MediaTitle title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title.title)),
        body: ListView(children: [
          LocalEpisodesSection(title: title, header: false),
          const SizedBox(height: 24),
        ]),
      );
}

/// Saisons et épisodes d'une série de notre base, avec les titres et résumés
/// TMDB ; on choisit l'épisode à regarder.
class LocalEpisodesSection extends ConsumerStatefulWidget {
  const LocalEpisodesSection({super.key, required this.title, this.header = true});
  final MediaTitle title;
  final bool header;

  @override
  ConsumerState<LocalEpisodesSection> createState() => _LocalEpisodesSectionState();
}

class _LocalEpisodesSectionState extends ConsumerState<LocalEpisodesSection> {
  int? _season;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = widget.title;
    final seasons = title.seasons;
    final resume = ref.watch(playbackStoreProvider).load();
    // Saison affichée : celle choisie, sinon celle d'un épisode entamé, sinon
    // la dernière.
    final started = title.files.where((f) => resume.containsKey(f.resumeKey));
    final season = seasons.containsKey(_season)
        ? _season!
        : started.firstOrNull?.guess.season ?? seasons.keys.last;
    final tmdbId = title.tmdb?.id;
    final details = tmdbId == null
        ? null
        : ref.watch(tmdbSeasonProvider((tmdbId, season))).value;
    final byNumber = {for (final e in details ?? const <TmdbEpisode>[]) e.number: e};

    // Plusieurs versions d'un même épisode : une seule ligne, choix à la lecture.
    final episodes = <int, List<MediaFile>>{};
    for (final f in seasons[season]!) {
      (episodes[f.guess.episode ?? 0] ??= []).add(f);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.header)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
          child: Row(children: [
            Icon(Icons.video_library_outlined, size: 18, color: c.muted),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Épisodes sur le disque',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ]),
        )
      else
        const SizedBox(height: 12),
      ChipRow<int>(
        items: seasons.keys.toList(),
        selected: season,
        label: (n) =>
            '${n == 0 ? 'Épisodes spéciaux' : 'Saison $n'} (${seasons[n]!.length})',
        icon: (_) => Icons.video_library_rounded,
        onSelected: (n) => setState(() => _season = n),
      ),
      const SizedBox(height: 8),
      for (final MapEntry(key: number, value: files) in episodes.entries)
        _LocalEpisodeCard(
          series: title,
          files: files,
          episode: byNumber[number],
          started: files.any((f) => resume.containsKey(f.resumeKey)),
        ),
    ]);
  }
}

class _LocalEpisodeCard extends StatelessWidget {
  const _LocalEpisodeCard({
    required this.series,
    required this.files,
    required this.episode,
    required this.started,
  });
  final MediaTitle series;
  final List<MediaFile> files;
  final TmdbEpisode? episode;
  final bool started;

  String get _playTitle =>
      [series.title, _code(files.first), ?episode?.name].join(' · ');

  void _play(BuildContext context) => playFiles(context, files, _playTitle);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = episode;
    final f = files.first;
    final width = MediaQuery.sizeOf(context).width >= 720 ? 200.0 : 140.0;
    final meta = [
      _code(f),
      if (e?.runtime case final r?) '$r min',
      if (e?.airDate case final d?) formatDate(d).substring(0, 10),
      files.length > 1 ? '${files.length} versions' : _versionLabel(f),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showDetail(context),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: width,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(fit: StackFit.expand, children: [
                    Poster(e?.stillUrl,
                        radius: 8,
                        fallback: const ContentArt(ContentKind.series, radius: 8)),
                    if (started)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Tag('ENTAMÉ', solid: true, color: c.download),
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      e == null || e.name.isEmpty
                          ? 'Épisode ${f.guess.episode}'
                          : '${e.number}. ${e.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted)),
                  if (e?.overview case final o?) ...[
                    const SizedBox(height: 4),
                    Text(o,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4)),
                  ],
                ]),
              ),
              IconButton(
                tooltip: started ? 'Reprendre' : 'Lire',
                icon: Icon(Icons.play_circle_fill_rounded, size: 32, color: c.accent),
                onPressed: () => _play(context),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Détail de l'épisode dans une fenêtre en bas : grande vignette, résumé
  /// complet, fichiers.
  void _showDetail(BuildContext context) {
    final e = episode;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) {
        final c = sheet.colors;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Poster(e?.stillUrl,
                    radius: 10,
                    fallback: const ContentArt(ContentKind.series, radius: 10)),
              ),
              const SizedBox(height: 12),
              Text('${_code(files.first)} · ${series.title}',
                  style: TextStyle(
                      fontSize: 12, color: c.muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(e?.name ?? 'Épisode ${files.first.guess.episode}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    _play(context);
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(started ? 'Reprendre' : 'Lire'),
                ),
              ),
              if (e?.overview case final o?) ...[
                const SizedBox(height: 12),
                Text(o, style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.5)),
              ],
              const SizedBox(height: 12),
              for (final f in files)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${_versionLabel(f)}\n${f.path}',
                      style: TextStyle(fontSize: 12, color: c.muted)),
                ),
            ]),
          ),
        );
      },
    );
  }
}
