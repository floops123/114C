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
  });

  final String title;
  final int? year;

  /// « Série » si un marqueur SxxEyy est présent, sinon vide.
  final String kind;
  final String? resolution;
  final String? source;
  final String? videoCodec;
  final List<String> languages;

  static final _year = RegExp(r'^(19|20)\d{2}$');
  static final _episode = RegExp(r'^S\d{1,2}(E\d{1,3})*$', caseSensitive: false);
  static final _resolution =
      RegExp(r'^(2160p|1080p|1080i|720p|576p|480p|4K|UHD)$', caseSensitive: false);

  static const _sources = {
    'BLURAY': 'BluRay', 'BDRIP': 'BDRip', 'REMUX': 'Remux', 'WEB-DL': 'WEB-DL',
    'WEBDL': 'WEB-DL', 'WEBRIP': 'WEBRip', 'WEB': 'WEB', 'HDTV': 'HDTV',
    'DVDRIP': 'DVDRip', 'HDRIP': 'HDRip', 'HDLIGHT': 'HDLight',
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
    final tokens = name
        .replaceAll(RegExp(r'-[^-.\s]+$'), '')
        .split(RegExp(r'[.\s_]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final titleWords = <String>[];
    int? year;
    var kind = '';
    String? resolution, source, codec;
    final languages = <String>[];
    var inTitle = true;

    for (final token in tokens) {
      final upper = token.toUpperCase();
      if (_year.hasMatch(token) && titleWords.isNotEmpty && year == null) {
        year = int.parse(token);
        inTitle = false;
      } else if (_episode.hasMatch(token)) {
        kind = 'Série';
        inTitle = false;
      } else if (_resolution.hasMatch(token)) {
        resolution = token.toLowerCase() == '4k' || upper == 'UHD' ? '2160p' : token.toLowerCase();
        inTitle = false;
      } else if (_sources.containsKey(upper)) {
        source ??= _sources[upper];
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
    );
  }
}
