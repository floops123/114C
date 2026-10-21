import '../api/tracker.dart';
import 'release_name.dart';

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
/// renseigne `tech`), sinon lues dans le nom.
class ReleaseTraits {
  const ReleaseTraits({
    this.resolution,
    this.source,
    this.codec,
    this.lossless,
    this.channels,
    this.dolbyVision = false,
    this.hdr = false,
    this.raw = false,
  });

  final String? resolution;

  /// Source normalisée (BluRay, WEB-DL, WEBRip, 4KLight, HDLight…).
  final String? source;

  /// H.264, H.265 ou AV1.
  final String? codec;

  /// Audio sans perte (TrueHD, DTS-HD MA, FLAC…) ; null si inconnu.
  final bool? lossless;

  /// Canaux audio (« 2.0 », « 5.1 », « 7.1 ») ; null si inconnus.
  final String? channels;
  final bool dolbyVision;

  /// HDR quelconque (HDR10, HDR10+, DV).
  final bool hdr;

  /// Source brute du disque : REMUX, BDMV, ISO.
  final bool raw;

  static final _token = RegExp(r'[.\s_\-\[\]()]+');
  static const _lossless = {'TRUEHD', 'FLAC', 'LPCM', 'PCM', 'DTSHD', 'DTS-HD', 'DTSX', 'DTS-X', 'DTS:X'};
  static const _lossy = {'AAC', 'EAC3', 'E-AC3', 'DDP', 'DD+', 'AC3', 'DD', 'DTS', 'MP3', 'OPUS'};

  factory ReleaseTraits.of(Release r) {
    final name = r.name.toUpperCase();
    final tokens = name.split(_token).where((t) => t.isNotEmpty).toList();
    final set = tokens.toSet();
    final parsed = ReleaseName.parse(r.name);

    // Source : les termes précis du nom passent avant ceux du tracker
    // (« BluRay.4KLight » : 4KLight).
    String? source;
    if (set.contains('4KLIGHT')) {
      source = '4KLight';
    } else if (set.contains('HDLIGHT')) {
      source = 'HDLight';
    } else {
      source = r.source ?? parsed.source;
    }
    final raw = set.contains('REMUX') ||
        set.contains('BDMV') ||
        set.contains('ISO') ||
        (source?.toUpperCase() == 'REMUX');

    String? codec;
    final c = (r.videoCodec ?? parsed.videoCodec ?? '').toUpperCase();
    if (c.contains('AV1') || set.contains('AV1')) {
      codec = 'AV1';
    } else if (c.contains('265') || c.contains('HEVC')) {
      codec = 'H.265';
    } else if (c.contains('264') || c.contains('AVC')) {
      codec = 'H.264';
    }

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

    final hdrFormat = (r.hdrFormat ?? '').toUpperCase();
    final dv = hdrFormat.contains('DV') ||
        set.contains('DV') ||
        set.contains('DOVI') ||
        name.contains('DOLBY.VISION');
    final hdr = dv ||
        (hdrFormat.isNotEmpty && hdrFormat != 'SDR') ||
        set.any((t) => t.startsWith('HDR'));

    return ReleaseTraits(
      resolution: r.resolution ?? parsed.resolution,
      source: source,
      codec: codec,
      lossless: lossless,
      channels: channels,
      dolbyVision: dv,
      hdr: hdr,
      raw: raw,
    );
  }

  /// Profil C411 de la sortie, ou null si on ne peut pas trancher.
  C411Profile? get profile {
    if (raw) return C411Profile.hcPure;
    final res = resolution?.toLowerCase();
    final src = source?.toUpperCase();
    if (res == '1080p' &&
        codec == 'H.264' &&
        lossless == false &&
        channels == '2.0' &&
        !hdr) {
      return C411Profile.compatibility;
    }
    // Ce que le profil Optimisation refuse ou relègue : audio sans perte,
    // AV1, 7.1, Dolby Vision ; et les sources des slots BluRay / 4KLight /
    // HDLight / WEBRip du profil Home Cinéma Optimisé.
    if (lossless == true ||
        codec == 'AV1' ||
        channels == '7.1' ||
        dolbyVision ||
        src == 'BLURAY' ||
        src == '4KLIGHT' ||
        src == 'HDLIGHT' ||
        src == 'WEBRIP') {
      return codec == null && src == null ? null : C411Profile.hcOptimized;
    }
    if ((codec == 'H.265' || codec == 'H.264') && lossless == false) {
      return C411Profile.optimization;
    }
    return null;
  }
}

/// Profil de la sortie : celui que C411 indique (`quality`) s'il le fait,
/// sinon déduit des caractéristiques techniques.
C411Profile? profileOf(Release r) =>
    C411Profile.fromKey(r.qualityProfile) ?? ReleaseTraits.of(r).profile;
