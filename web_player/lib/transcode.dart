import 'dart:convert';
import 'dart:io';

/// Une piste audio d'un fichier.
class AudioTrack {
  const AudioTrack(this.index, this.codec, this.language, this.channels, this.title);

  /// Index du flux dans le fichier (pour `-map 0:<index>`).
  final int index;
  final String codec;
  final String? language;
  final int channels;
  final String? title;

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
    this.audio = const [],
  });

  final String container;
  final double duration;
  final String? videoCodec;
  final String? pixelFormat;
  final int? width;
  final List<AudioTrack> audio;

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
      audio: [
        for (final s in streams)
          if (s['codec_type'] == 'audio')
            AudioTrack(
              (s['index'] as num).toInt(),
              s['codec_name'] as String? ?? '',
              (s['tags'] as Map?)?['language'] as String?,
              (s['channels'] as num?)?.toInt() ?? 2,
              (s['tags'] as Map?)?['title'] as String?,
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

  /// Arguments ffmpeg pour servir le fichier en MP4 fragmenté lisible
  /// partout, à partir de [start] secondes : vidéo copiée si elle est déjà
  /// en H.264 8 bits (rapide), sinon réencodée en H.264 (1080p au plus) ;
  /// audio en AAC stéréo, piste [audioIndex] (par défaut, la française).
  List<String> ffmpegArgs(String input, {double start = 0, int? audioIndex}) {
    final track = audio.where((a) => a.index == audioIndex).firstOrNull ?? preferredAudio;
    final copyAudio = track != null && track.codec == 'aac' && track.channels <= 2;
    return [
      '-hide_banner', '-loglevel', 'error', '-nostdin',
      if (start > 0) ...['-ss', start.toStringAsFixed(2)],
      '-i', input,
      '-map', '0:v:0',
      if (track != null) ...['-map', '0:${track.index}'],
      if (_h264)
        ...['-c:v', 'copy']
      else ...[
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
        'audio': [for (final a in audio) a.toJson()],
        'preferredAudio': preferredAudio?.index,
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

/// L'outil [command] est-il installé ?
Future<bool> available(String command) async {
  try {
    return (await Process.run(command, ['-version'])).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
