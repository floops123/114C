import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api/jellyfin.dart';
import '../core/format.dart';
import '../state/media_library.dart';
import '../state/playback.dart';
import 'theme.dart';
import 'widgets.dart';

/// Lecteur intégré (media_kit, basé sur mpv) : lit le fichier d'origine, sur
/// le FTP (notre base) ou servi par Jellyfin, sans transcodage. Commandes standard (barre, volume, plein
/// écran, raccourcis clavier sur PC), choix des pistes audio et sous-titres,
/// reprise là où on s'était arrêté.
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage(
      {super.key, this.item, this.file, required this.title, this.sourceId})
      : assert(item != null || file != null);

  /// Élément Jellyfin, ou [file] : fichier de notre base, lu sur le FTP par
  /// le relais local.
  final JellyfinItem? item;
  final MediaFile? file;
  final String title;

  /// Version choisie (fichier) ; null : version par défaut de Jellyfin.
  final String? sourceId;

  /// Clé de reprise : par version, deux fichiers n'ayant pas forcément le
  /// même montage.
  String get resumeKey => file?.resumeKey ?? sourceId ?? item!.id;

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
    final start = _store.load()[widget.resumeKey] ?? widget.item?.resume;
    // Si media_kit n'a pas pu rendre la vidéo par le GPU, mpv la convertit
    // sur le processeur : mode rapide, un peu moins fin.
    if (_player.platform case final NativePlayer mpv) {
      mpv.setProperty('sw-fast', 'yes');
    }
    if (widget.file case final file?) {
      final relay = ref.read(mediaRelayProvider);
      if (relay == null) {
        _error = 'L’accès FTP n’est pas configuré';
        return;
      }
      relay.urlFor(file.path).then((url) {
        if (mounted) _player.open(Media(url.toString(), start: start));
      }, onError: (Object e) {
        if (mounted) setState(() => _error = '$e');
      });
    } else {
      final client = ref.read(jellyfinProvider);
      if (client == null) {
        _error = 'Jellyfin n’est pas configuré';
        return;
      }
      _player.open(Media(
          client.streamUrl(widget.item!.id, sourceId: widget.sourceId).toString(),
          httpHeaders: client.headers,
          start: start));
    }
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
      positions.remove(widget.resumeKey);
    } else {
      positions[widget.resumeKey] = point;
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

/// « The Bear · S03E01 · Demain ».
String episodeTitle(JellyfinItem series, JellyfinItem e) {
  String two(int? n) => (n ?? 0).toString().padLeft(2, '0');
  return [
    series.name,
    if (e.season != null || e.episode != null) 'S${two(e.season)}E${two(e.episode)}',
    e.name,
  ].join(' · ');
}

/// Lit l'un de ces éléments (un film et ses doublons, ou un épisode) : une
/// seule version → lecture directe ; plusieurs → choix de la version. Si
/// Jellyfin ne répond pas, version par défaut du premier élément.
Future<void> playVersions(
    BuildContext context, List<JellyfinItem> items, String title) async {
  final container = ProviderScope.containerOf(context);
  final client = container.read(jellyfinProvider);
  final navigator = Navigator.of(context);
  void play(JellyfinItem item, [String? sourceId]) => navigator.push(
      MaterialPageRoute(
          builder: (_) =>
              PlayerPage(item: item, title: title, sourceId: sourceId)));

  List<JellyfinVersion> versions;
  try {
    versions = client == null
        ? const []
        : await client.versions(items).timeout(const Duration(seconds: 8));
  } on Object {
    versions = const [];
  }
  if (!context.mounted) return;
  if (versions.length <= 1) {
    final v = versions.firstOrNull;
    play(v?.item ?? items.first, v?.sourceId);
    return;
  }
  // La meilleure d'abord : résolution, puis taille.
  versions = [...versions]..sort((a, b) {
      final w = (b.width ?? 0).compareTo(a.width ?? 0);
      return w != 0 ? w : (b.size ?? 0).compareTo(a.size ?? 0);
    });
  final resume = container.read(playbackStoreProvider).load();
  final chosen = await showModalBottomSheet<JellyfinVersion>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _VersionSheet(
        title: title, versions: versions, resume: resume.keys.toSet()),
  );
  if (chosen != null) play(chosen.item, chosen.sourceId);
}

class _VersionSheet extends StatelessWidget {
  const _VersionSheet(
      {required this.title, required this.versions, required this.resume});
  final String title;
  final List<JellyfinVersion> versions;

  /// Versions dont la lecture est entamée (clé de reprise).
  final Set<String> resume;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Quelle version ?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text('$title · ${versions.length} versions sur le disque',
                  style: TextStyle(fontSize: 12.5, color: c.muted)),
            ]),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final v in versions)
                ListTile(
                  leading: Icon(
                      resume.contains(v.sourceId)
                          ? Icons.play_circle_outline_rounded
                          : Icons.play_arrow_rounded,
                      color: c.accent),
                  title: Text(
                      [
                        ?v.resolution,
                        ?v.videoCodec,
                        ?v.hdr,
                        if (v.size != null) formatBytes(v.size!),
                      ].join(' · '),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      [
                        ?v.audio,
                        ?(v.fileName ?? v.name),
                        if (resume.contains(v.sourceId)) 'lecture entamée',
                      ].join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                  isThreeLine: true,
                  onTap: () => Navigator.of(context).pop(v),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
