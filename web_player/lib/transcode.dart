import 'dart:convert';
import 'dart:io';

/// Une piste audio d'un fichier.
class AudioTrack {
  const AudioTrack(this.index, this.codec, this.language, this.channels, this.title,
      {this.isDefault = false});

  /// Index du flux dans le fichier (pour `-map 0:<index>`).
  final int index;
  final String codec;
  final String? language;
  final int channels;
  final String? title;

  /// Marquée « par défaut » : celle qu'un navigateur joue en lecture directe.
  final bool isDefault;

  /// Code de codec pour `canPlayType` (`audio/mp4; codecs="…"`) ; null : aucun
  /// navigateur ne le lit (DTS, TrueHD…).
  String? get mime => switch (codec) {
        'aac' => 'audio/mp4; codecs="mp4a.40.2"',
        'mp3' => 'audio/mpeg',
        'opus' => 'audio/webm; codecs="opus"',
        'vorbis' => 'audio/webm; codecs="vorbis"',
        'flac' => 'audio/mp4; codecs="flac"',
        'ac3' => 'audio/mp4; codecs="ac-3"',
        'eac3' => 'audio/mp4; codecs="ec-3"',
        _ => null,
      };

  bool get french =>
      const {'fre', 'fra', 'fr', 'french'}.contains(language?.toLowerCase()) ||
      RegExp(r'\b(vff|vfq|vf2|vfi|fran[cç]ais|french)\b', caseSensitive: false)
          .hasMatch(title ?? '');

  Map<String, Object?> toJson() => {
        'index': index,
        'codec': codec,
        'language': language,
        'channels': channels,
        'title': title,
        'default': isDefault,
        'mime': mime,
      };
}

/// Ce que `ffprobe` dit d'un fichier, et comment le servir au navigateur.
class MediaInfo {
  const MediaInfo({
    required this.container,
    required this.duration,
    this.videoCodec,
    this.pixelFormat,
    this.width,
    this.videoProfile,
    this.videoLevel,
    this.audio = const [],
  });

  final String container;
  final double duration;
  final String? videoCodec;
  final String? pixelFormat;
  final int? width;
  final String? videoProfile;
  final int? videoLevel;
  final List<AudioTrack> audio;

  /// Type MIME et codec de la vidéo pour `canPlayType`, dans un conteneur MP4
  /// (celui du flux converti) ; null : aucun navigateur ne la lit.
  String? get videoMime {
    final level = videoLevel ?? 0;
    final tenBit = (pixelFormat ?? '').contains('10');
    return switch (videoCodec) {
      'h264' => 'video/mp4; codecs="avc1.${switch (videoProfile) {
            'Baseline' || 'Constrained Baseline' => '42',
            'Main' => '4d',
            'High 10' => '6e',
            _ => '64',
          }}00${level.clamp(10, 62).toRadixString(16).padLeft(2, '0')}"',
      'hevc' => 'video/mp4; codecs="hvc1.${tenBit ? '2.4' : '1.6'}.L${level == 0 ? 120 : level}.B0"',
      'av1' => 'video/mp4; codecs="av01.0.08M.${tenBit ? '10' : '08'}"',
      'vp9' => 'video/webm; codecs="vp9"',
      _ => null,
    };
  }

  /// Piste que le navigateur jouerait en lecture directe : celle marquée
  /// par défaut, sinon la première.
  AudioTrack? get browserAudio =>
      audio.where((a) => a.isDefault).firstOrNull ?? audio.firstOrNull;

  /// Depuis la sortie JSON de `ffprobe -show_format -show_streams`.
  factory MediaInfo.parse(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final format = (data['format'] as Map?)?.cast<String, dynamic>() ?? const {};
    final streams = [
      for (final s in (data['streams'] as List? ?? const []).whereType<Map>())
        s.cast<String, dynamic>(),
    ];
    final video = streams
        .where((s) => s['codec_type'] == 'video' && s['disposition']?['attached_pic'] != 1)
        .firstOrNull;
    return MediaInfo(
      container: format['format_name'] as String? ?? '',
      duration: double.tryParse('${format['duration']}') ?? 0,
      videoCodec: video?['codec_name'] as String?,
      pixelFormat: video?['pix_fmt'] as String?,
      width: (video?['width'] as num?)?.toInt(),
      videoProfile: video?['profile'] as String?,
      videoLevel: (video?['level'] as num?)?.toInt(),
      audio: [
        for (final s in streams)
          if (s['codec_type'] == 'audio')
            AudioTrack(
              (s['index'] as num).toInt(),
              s['codec_name'] as String? ?? '',
              (s['tags'] as Map?)?['language'] as String?,
              (s['channels'] as num?)?.toInt() ?? 2,
              (s['tags'] as Map?)?['title'] as String?,
              isDefault: (s['disposition'] as Map?)?['default'] == 1,
            ),
      ],
    );
  }

  /// Piste audio par défaut : la première en français, sinon la première.
  AudioTrack? get preferredAudio =>
      audio.where((a) => a.french).firstOrNull ?? audio.firstOrNull;

  bool get _h264 => videoCodec == 'h264' && (pixelFormat ?? 'yuv420p') == 'yuv420p';

  /// Le navigateur lit le fichier tel quel : MP4 ou WebM, vidéo H.264 8 bits
  /// (ou VP9 / AV1), audio AAC, MP3 ou Opus.
  bool get direct {
    final mp4 = container.contains('mp4') || container.contains('mov');
    final webm = container == 'webm' || container.startsWith('matroska,webm') && videoCodec == 'vp9';
    final video = _h264 || const {'vp9', 'av1'}.contains(videoCodec);
    final sound = audio.isEmpty ||
        const {'aac', 'mp3', 'opus', 'vorbis'}.contains(preferredAudio?.codec);
    return (mp4 || webm) && video && sound;
  }

  /// La vidéo sera-t-elle copiée telle quelle (voir [ffmpegArgs]) ?
  bool copiesVideo({bool copyVideo = false}) => _h264 || (copyVideo && videoMime != null);

  /// Arguments ffmpeg pour servir le fichier en MP4 fragmenté, à partir de
  /// [start] secondes. Vidéo copiée (rapide, quasiment sans calcul) si elle
  /// est en H.264 8 bits, ou si le navigateur a dit savoir la décoder
  /// ([copyVideo] : H.265, AV1…) ; sinon réencodée en H.264 (1080p au plus).
  /// Audio en AAC stéréo, piste [audioIndex] (par défaut, la française).
  ///
  /// Vidéo copiée : elle ne peut partir que d'une image clé, alors qu'une
  /// recherche précise ferait partir l'audio pile à [start]. ffmpeg comble
  /// l'écart par un trou au début de la piste audio, que les navigateurs
  /// ignorent : le son passait en avance de plusieurs secondes. On part donc
  /// d'une image clé pour les deux pistes (`-noaccurate_seek`) ; [start] doit
  /// être cette image clé ([keyframeBefore]). +0,2 s : ffmpeg recule de 3/23 s
  /// avant de chercher dans un MKV, et retomberait sur l'image clé précédente.
  List<String> ffmpegArgs(String input,
      {double start = 0, int? audioIndex, bool copyVideo = false}) {
    final track = audio.where((a) => a.index == audioIndex).firstOrNull ?? preferredAudio;
    final copyAudio = track != null && track.codec == 'aac' && track.channels <= 2;
    final copy = copiesVideo(copyVideo: copyVideo);
    return [
      '-hide_banner', '-loglevel', 'error', '-nostdin',
      if (start > 0 && copy) ...['-noaccurate_seek', '-ss', (start + 0.2).toStringAsFixed(3)]
      else if (start > 0) ...['-ss', start.toStringAsFixed(2)],
      '-i', input,
      '-map', '0:v:0',
      if (track != null) ...['-map', '0:${track.index}'],
      if (copy) ...[
        '-c:v', 'copy',
        // Étiquette attendue par les navigateurs pour le H.265 en MP4.
        if (videoCodec == 'hevc') ...['-tag:v', 'hvc1'],
      ] else ...[
        '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '22',
        '-pix_fmt', 'yuv420p',
        if ((width ?? 0) > 1920) ...['-vf', 'scale=1920:-2'],
      ],
      if (track != null)
        ...(copyAudio ? ['-c:a', 'copy'] : ['-c:a', 'aac', '-ac', '2', '-b:a', '192k']),
      '-sn', '-dn',
      '-f', 'mp4', '-movflags', 'frag_keyframe+empty_moov+default_base_moof',
      'pipe:1',
    ];
  }

  Map<String, Object?> toJson() => {
        'container': container,
        'duration': duration,
        'video': videoCodec,
        'direct': direct,
        'videoMime': videoMime,
        'audio': [for (final a in audio) a.toJson()],
        'preferredAudio': preferredAudio?.index,
        'browserAudio': browserAudio?.index,
      };
}

/// Lance `ffprobe` sur [url].
Future<MediaInfo> probe(String url, {String ffprobe = 'ffprobe'}) async {
  final result = await Process.run(ffprobe, [
    '-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', url,
  ]);
  if (result.exitCode != 0) {
    throw ProcessException(ffprobe, const [], '${result.stderr}'.trim(), result.exitCode);
  }
  return MediaInfo.parse(result.stdout as String);
}

/// Dernière image clé de la vidéo de [url] à [t] secondes ou avant, ou [t]
/// si aucune n'est trouvée dans la minute qui précède. Seuls les paquets sont
/// lus (pas de décodage), sur cette minute : rapide, même à distance.
Future<double> keyframeBefore(String url, double t, {String ffprobe = 'ffprobe'}) async {
  if (t <= 0) return 0;
  final from = t > 60 ? t - 60 : 0;
  final result = await Process.run(ffprobe, [
    '-v', 'error', '-select_streams', 'v:0',
    '-read_intervals', '${from.toStringAsFixed(3)}%${t.toStringAsFixed(3)}',
    '-show_entries', 'packet=pts_time,flags', '-of', 'csv=p=0', url,
  ]);
  if (result.exitCode != 0) return t;
  return parseKeyframeBefore(result.stdout as String, t) ?? t;
}

/// Sortie `pts_time,flags` de ffprobe : la dernière image clé (K) <= [t].
double? parseKeyframeBefore(String csv, double t) {
  double? best;
  for (final line in const LineSplitter().convert(csv)) {
    final parts = line.split(',');
    if (parts.length < 2 || !parts[1].contains('K')) continue;
    final pts = double.tryParse(parts[0]);
    if (pts != null && pts <= t && (best == null || pts > best)) best = pts;
  }
  return best;
}

/// L'outil [command] est-il installé ?
Future<bool> available(String command) async {
  try {
    return (await Process.run(command, ['-version'])).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
