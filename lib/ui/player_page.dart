import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api/jellyfin.dart';
import '../state/playback.dart';
import 'theme.dart';
import 'widgets.dart';

/// Lecteur intégré (media_kit, basé sur mpv) : lit le fichier d'origine servi
/// par Jellyfin, sans transcodage. Commandes standard (barre, volume, plein
/// écran, raccourcis clavier sur PC), choix des pistes audio et sous-titres,
/// reprise là où on s'était arrêté.
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.item, required this.title});
  final JellyfinItem item;
  final String title;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final Player _player = Player(
      configuration: PlayerConfiguration(title: widget.title));

  /// Image produite à la taille de l'écran (pas d'image 4K pour un écran
  /// 1080p : moins de pixels à rendre et à copier à chaque image).
  late final VideoController _video = VideoController(_player,
      configuration: VideoControllerConfiguration(
        width: _screen.width.round(),
        height: _screen.height.round(),
      ));

  static Size get _screen {
    final views = PlatformDispatcher.instance.views;
    final size = views.isEmpty ? Size.zero : views.first.physicalSize;
    return size.isEmpty
        ? const Size(1920, 1080)
        : Size(math.min(size.width, 3840), math.min(size.height, 2160));
  }

  bool _stats = false;
  late final PlaybackStore _store = ref.read(playbackStoreProvider);
  final _subscriptions = <StreamSubscription<Object?>>[];
  Duration _lastSaved = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    final client = ref.read(jellyfinProvider);
    if (client == null) {
      _error = 'Jellyfin n’est pas configuré';
      return;
    }
    final id = widget.item.id;
    final start = _store.load()[id] ?? widget.item.resume;
    // Si media_kit n'a pas pu rendre la vidéo par le GPU, mpv la convertit
    // sur le processeur : mode rapide, un peu moins fin.
    if (_player.platform case final NativePlayer mpv) {
      mpv.setProperty('sw-fast', 'yes');
    }
    _player.open(Media(client.streamUrl(id).toString(),
        httpHeaders: client.headers, start: start));
    _subscriptions
      ..add(_player.stream.position.listen((p) {
        // Sauvegarde toutes les 10 s de lecture.
        if ((p - _lastSaved).abs() >= const Duration(seconds: 10)) _save(p);
      }))
      ..add(_player.stream.error.listen((e) {
        if (mounted) setState(() => _error = e);
      }));
  }

  void _save(Duration position) {
    _lastSaved = position;
    final positions = _store.load();
    final point = resumePoint(position, _player.state.duration);
    if (point == null) {
      positions.remove(widget.item.id);
    } else {
      positions[widget.item.id] = point;
    }
    _store.save(positions);
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    if (_error == null) _save(_player.state.position);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bar = [
      const BackButton(color: Colors.white),
      Expanded(
        child: Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      _TrackMenu(player: _player, audio: true),
      _TrackMenu(player: _player, audio: false),
      IconButton(
        tooltip: 'Statistiques de lecture',
        icon: Icon(Icons.info_outline_rounded,
            color: _stats ? Colors.amber : Colors.white),
        onPressed: () => setState(() => _stats = !_stats),
      ),
    ];
    final video = Video(controller: _video);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        MaterialVideoControlsTheme(
          normal: kDefaultMaterialVideoControlsThemeData.copyWith(
              topButtonBar: bar),
          fullscreen: kDefaultMaterialVideoControlsThemeDataFullscreen
              .copyWith(topButtonBar: bar),
          child: MaterialDesktopVideoControlsTheme(
            normal: kDefaultMaterialDesktopVideoControlsThemeData.copyWith(
                topButtonBar: bar),
            fullscreen: kDefaultMaterialDesktopVideoControlsThemeDataFullscreen
                .copyWith(topButtonBar: bar),
            child: video,
          ),
        ),
        if (_stats)
          Positioned(
            left: 16,
            top: 72,
            child: IgnorePointer(child: _Stats(player: _player)),
          ),
        if (_error != null)
          SafeArea(
            child: Column(children: [
              const Align(
                  alignment: Alignment.centerLeft,
                  child: BackButton(color: Colors.white)),
              ErrorBanner('Lecture impossible : $_error'),
            ]),
          ),
      ]),
    );
  }
}

/// Statistiques mpv, relues chaque seconde : décodage matériel (vaapi…) ou
/// logiciel, codec, résolution, images perdues. Sert à comprendre une lecture
/// saccadée.
class _Stats extends StatefulWidget {
  const _Stats({required this.player});
  final Player player;

  @override
  State<_Stats> createState() => _StatsState();
}

class _StatsState extends State<_Stats> {
  static const _properties = {
    'hwdec-current': 'Décodage matériel',
    'video-codec': 'Codec vidéo',
    'video-params/w': 'Largeur',
    'video-params/h': 'Hauteur',
    'video-params/pixelformat': 'Format',
    'video-params/gamma': 'Transfert (HDR)',
    'container-fps': 'Images/s (source)',
    'estimated-vf-fps': 'Images/s (lues)',
    'frame-drop-count': 'Images perdues (rendu)',
    'decoder-frame-drop-count': 'Images perdues (décodage)',
    'audio-codec-name': 'Codec audio',
  };

  Timer? _timer;
  var _values = <String, String>{};

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _read());
  }

  Future<void> _read() async {
    final mpv = widget.player.platform;
    if (mpv is! NativePlayer) return;
    final values = <String, String>{};
    for (final p in _properties.keys) {
      try {
        values[p] = await mpv.getProperty(p);
      } on Object {
        values[p] = '—';
      }
    }
    if (mounted) setState(() => _values = values);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white, fontSize: 12, height: 1.5);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final MapEntry(key: p, value: label) in _properties.entries)
          Text('$label : ${switch (_values[p]) {
            null || '' => '—',
            'no' when p == 'hwdec-current' => 'non (logiciel)',
            final v => v,
          }}', style: style),
      ]),
    );
  }
}

/// Choix de la piste audio ou des sous-titres (pistes du fichier).
class _TrackMenu extends StatelessWidget {
  const _TrackMenu({required this.player, required this.audio});
  final Player player;
  final bool audio;

  static String _label(String? title, String? language, String id, String? codec) {
    final parts = [?title, if (language != null) language.toUpperCase(), ?codec];
    return parts.isEmpty ? 'Piste $id' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? const Tracks();
        final current = player.state.track;
        final items = <PopupMenuEntry<Object>>[];
        if (audio) {
          for (final t in tracks.audio) {
            if (t.id == 'auto' || t.id == 'no') continue;
            items.add(CheckedPopupMenuItem(
              value: t,
              checked: current.audio.id == t.id,
              child: Text(_label(t.title, t.language, t.id, t.codec)),
            ));
          }
        } else {
          items.add(CheckedPopupMenuItem(
            value: SubtitleTrack.no(),
            checked: current.subtitle.id == 'no',
            child: const Text('Aucun'),
          ));
          for (final t in tracks.subtitle) {
            if (t.id == 'auto' || t.id == 'no') continue;
            items.add(CheckedPopupMenuItem(
              value: t,
              checked: current.subtitle.id == t.id,
              child: Text(_label(t.title, t.language, t.id, t.codec)),
            ));
          }
        }
        return PopupMenuButton<Object>(
          tooltip: audio ? 'Piste audio' : 'Sous-titres',
          enabled: items.length > (audio ? 0 : 1),
          icon: Icon(audio ? Icons.audiotrack_rounded : Icons.subtitles_rounded,
              color: Colors.white),
          onSelected: (t) => switch (t) {
            final AudioTrack a => player.setAudioTrack(a),
            final SubtitleTrack s => player.setSubtitleTrack(s),
            _ => null,
          },
          itemBuilder: (_) => items,
        );
      },
    );
  }
}

/// Épisodes d'une série Jellyfin, par saison ; un épisode se lit dans le
/// lecteur intégré.
class EpisodesPage extends ConsumerStatefulWidget {
  const EpisodesPage({super.key, required this.series});
  final JellyfinItem series;

  @override
  ConsumerState<EpisodesPage> createState() => _EpisodesPageState();
}

class _EpisodesPageState extends ConsumerState<EpisodesPage> {
  late Future<List<JellyfinItem>> _episodes = _load();

  Future<List<JellyfinItem>> _load() async {
    final client = ref.read(jellyfinProvider);
    if (client == null) throw const JellyfinException('Jellyfin n’est pas configuré');
    return client.episodes(widget.series.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final resume = ref.read(playbackStoreProvider).load();
    return Scaffold(
      appBar: AppBar(title: Text(widget.series.name)),
      body: FutureBuilder<List<JellyfinItem>>(
        future: _episodes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(Icons.error_outline_rounded, '${snapshot.error}',
                action: OutlinedButton(
                  onPressed: () => setState(() => _episodes = _load()),
                  child: const Text('Réessayer'),
                ));
          }
          final episodes = snapshot.data;
          if (episodes == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (episodes.isEmpty) {
            return const EmptyState(Icons.video_library_outlined, 'Aucun épisode.');
          }
          final rows = <Object>[];
          int? season;
          for (final e in episodes) {
            if (e.season != season) {
              season = e.season;
              rows.add(season == null || season == 0
                  ? 'Hors saison'
                  : 'Saison $season');
            }
            rows.add(e);
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) => switch (rows[i]) {
              final String header => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Text(header,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              final JellyfinItem e => ListTile(
                  leading: Icon(
                      e.played
                          ? Icons.check_circle_rounded
                          : resume.containsKey(e.id) || e.resume != null
                              ? Icons.play_circle_outline_rounded
                              : Icons.play_arrow_rounded,
                      color: e.played ? c.success : c.accent),
                  title: Text(
                      '${e.episode == null ? '' : '${e.episode}. '}${e.name}'),
                  subtitle: e.overview == null
                      ? null
                      : Text(e.overview!,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PlayerPage(
                          item: e,
                          title: episodeTitle(widget.series, e)))),
                ),
              _ => const SizedBox.shrink(),
            },
          );
        },
      ),
    );
  }
}

/// « The Bear · S03E01 · Demain ».
String episodeTitle(JellyfinItem series, JellyfinItem e) {
  String two(int? n) => (n ?? 0).toString().padLeft(2, '0');
  return [
    series.name,
    if (e.season != null || e.episode != null) 'S${two(e.season)}E${two(e.episode)}',
    e.name,
  ].join(' · ');
}
