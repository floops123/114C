import '../api/tracker.dart';
import 'c411_slots.dart';
import 'release_name.dart';
import 'release_quality.dart';

/// Profils de qualité de C411 (système de slots), du plus exigeant au plus
/// léger. Libellés courts, descriptions et clés repris du site.
enum C411Profile {
  hcPure('pure', 'Home Cinéma Pure', 'Pure',
      'Qualité cinéma pure : Remux, audio lossless, fidèle au Blu-ray original sans compromis'),
  hcOptimized('hc_optimized', 'Home Cinéma Optimisé', 'HC Opti',
      'Home cinéma optimisé : meilleur rapport qualité/taille en HDR et audio multicanal'),
  optimization('optimization', 'Optimisation', 'Opti',
      'Poids minimal : encodage poussé pour économiser espace et bande passante'),
  compatibility('compatibility', 'Compatibilité', 'Compat',
      'Compatible partout : H.264, audio standard, lisible sur tous les appareils sans conversion');

  const C411Profile(this.key, this.label, this.short, this.description);

  /// Clé du profil côté C411 (`pure`, `hc_optimized`…).
  final String key;
  final String label;
  final String short;
  final String description;

  static C411Profile? fromKey(String? key) =>
      values.where((p) => p.key == key).firstOrNull;
}

/// Caractéristiques techniques d'une sortie : celles du tracker (C411
/// renseigne `tech`), sinon lues dans le nom, dans le vocabulaire de la
/// grille de C411.
class ReleaseTraits {
  const ReleaseTraits({
    this.resolution,
    this.source,
    this.codec,
    this.lossless,
    this.channels,
    this.channelCount,
    this.hdrFormat = 'SDR',
  });

  final String? resolution;

  /// Source normalisée (Remux, BDMV, ISO, 4KLight, HDLight, BluRay, WEB-DL,
  /// WEBRip, HDTV, DVDRip, DVD, SDTV).
  final String? source;

  /// H.264, H.265, AV1, VC-1, XviD, MPEG-2, VP9.
  final String? codec;

  /// Audio sans perte (TrueHD, DTS-HD MA, FLAC…) ; null si inconnu.
  final bool? lossless;

  /// Canaux audio (« 2.0 », « 5.1 », « 7.1 ») ; null si inconnus.
  final String? channels;

  /// Les mêmes en nombre (7.1 = 8), comme la grille de C411.
  final int? channelCount;

  /// DV.HDR10+, DV.HDR10, HDR10+, HDR10, DV ou SDR.
  final String hdrFormat;

  bool get dolbyVision => hdrFormat.startsWith('DV');
  bool get hdr => hdrFormat != 'SDR';

  /// Source brute du disque : REMUX, BDMV, ISO.
  bool get raw => const {'Remux', 'BDMV', 'ISO'}.contains(source);

  static final _token = RegExp(r'[.\s_\-\[\]()]+');
  static const _lossless = {'TRUEHD', 'FLAC', 'LPCM', 'PCM', 'DTSHD', 'DTS-HD', 'DTSX', 'DTS-X', 'DTS:X'};
  static const _lossy = {'AAC', 'EAC3', 'E-AC3', 'DDP', 'DD+', 'AC3', 'DD', 'DTS', 'MP3', 'OPUS', 'VORBIS'};
  static const _precise = {'Remux', 'BDMV', 'ISO', '4KLight', 'HDLight'};

  factory ReleaseTraits.of(Release r) {
    final name = r.name.toUpperCase();
    final set = name.split(_token).where((t) => t.isNotEmpty).toSet();
    final parsed = ReleaseName.parse(r.name);

    // Source : les termes précis du nom passent avant ceux du tracker
    // (« BluRay.4KLight » : 4KLight ; « BluRay.REMUX » : Remux).
    final fromName = normalizeSource(r.name);
    final source = _precise.contains(fromName)
        ? fromName
        : (r.source == null ? null : normalizeSource(r.source!)) ?? fromName;

    final codec = normalizeCodec(r.videoCodec ?? '') ?? normalizeCodec(r.name);

    // Audio : codec du tracker, sinon jetons du nom (DTS-HD MA s'écrit
    // aussi DTS.HD.MA).
    bool? lossless;
    final audio = r.audioCodec?.toUpperCase();
    if (audio != null && audio.isNotEmpty) {
      lossless = RegExp(r'TRUEHD|DTS-?HD|DTS[-:]?X|FLAC|PCM').hasMatch(audio);
    } else if (set.any(_lossless.contains) ||
        RegExp(r'DTS[.\s_-]HD').hasMatch(name)) {
      lossless = true;
    } else if (set.any(_lossy.contains)) {
      lossless = false;
    }

    final m = RegExp(r'(?:^|[.\s_-])([1-9])[.\s]([01])(?=$|[.\s_-])')
        .firstMatch(name);
    final channels = r.audioChannels ?? (m == null ? null : '${m[1]}.${m[2]}');

    var resolution = r.resolution ?? parsed.resolution;
    if (resolution == '1080i') resolution = '1080p';

    return ReleaseTraits(
      resolution: resolution,
      source: source,
      codec: codec,
      lossless: lossless,
      channels: channels,
      channelCount: channelsOf(r.audioChannels ?? '') ?? channelsOf(r.name),
      hdrFormat: normalizeHdr(r.hdrFormat) ?? hdrOfName(r.name),
    );
  }

  /// Créneau de la grille C411 le plus proche, ou null.
  SlotMatch? get slot => matchSlot((
        resolution: resolution,
        source: source,
        hdr: hdrFormat,
        lossless: lossless,
        channels: channelCount,
        videoCodec: codec,
      ));

  /// Profil C411 de la sortie, d'après la grille ; null si on ne peut pas
  /// trancher. Une source brute sans résolution connue reste « Pure ».
  C411Profile? get profile =>
      slot?.slot.profile ?? (raw ? C411Profile.hcPure : null);
}

/// Profil de la sortie : celui que C411 indique (`quality`) s'il le fait,
/// sinon déduit de la grille.
C411Profile? profileOf(Release r) =>
    C411Profile.fromKey(r.qualityProfile) ?? ReleaseTraits.of(r).profile;
