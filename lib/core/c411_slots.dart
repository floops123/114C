import 'release_profile.dart';

/// Un créneau (« slot ») de la grille de qualité de C411 : un profil, des
/// critères, et pour chaque critère les valeurs acceptées en repli, de la
/// plus proche à la plus éloignée. Repris tel quel du site.
class C411Slot {
  const C411Slot(
    this.id,
    this.profile,
    this.label, {
    required this.resolution,
    required this.source,
    required this.hdr,
    required this.lossless,
    required this.videoCodec,
    this.channelsMin = 1,
    this.channelsMax,
    this.fallbacks = const {},
  });

  final String id;
  final C411Profile profile;
  final String label;
  final String resolution;
  final String source;
  final String hdr;

  /// Audio attendu : sans perte (`lossless`) ou non (`lossy`).
  final bool lossless;
  final String videoCodec;

  /// Canaux audio (7.1 = 8, 5.1 = 6).
  final int channelsMin;
  final int? channelsMax;

  /// Replis par critère : `resolution`, `source`, `hdr`, `videoCodec`,
  /// `audioType` (`lossless` / `lossy`).
  final Map<String, List<String>> fallbacks;

  /// Résumé du créneau comme sur le site : « 2160p 4KLight H.265 DV.HDR10+ ».
  String get summary =>
      [resolution, source, videoCodec, if (hdr != 'SDR') hdr].join(' ');
}

/// Ce qu'on sait d'une sortie, dans le vocabulaire de la grille ; null =
/// inconnu.
typedef SlotTraits = ({
  String? resolution,
  String? source,
  String? hdr,
  bool? lossless,
  int? channels,
  String? videoCodec,
});

/// Créneau retenu et son écart aux critères (0 : tous respectés à la
/// lettre).
typedef SlotMatch = ({C411Slot slot, double distance});

/// Le créneau de la grille le plus proche de [t], ou null si aucun ne
/// l'accepte ou si on en sait trop peu : il faut la résolution, et le codec
/// sauf pour une source brute (Remux, BDMV, ISO) où il ne départage pas.
/// Sans codec, la grille pencherait toujours vers Compat, premier critère
/// SDR de la liste. Un critère respecté coûte 0, un repli sa position dans la
/// liste des replis (1 pour le premier…), un critère inconnu 0,5. Les
/// canaux doivent tenir dans les bornes du créneau. À écart égal, le premier
/// dans l'ordre du site l'emporte (C411 laisse l'uploader choisir parmi les
/// créneaux qui conviennent : ce n'est qu'une estimation).
SlotMatch? matchSlot(SlotTraits t) {
  final raw = const {'Remux', 'BDMV', 'ISO'}.contains(t.source);
  if (t.resolution == null || (t.videoCodec == null && !raw)) return null;
  SlotMatch? best;
  for (final slot in c411Slots) {
    final d = _distance(slot, t);
    if (d != null && (best == null || d < best.distance)) {
      best = (slot: slot, distance: d);
    }
  }
  return best;
}

double? _distance(C411Slot s, SlotTraits t) {
  double? cost(String key, String expected, String? actual) {
    if (actual == null) return 0.5;
    if (actual.toLowerCase() == expected.toLowerCase()) return 0;
    final i = (s.fallbacks[key] ?? const [])
        .indexWhere((f) => f.toLowerCase() == actual.toLowerCase());
    return i < 0 ? null : i + 1.0;
  }

  final channels = t.channels;
  if (channels != null &&
      (channels < s.channelsMin ||
          (s.channelsMax != null && channels > s.channelsMax!))) {
    return null;
  }
  final parts = [
    cost('resolution', s.resolution, t.resolution),
    cost('source', s.source, t.source),
    cost('hdr', s.hdr, t.hdr),
    cost('videoCodec', s.videoCodec, t.videoCodec),
    cost('audioType', s.lossless ? 'lossless' : 'lossy',
        t.lossless == null ? null : (t.lossless! ? 'lossless' : 'lossy')),
  ];
  if (parts.contains(null)) return null;
  return parts.fold<double>(0, (a, b) => a + b!);
}

const _lowRes = ['720p', '576p', '480p', 'SD'];
const _hdrAll = ['DV.HDR10', 'DV', 'HDR10+', 'HDR10', 'SDR'];
const _hdrDynamic = ['DV.HDR10', 'DV', 'HDR10+', 'HDR10'];
const _hdrOpti = ['DV.HDR10+', 'DV.HDR10', 'DV', 'HDR10+', 'SDR'];
const _lossy = ['lossy'];

/// La grille de C411, dans l'ordre du site.
const c411Slots = <C411Slot>[
  // Compatibilité
  C411Slot('COMPAT-01', C411Profile.compatibility,
      '1080p H.264 Lossy (Direct Play, BDRip)',
      resolution: '1080p', source: 'BluRay', hdr: 'SDR', lossless: false,
      videoCodec: 'H.264',
      fallbacks: {
        'resolution': _lowRes,
        'source': ['HDLight', 'WEB-DL', 'HDTV', 'DVDRip'],
        'videoCodec': ['XviD', 'MPEG-2'],
        'audioType': ['lossless'],
      }),
  C411Slot('COMPAT-WR', C411Profile.compatibility,
      '1080p Bluray.HDLight/WEBRip H.264 Lossy (Direct Play)',
      resolution: '1080p', source: 'HDLight', hdr: 'SDR', lossless: false,
      videoCodec: 'H.264',
      fallbacks: {
        'resolution': _lowRes,
        'source': ['WEBRip', 'WEB-DL'],
        'videoCodec': ['XviD', 'MPEG-2'],
        'audioType': ['lossless'],
      }),
  // Home Cinéma Pure
  C411Slot('PURE-UHD-REMUX', C411Profile.hcPure,
      '2160p UHD Remux Lossless (lossy accepté)',
      resolution: '2160p', source: 'Remux', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'H.265',
      fallbacks: {'hdr': _hdrAll, 'audioType': _lossy}),
  C411Slot('PURE-UHD-BDMV', C411Profile.hcPure,
      '2160p UHD BDMV Lossless (lossy accepté)',
      resolution: '2160p', source: 'BDMV', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'H.265',
      fallbacks: {'hdr': _hdrAll, 'audioType': _lossy}),
  C411Slot('PURE-BD-REMUX', C411Profile.hcPure,
      '1080p Remux Lossless (lossy accepté)',
      resolution: '1080p', source: 'Remux', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'H.265',
      fallbacks: {
        'resolution': _lowRes,
        'source': ['DVD'],
        'hdr': _hdrAll,
        'videoCodec': ['H.264', 'MPEG-2', 'VC-1', 'XviD'],
        'audioType': _lossy,
      }),
  C411Slot('PURE-BD-BDMV', C411Profile.hcPure,
      '1080p BDMV Lossless (lossy accepté)',
      resolution: '1080p', source: 'BDMV', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'H.265',
      fallbacks: {
        'source': ['DVD'],
        'hdr': _hdrAll,
        'videoCodec': ['H.264', 'VC-1'],
        'audioType': _lossy,
      }),
  C411Slot('PURE-BD-VC1', C411Profile.hcPure,
      '1080p VC-1 Remux Lossless (lossy accepté, BD native VC-1 stream)',
      resolution: '1080p', source: 'Remux', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'VC-1',
      fallbacks: {
        'resolution': _lowRes,
        'source': ['BDMV', 'ISO', 'DVD'],
        'hdr': _hdrAll,
        'audioType': _lossy,
      }),
  C411Slot('PURE-BD-ISO', C411Profile.hcPure,
      '1080p Bluray.ISO Lossless (lossy accepté)',
      resolution: '1080p', source: 'ISO', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'H.265',
      fallbacks: {
        'source': ['DVD'],
        'hdr': _hdrAll,
        'videoCodec': ['H.264', 'VC-1'],
        'audioType': _lossy,
      }),
  C411Slot('PURE-UHD-ISO', C411Profile.hcPure,
      '2160p UHD Bluray.ISO Lossless (lossy accepté)',
      resolution: '2160p', source: 'ISO', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'H.265',
      fallbacks: {'hdr': _hdrAll, 'audioType': _lossy}),
  // Home Cinéma Optimisé
  C411Slot('HCOPT-1080-BD-H265', C411Profile.hcOptimized,
      '1080p BluRay H.265 Lossless (lossy accepté, Full BluRay encode)',
      resolution: '1080p', source: 'BluRay', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'H.265',
      fallbacks: {
        'resolution': _lowRes,
        'source': ['HDLight', 'WEB-DL', 'DVDRip'],
        'hdr': _hdrAll,
        'audioType': _lossy,
      }),
  C411Slot('HCOPT-1080-BD-AV1', C411Profile.hcOptimized,
      '1080p BluRay AV1 Lossless (lossy accepté)',
      resolution: '1080p', source: 'BluRay', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'AV1',
      fallbacks: {
        'resolution': _lowRes,
        'source': ['HDLight', 'WEB-DL', 'DVDRip'],
        'hdr': _hdrAll,
        'audioType': _lossy,
      }),
  C411Slot('HCOPT-1080-WR-H265', C411Profile.hcOptimized,
      '1080p Bluray.HDLight/WEBRip H.265 Lossy',
      resolution: '1080p', source: 'HDLight', hdr: 'SDR', lossless: false,
      videoCodec: 'H.265',
      fallbacks: {'resolution': _lowRes, 'source': ['WEBRip', 'WEB-DL']}),
  C411Slot('HCOPT-1080-WR-AV1', C411Profile.hcOptimized,
      '1080p Bluray.HDLight/WEBRip AV1 Lossy',
      resolution: '1080p', source: 'HDLight', hdr: 'SDR', lossless: false,
      videoCodec: 'AV1',
      fallbacks: {'resolution': _lowRes, 'source': ['WEBRip', 'WEB-DL']}),
  C411Slot('HCOPT-2160-BD-H265', C411Profile.hcOptimized,
      '2160p BluRay H.265 Encode Qualité Lossless (lossy accepté)',
      resolution: '2160p', source: 'BluRay', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'H.265',
      fallbacks: {
        'source': ['HDLight', 'WEB-DL'],
        'hdr': _hdrAll,
        'audioType': _lossy,
      }),
  C411Slot('HCOPT-2160-BD-AV1', C411Profile.hcOptimized,
      '2160p BluRay AV1 Lossless (lossy accepté)',
      resolution: '2160p', source: 'BluRay', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'AV1',
      fallbacks: {
        'source': ['HDLight', 'WEB-DL'],
        'hdr': _hdrAll,
        'audioType': _lossy,
      }),
  C411Slot('HCOPT-2160-4KL-H265', C411Profile.hcOptimized,
      '2160p Bluray.4KLight H.265 Lossless (lossy accepté)',
      resolution: '2160p', source: '4KLight', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'H.265',
      fallbacks: {'hdr': _hdrAll, 'audioType': _lossy}),
  C411Slot('HCOPT-2160-4KL-AV1', C411Profile.hcOptimized,
      '2160p Bluray.4KLight AV1 Lossless (lossy accepté)',
      resolution: '2160p', source: '4KLight', hdr: 'DV.HDR10+', lossless: true,
      videoCodec: 'AV1',
      fallbacks: {'hdr': _hdrAll, 'audioType': _lossy}),
  C411Slot('HCOPT-2160-WR-H265-HDR', C411Profile.hcOptimized,
      '2160p Bluray.HDLight/WEBRip H.265 HDR Lossy',
      resolution: '2160p', source: 'HDLight', hdr: 'DV.HDR10+', lossless: false,
      videoCodec: 'H.265',
      fallbacks: {'source': ['WEBRip', 'WEB-DL'], 'hdr': _hdrDynamic}),
  C411Slot('HCOPT-2160-WR-AV1-HDR', C411Profile.hcOptimized,
      '2160p Bluray.HDLight/WEBRip AV1 HDR Lossy',
      resolution: '2160p', source: 'HDLight', hdr: 'DV.HDR10+', lossless: false,
      videoCodec: 'AV1',
      fallbacks: {'source': ['WEBRip', 'WEB-DL'], 'hdr': _hdrDynamic}),
  C411Slot('HCOPT-2160-WR-H265', C411Profile.hcOptimized,
      '2160p Bluray.HDLight/WEBRip H.265 Lossy',
      resolution: '2160p', source: 'HDLight', hdr: 'SDR', lossless: false,
      videoCodec: 'H.265',
      fallbacks: {'source': ['WEBRip', 'WEB-DL']}),
  C411Slot('HCOPT-2160-WR-AV1', C411Profile.hcOptimized,
      '2160p Bluray.HDLight/WEBRip AV1 Lossy',
      resolution: '2160p', source: 'HDLight', hdr: 'SDR', lossless: false,
      videoCodec: 'AV1',
      fallbacks: {'source': ['WEBRip', 'WEB-DL']}),
  // Optimisation
  C411Slot('OPTI-1080-HDR', C411Profile.optimization,
      '1080p BluRay HDR10 H.265 Lossy (x265 Bluray.HDLight HDR)',
      resolution: '1080p', source: 'BluRay', hdr: 'HDR10', lossless: false,
      videoCodec: 'H.265', channelsMin: 2, channelsMax: 6,
      fallbacks: {
        'resolution': _lowRes,
        'source': ['HDLight', 'WEB-DL', 'DVDRip', 'HDTV'],
        'hdr': _hdrOpti,
        'videoCodec': ['H.264'],
      }),
  C411Slot('OPTI-1080-SDR-BD', C411Profile.optimization,
      '1080p BluRay SDR H.265 Lossy (x265 Bluray.HDLight)',
      resolution: '1080p', source: 'BluRay', hdr: 'SDR', lossless: false,
      videoCodec: 'H.265', channelsMin: 2, channelsMax: 6,
      fallbacks: {
        'resolution': _lowRes,
        'source': ['HDLight', 'WEB-DL', 'DVDRip', 'HDTV'],
        'videoCodec': ['H.264'],
      }),
  C411Slot('OPTI-1080-SDR-WR', C411Profile.optimization,
      '1080p Bluray.HDLight/WEBRip SDR H.265 Lossy',
      resolution: '1080p', source: 'HDLight', hdr: 'SDR', lossless: false,
      videoCodec: 'H.265', channelsMin: 2, channelsMax: 6,
      fallbacks: {
        'resolution': _lowRes,
        'source': ['WEBRip', 'WEB-DL'],
        'videoCodec': ['H.264'],
      }),
  C411Slot('OPTI-2160-HDR', C411Profile.optimization,
      '2160p BluRay HDR10 H.265 Encode Qualité Lossy (x265 Bluray.HDLight 4K HDR)',
      resolution: '2160p', source: 'BluRay', hdr: 'HDR10', lossless: false,
      videoCodec: 'H.265', channelsMin: 2, channelsMax: 6,
      fallbacks: {
        'source': ['HDLight', 'WEB-DL', 'DVDRip', 'HDTV'],
        'hdr': _hdrOpti,
        'videoCodec': ['H.264'],
      }),
  C411Slot('OPTI-2160-HDR-4KL', C411Profile.optimization,
      '2160p Bluray.4KLight HDR10 H.265 Lossy (Bluray.4KLight HDR)',
      resolution: '2160p', source: '4KLight', hdr: 'HDR10', lossless: false,
      videoCodec: 'H.265', channelsMin: 2, channelsMax: 6,
      fallbacks: {'hdr': _hdrOpti, 'videoCodec': ['H.264']}),
  C411Slot('OPTI-2160-SDR-BD', C411Profile.optimization,
      '2160p BluRay SDR H.265 Lossy',
      resolution: '2160p', source: 'BluRay', hdr: 'SDR', lossless: false,
      videoCodec: 'H.265', channelsMin: 2, channelsMax: 6,
      fallbacks: {
        'source': ['HDLight', 'WEB-DL', 'DVDRip', 'HDTV'],
        'videoCodec': ['H.264'],
      }),
  C411Slot('OPTI-2160-SDR-WR', C411Profile.optimization,
      '2160p Bluray.HDLight/WEBRip SDR H.265 Lossy',
      resolution: '2160p', source: 'HDLight', hdr: 'SDR', lossless: false,
      videoCodec: 'H.265', channelsMin: 2, channelsMax: 6,
      fallbacks: {
        'source': ['WEBRip', 'WEB-DL'],
        'videoCodec': ['H.264'],
      }),
];
