// Libellés et descriptions de la qualité d'une sortie, alignés sur ceux du
// site C411 (portés de son bundle JavaScript). Le bundle s'appuie sur des
// tables qu'il importe (variantes françaises, autres langues) : elles sont
// reconstituées ici d'après les codes que l'API renvoie dans `tech.languages`.

/// Doublages français, dans l'ordre où le site les cherche.
const _frenchDubs = {
  'VFF': 'VFF',
  'TRUEFRENCH': 'VFF',
  'VFQ': 'VFQ',
  'VFI': 'VFI',
  'VF': 'VF',
  'FRENCH': 'VF',
};

/// Codes qui ne sont ni un doublage français ni une autre langue (« VO »
/// en est une : VFF + VO donne « MULTI.VFF », comme sur le site).
const _notOther = {'MULTI', 'VOSTFR', 'SUBFRENCH', 'VF2', 'VOF', ..._frenchKeys};
const _frenchKeys = {'VFF', 'TRUEFRENCH', 'VFQ', 'VFI', 'VF', 'FRENCH'};

/// Langues d'une sortie résumées comme sur C411 : « MULTI.VF2 », « VFF »,
/// « MULTI.VOSTFR »… À partir de la liste brute (`MULTI`, `VFF`, `VFQ`,
/// `ANGLAIS`…). Vide si la liste l'est.
String languageLabel(List<String> languages) {
  if (languages.isEmpty) return '';
  final t = [for (final l in languages) l.toUpperCase()];
  final france = t.contains('VFF') || t.contains('TRUEFRENCH');
  final vf2 = t.contains('VF2') || (france && t.contains('VFQ'));
  final subtitled = t.contains('VOSTFR') || t.contains('SUBFRENCH');
  final dubbed =
      vf2 || t.any(const {'VF2', 'VFF', 'VFQ', 'VFI'}.contains);
  if (subtitled && !dubbed) {
    return t.contains('MULTI') ? 'MULTI.VOSTFR' : 'VOSTFR';
  }
  final dub = vf2
      ? 'VF2'
      : _frenchDubs.entries
          .where((e) => t.contains(e.key))
          .map((e) => e.value)
          .firstOrNull;
  final other = t.any((l) => !_notOther.contains(l));
  if (t.contains('MULTI') || (dub != null && other)) {
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
