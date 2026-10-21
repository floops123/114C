import 'release_quality.dart';

/// Extraction d'informations depuis un nom de release
/// (`Titre.Du.Film.2024.MULTi.1080p.WEB.H265-GROUPE`), pour les trackers qui
/// ne fournissent pas de métadonnées (Torznab).
class ReleaseName {
  const ReleaseName({
    required this.title,
    this.year,
    this.kind = '',
    this.resolution,
    this.source,
    this.videoCodec,
    this.languages = const [],
    this.editions = const [],
    this.platform,
  });

  final String title;
  final int? year;

  /// « Série » si un marqueur SxxEyy est présent, sinon vide.
  final String kind;
  final String? resolution;
  final String? source;
  final String? videoCodec;
  final List<String> languages;

  /// Éditions signalées (IMAX, EXTENDED, REPACK…), voir [releaseEditions].
  final List<String> editions;

  /// Plateforme de streaming (NF, AMZN…), voir [streamingPlatforms].
  final String? platform;

  static final _episode = RegExp(r'^S\d{1,2}(E\d{1,3})*$', caseSensitive: false);
  static final _resolution =
      RegExp(r'^(2160p|1080p|1080i|720p|576p|480p|4K|UHD)$', caseSensitive: false);

  /// Jetons de source : marquent la fin du titre.
  static const _sources = {
    'BLURAY', 'BLU-RAY', 'BDRIP', 'BRRIP', 'REMUX', 'BDMV', 'WEB-DL', 'WEBDL',
    'WEBRIP', 'WEB-RIP', 'WEB', 'HDTV', 'TVRIP', 'DVDRIP', 'DVD', 'HDRIP',
    'HDLIGHT', '4KLIGHT', 'SDTV', 'PDTV',
  };
  static const _codecs = {
    'X264': 'H.264', 'H264': 'H.264', 'AVC': 'H.264', 'X265': 'H.265',
    'H265': 'H.265', 'HEVC': 'H.265', 'AV1': 'AV1',
  };
  static const _languages = {
    'MULTI', 'VFF', 'VFQ', 'VF2', 'VFI', 'VF', 'VOF', 'TRUEFRENCH', 'FRENCH',
    'VOSTFR', 'SUBFRENCH', 'VO',
  };

  static ReleaseName parse(String name) {
    // Le groupe est après le dernier tiret ; les séparateurs sont . _ ou espace.
    final bare = name.replaceAll(RegExp(r'-[^-.\s]+$'), '');
    final tokens =
        bare.split(RegExp(r'[.\s_]+')).where((t) => t.isNotEmpty).toList();

    // Année choisie comme sur C411 (« Blade.Runner.2049.2017 » : 2017) : on
    // repère laquelle de ses occurrences dans les jetons.
    final chosen = yearOf(bare);
    var yearTurn = -1;
    if (chosen != null) {
      final spaced = bare.replaceAll(RegExp(r'[._]'), ' ');
      yearTurn = RegExp('\\b${chosen.year}\\b')
          .allMatches(spaced)
          .takeWhile((m) => m.start < chosen.index)
          .length;
    }
    var yearSeen = 0;
    final editions = <String>[];
    String? platform;

    final titleWords = <String>[];
    int? year;
    var kind = '';
    String? resolution, source, codec;
    final languages = <String>[];
    var inTitle = true;

    for (final token in tokens) {
      final upper = token.toUpperCase();
      final isChosenYear = chosen != null &&
          token == '${chosen.year}' &&
          yearSeen++ == yearTurn;
      if (isChosenYear) {
        year = chosen.year;
        inTitle = false;
      } else if (!inTitle && releaseEditions.contains(upper)) {
        if (!editions.contains(upper)) editions.add(upper);
      } else if (!inTitle && streamingPlatforms.contains(upper)) {
        platform ??= upper;
      } else if (_episode.hasMatch(token)) {
        kind = 'Série';
        inTitle = false;
      } else if (_resolution.hasMatch(token)) {
        resolution = token.toLowerCase() == '4k' || upper == 'UHD' ? '2160p' : token.toLowerCase();
        inTitle = false;
      } else if (_sources.contains(upper)) {
        // Valeur prise sur le nom entier, comme sur C411 (« BluRay.REMUX » :
        // Remux, « WEB » : WEB-DL).
        source ??= normalizeSource(name);
        inTitle = false;
      } else if (_codecs.containsKey(upper)) {
        codec ??= _codecs[upper];
        inTitle = false;
      } else if (_languages.contains(upper)) {
        if (!languages.contains(upper)) languages.add(upper);
        inTitle = false;
      } else if (inTitle) {
        titleWords.add(token);
      }
    }

    return ReleaseName(
      title: titleWords.isEmpty ? name : titleWords.join(' '),
      year: year,
      kind: kind,
      resolution: resolution,
      source: source,
      videoCodec: codec,
      languages: languages,
      editions: editions,
      platform: platform,
    );
  }
}
