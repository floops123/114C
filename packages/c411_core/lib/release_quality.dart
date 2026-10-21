// Libellés, descriptions et lecture de la qualité d'une sortie, alignés sur
// le site C411 (portés de son bundle JavaScript : tables de langues, de
// sources, de codecs ; grille des créneaux dans c411_slots.dart).

/// Doublages français et leur libellé, dans l'ordre où le site les cherche.
const _frenchDubs = {
  'VF2': 'VF2',
  'VFF': 'VFF',
  'VFQ': 'VFQ',
  'VFI': 'VFI',
  'TRUEFRENCH': 'VFF',
  'VF': 'VF',
  'FRANÇAIS': 'VF',
  'FRENCH': 'VF',
};

/// Langues nommées par le site (code et nom affiché).
const _languageNames = {
  'MULTI': 'Multi', 'TRUEFRENCH': 'TrueFrench', 'VFF': 'VFF', 'VFQ': 'VFQ',
  'VFI': 'VFI', 'VF2': 'VF2', 'FRENCH': 'Français', 'VF': 'VF',
  'VOSTFR': 'VOSTFR', 'SUBFRENCH': 'SubFrench', 'VO': 'VO',
  'ENGLISH': 'Anglais', 'GERMAN': 'Allemand', 'SPANISH': 'Espagnol',
  'ITALIAN': 'Italien', 'JAPANESE': 'Japonais', 'KOREAN': 'Coréen',
  'CHINESE': 'Chinois', 'RUSSIAN': 'Russe', 'PORTUGUESE': 'Portugais',
  'ARABIC': 'Arabe', 'HEBREW': 'Hébreu',
};

/// Autres langues que le français : codes et noms (« ANGLAIS »), VO comprise.
final Set<String> _otherLanguages = {
  for (final MapEntry(:key, :value) in _languageNames.entries)
    if (!{'MULTI', 'VOSTFR', 'SUBFRENCH', ..._frenchDubs.keys}.contains(key))
      ...[key, value.toUpperCase()],
};

/// Langues d'une sortie résumées comme sur C411 : « MULTI.VF2 », « VFF »,
/// « MULTI.VOSTFR »… À partir de la liste brute (`MULTI`, `VFF`, `VFQ`,
/// `ANGLAIS`…). Vide si la liste l'est.
String languageLabel(List<String> languages) {
  if (languages.isEmpty) return '';
  final t = [for (final l in languages) l.toUpperCase()];
  // VFF (ou VOF) + VFQ : doublages France et Québec.
  final france = t.contains('VFF') || t.contains('VOF');
  final vf2 = t.contains('VF2') || (france && t.contains('VFQ'));
  final subtitled = t.contains('VOSTFR') || t.contains('SUBFRENCH');
  final dubbed = vf2 || t.any(const {'VF2', 'VFF', 'VFQ', 'VFI'}.contains);
  if (subtitled && !dubbed) {
    return t.contains('MULTI') ? 'MULTI.VOSTFR' : 'VOSTFR';
  }
  final dub = vf2
      ? 'VF2'
      : _frenchDubs.entries
          .where((e) => t.contains(e.key))
          .map((e) => e.value)
          .firstOrNull;
  if (t.contains('MULTI') || (dub != null && t.any(_otherLanguages.contains))) {
    return dub != null ? 'MULTI.$dub' : 'MULTI';
  }
  if (dub != null) return dub;
  final rest = [
    for (final l in languages)
      if (!const {'MULTI', 'VO'}.contains(l.toUpperCase())) l,
  ].take(2);
  return rest.isNotEmpty ? rest.join('.') : languages.first;
}

/// Ce que veut dire un libellé de [languageLabel].
String languageDescription(String label) => switch (label) {
      _ when label.startsWith('MULTI.VF2') =>
        'Multi-langues avec VFF + VFQ (doublage France et Québec)',
      _ when label.startsWith('MULTI.VFF') =>
        'Multi-langues avec doublage français (France)',
      _ when label.startsWith('MULTI.VFQ') =>
        'Multi-langues avec doublage français (Québec)',
      _ when label.startsWith('MULTI.VFI') =>
        'Multi-langues avec doublage français international',
      _ when label.startsWith('MULTI.VOSTFR') =>
        'Multi-langues, sous-titres français',
      _ when label.startsWith('MULTI.VF') =>
        'Multi-langues avec version française',
      'MULTI' => 'Multi-langues (VO + français)',
      'VF2' => 'VFF + VFQ (doublage France et Québec)',
      'VFF' => 'Version Française (doublage France)',
      'VFQ' => 'Version Française (doublage Québec)',
      'VFI' => 'Version Française Internationale',
      'VOSTFR' => 'Version Originale Sous-Titrée Français',
      'TRUEFRENCH' => 'Doublage français intégral',
      _ => 'Langue : $label',
    };

String resolutionDescription(String resolution) => switch (resolution) {
      '2160p' => 'Résolution 4K Ultra HD (3840×2160)',
      '1080p' => 'Résolution Full HD (1920×1080)',
      '720p' => 'Résolution HD (1280×720)',
      '576p' => 'Résolution SD PAL (720×576)',
      '480p' => 'Résolution SD NTSC (720×480)',
      _ => 'Résolution : $resolution',
    };

String sourceDescription(String source) {
  final s = source.toLowerCase();
  if (s.contains('remux')) {
    return 'Remux : copie directe du Blu-ray sans ré-encodage';
  }
  if (s.contains('bdmv')) return 'BDMV : structure complète du disque Blu-ray';
  return switch (s) {
    'bluray' || 'blu-ray' => 'Encodé depuis un disque Blu-ray',
    'web-dl' => 'WEB-DL : téléchargé depuis un service de streaming sans perte',
    'webrip' => 'WEBRip : capturé depuis un service de streaming',
    'dvdrip' => 'DVDRip : encodé depuis un DVD',
    'hdtv' => 'HDTV : capturé depuis une diffusion TV HD',
    // Hors bundle : sources propres aux trackers français.
    '4klight' => '4KLight : 4K réencodée allégée',
    'hdlight' => 'HDLight : HD réencodée allégée',
    _ => 'Source : $source',
  };
}

String videoCodecDescription(String codec) {
  final c = codec.toLowerCase();
  if (c.contains('h.265') || c.contains('hevc') || c.contains('x265')) {
    return 'Codec H.265 (HEVC) : compression efficace, qualité élevée';
  }
  if (c.contains('h.264') || c.contains('avc') || c.contains('x264')) {
    return 'Codec H.264 (AVC) : compatibilité maximale';
  }
  if (c.contains('av1')) return 'Codec AV1 : compression nouvelle génération';
  return 'Codec vidéo : $codec';
}

String hdrDescription(String format) => switch (format) {
      'DV.HDR10+' => 'Dolby Vision + HDR10+ : double format HDR dynamique',
      'DV.HDR10' => 'Dolby Vision + HDR10 : HDR dynamique avec fallback statique',
      'HDR10+' => 'HDR10+ : HDR dynamique (Samsung)',
      'HDR10' => 'HDR10 : HDR statique standard',
      'DV' => 'Dolby Vision : HDR dynamique (Dolby)',
      'SDR' => 'SDR : pas de HDR',
      _ => 'Format HDR : $format',
    };

String audioDescription(String codec, [String? channels]) {
  final a = codec.toLowerCase();
  final text = a.contains('truehd')
      ? 'Dolby TrueHD : audio lossless haute fidélité'
      : a.contains('dts-hd ma') || a.contains('dts-hd.ma')
          ? 'DTS-HD Master Audio : audio lossless'
          : a.contains('dts-x') || a.contains('dts:x')
              ? 'DTS:X : audio lossless immersif'
              : a.contains('flac')
                  ? 'FLAC : audio lossless'
                  : a.contains('eac3') || a.contains('dd+') || a.contains('e-ac-3')
                      ? 'Dolby Digital Plus (EAC3) : audio lossy de qualité'
                      : a.contains('ac3') || a.contains('dd')
                          ? 'Dolby Digital (AC3) : audio lossy standard'
                          : a.contains('dts')
                              ? 'DTS : audio lossy multicanal'
                              : a.contains('aac')
                                  ? 'AAC : audio lossy compact'
                                  : a.contains('opus')
                                      ? 'Opus : audio lossy efficace'
                                      : 'Audio : $codec';
  return channels != null && channels != '2.0'
      ? '$text - $channels canaux'
      : text;
}

/// Équipe de la release : ce qui suit le dernier tiret, extension exclue.
String? releaseGroup(String name) =>
    RegExp(r'-([A-Za-z0-9_]+)(?:\.[a-z]{2,4})?$').firstMatch(name)?[1];

/// Sortie de bonus (making-of, scènes coupées…), pas le film lui-même.
bool isBonus(String name) =>
    RegExp(r'\bBONUS\b', caseSensitive: false).hasMatch(name);

// ---------------------------------------------------------------------------
// Lecture d'un nom de release, dans le vocabulaire de la grille C411.

/// Nom passé en minuscules, séparateurs `.` et `_` remplacés par des espaces.
String _spaced(String name) => name.toLowerCase().replaceAll(RegExp(r'[._]'), ' ');

bool _has(String spaced, String pattern) =>
    RegExp('(?<![a-z0-9])(?:$pattern)(?![a-z0-9])').hasMatch(spaced);

/// Source normalisée comme sur C411 (Remux, BDMV, ISO, 4KLight, HDLight,
/// BluRay, WEB-DL, WEBRip, HDTV, DVDRip, DVD, SDTV), d'après un nom de
/// release ou une valeur de tracker ; null si rien n'est reconnu. Les
/// sources précises passent avant les génériques (« BluRay.4KLight » :
/// 4KLight ; « BluRay.REMUX » : Remux).
String? normalizeSource(String text) {
  final n = _spaced(text);
  if (_has(n, 'remux')) return 'Remux';
  if (_has(n, r'bdmv|full blu-?ray')) return 'BDMV';
  if (_has(n, 'iso')) return 'ISO';
  if (_has(n, '4k-?light')) return '4KLight';
  if (_has(n, 'hd-?light')) return 'HDLight';
  if (_has(n, r'web-?rip')) return 'WEBRip';
  if (_has(n, r'web-?dl|web')) return 'WEB-DL';
  if (_has(n, r'blu-?ray|bdrip|brrip|hd-?rip|uhd')) return 'BluRay';
  if (_has(n, r'hdtv|tv-?rip|tv rip')) return 'HDTV';
  if (_has(n, r'dvd-?rip')) return 'DVDRip';
  if (_has(n, r'dvd[59]?|dvd-r')) return 'DVD';
  if (_has(n, 'sdtv|pdtv')) return 'SDTV';
  return null;
}

/// Format HDR comme sur C411 (DV.HDR10+, DV.HDR10, HDR10+, HDR10, DV, SDR),
/// d'après un nom de release ; SDR si rien n'est indiqué.
String hdrOfName(String name) {
  final n = _spaced(name);
  final dv = _has(n, r'dv|dovi|dolby ?vision');
  final plus = _has(n, r'hdr10\+|hdr10plus') || n.contains('hdr10+');
  final hdr10 = plus || _has(n, r'hdr10|hdr');
  if (dv && plus) return 'DV.HDR10+';
  if (dv && hdr10) return 'DV.HDR10';
  if (plus) return 'HDR10+';
  if (hdr10) return 'HDR10';
  if (dv) return 'DV';
  return 'SDR';
}

/// Format HDR d'un tracker ramené au vocabulaire de la grille.
String? normalizeHdr(String? format) {
  final f = format?.trim().toUpperCase();
  if (f == null || f.isEmpty) return null;
  return hdrOfName(f);
}

/// Canaux audio (8, 6, 2, 1) : « 7.1 », « 5.1 », « 2.0 », « stereo »,
/// « mono », « 6 canaux »… ; null si rien n'est indiqué.
int? channelsOf(String text) {
  const audio = r'(?:\b|(?<=\b(?:ddp|dd|eac3|ac3|aac|dts|truehd|flac|opus|pcm|lpcm)))';
  final n = text.replaceAll(RegExp(r'[._]'), ' ');
  bool match(String p) =>
      RegExp('$audio($p)\\b', caseSensitive: false).hasMatch(n);
  if (match(r'7[.\s]1|8\s*(?:canaux|channels?)')) return 8;
  if (match(r'5[.\s]1|6\s*(?:canaux|channels?)')) return 6;
  if (match(r'2[.\s]0|stereo|2\s*(?:canaux|channels?)')) return 2;
  if (match(r'1[.\s]0|mono|1\s*(?:canal|channel)')) return 1;
  return null;
}

/// Codec vidéo dans le vocabulaire de la grille (H.264, H.265, AV1, VC-1,
/// XviD, MPEG-2, VP9).
String? normalizeCodec(String text) {
  final n = _spaced(text);
  if (_has(n, 'av1')) return 'AV1';
  if (_has(n, r'x265|h ?265|h\.265|hevc')) return 'H.265';
  if (_has(n, r'x264|h ?264|h\.264|avc')) return 'H.264';
  if (_has(n, r'vc-?1')) return 'VC-1';
  if (_has(n, r'xvid|divx')) return 'XviD';
  if (_has(n, r'mpeg-?2')) return 'MPEG-2';
  if (_has(n, 'vp9')) return 'VP9';
  return null;
}

/// Éditions signalées dans le nom (IMAX, EXTENDED, REPACK…).
const releaseEditions = [
  'CUSTOM', 'UNCENSORED', 'IMAX', 'UNRATED', 'EXTENDED', 'REMASTERED',
  'HYBRID', 'REPACK', 'PROPER',
];

/// Plateformes de streaming reconnues par C411 (NF, AMZN, DSNP…).
const streamingPlatforms = {
  'NETFLIX', 'NF', 'AMAZON', 'AMZN', 'DSNP', 'DNSP', 'DISNEY', 'DISNEYPLUS',
  'DISNEY+', 'HULU', 'ATVP', 'APTV', 'APPLETVPLUS', 'APPLETV+', 'APPLE', 'HBO',
  'HMAX', 'HBOMAX', 'PCOK', 'PEACOCK', 'PMTP', 'PMNP', 'PARAMOUNT',
  'PARAMOUNT+', 'CRAV', 'CRAVE', 'STAN', 'BCORE', 'BRAVIA', 'CRITERION', 'CC',
  'MUBI', 'CANAL', 'CANAL+', 'CANALPLUS', 'SALTO', 'OCS', 'ADN', 'CRUNCHYROLL',
  'CR', 'FUNIMATION', 'FUNI', 'ROKU', 'TUBI', 'PLUTO', 'STARZ', 'SHO',
  'SHOWTIME',
};

/// Année d'un nom de release, choisie comme sur C411 : parmi les années
/// plausibles, celle suivie d'un marqueur technique (1080p, MULTI, BluRay…)
/// l'emporte, puis la plus à droite. « Blade.Runner.2049.2017.1080p » :
/// 2017. Renvoie l'année et sa position dans le nom.
({int year, int index})? yearOf(String name) {
  final n = name.replaceAll(RegExp(r'[._]'), ' ');
  final found = <({int year, int index, int score})>[];
  for (final m in RegExp(r'\b((?:19|20)\d{2})\b').allMatches(n)) {
    final year = int.parse(m[1]!);
    final at = m.start;
    final after = n.substring(at + 4, (at + 20).clamp(0, n.length));
    if (RegExp(r'^[pi]\b|^kb|^mb|^x\d', caseSensitive: false).hasMatch(after)) {
      continue;
    }
    // « 24 12 2019 » : une date, pas une année de sortie.
    final before = n.substring((at - 8).clamp(0, n.length), at);
    final words = before.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final date = before.endsWith(' ') &&
        words.length >= 2 &&
        RegExp(r'^\d{1,2}$').hasMatch(words[words.length - 1]) &&
        RegExp(r'^\d{1,2}$').hasMatch(words[words.length - 2]);
    if (date) continue;
    final score = RegExp(
            r'^\s*(1080p|720p|480p|2160p|4k|uhd|french|multi|vff|vfq|vf\b|blu|web|dvd|hd|remux|complete|integrale)',
            caseSensitive: false)
        .hasMatch(after)
        ? 10
        : RegExp(r'^\s+[A-Z]').hasMatch(after)
            ? 5
            : RegExp(r'^\s+[a-z]').hasMatch(after)
                ? 1
                : 3;
    found.add((year: year, index: at, score: score));
  }
  if (found.isEmpty) return null;
  found.sort((a, b) =>
      a.score == b.score ? b.index - a.index : b.score - a.score);
  return (year: found.first.year, index: found.first.index);
}

