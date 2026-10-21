import 'package:c411_remote/api/c411.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/core/release_profile.dart';
import 'package:c411_remote/core/release_quality.dart';
import 'package:flutter_test/flutter_test.dart';

Release _r(String name, {String? quality}) => Release(
    tracker: Tracker.c411,
    id: name,
    name: name,
    qualityProfile: quality,
    createdAt: DateTime(2026));

void main() {
  group('languageLabel (comme sur C411)', () {
    test('listes renvoyées par l’API C411', () {
      expect(languageLabel(['MULTI', 'VFF', 'VF']), 'MULTI.VFF');
      expect(languageLabel(['MULTI', 'VFF', 'VFQ', 'VF2', 'ANGLAIS']),
          'MULTI.VF2');
      expect(languageLabel(['MULTI', 'VFF', 'VF2', 'ANGLAIS', 'VO']),
          'MULTI.VF2');
      expect(languageLabel(['VOF']), 'VOF');
    });

    test('doublages', () {
      expect(languageLabel(['VFF', 'VFQ']), 'VF2', reason: 'France + Québec');
      expect(languageLabel(['VFQ']), 'VFQ');
      expect(languageLabel(['TRUEFRENCH']), 'VFF');
      expect(languageLabel(['VFF', 'ANGLAIS']), 'MULTI.VFF',
          reason: 'une autre langue en plus : multi');
      expect(languageLabel(['VFF', 'VO']), 'MULTI.VFF');
    });

    test('tables exactes du site', () {
      expect(languageLabel(['TRUEFRENCH', 'VFQ']), 'VFQ',
          reason: 'VF2 = VFF ou VOF avec VFQ ; TrueFrench ne compte pas');
      expect(languageLabel(['VOF', 'VFQ']), 'VF2');
      expect(languageLabel(['VFF', 'GERMAN']), 'MULTI.VFF');
      expect(languageLabel(['VFF', 'VFB']), 'VFF', reason: 'VFB : pas une autre langue');
      expect(languageLabel(['FRENCH']), 'VF');
    });

    test('sous-titres seuls', () {
      expect(languageLabel(['VOSTFR']), 'VOSTFR');
      expect(languageLabel(['MULTI', 'VOSTFR']), 'MULTI.VOSTFR');
      expect(languageLabel(['VFF', 'VOSTFR']), 'VFF',
          reason: 'un doublage passe avant les sous-titres');
    });

    test('ni doublage ni sous-titres', () {
      expect(languageLabel(['MULTI']), 'MULTI');
      expect(languageLabel(['ANGLAIS', 'ALLEMAND', 'VO']), 'ANGLAIS.ALLEMAND');
      expect(languageLabel(const []), '');
    });

    test('descriptions', () {
      expect(languageDescription('MULTI.VF2'),
          'Multi-langues avec VFF + VFQ (doublage France et Québec)');
      expect(languageDescription('VOSTFR'),
          'Version Originale Sous-Titrée Français');
      expect(languageDescription('ANGLAIS'), 'Langue : ANGLAIS');
    });
  });

  test('descriptions techniques', () {
    expect(resolutionDescription('2160p'), 'Résolution 4K Ultra HD (3840×2160)');
    expect(sourceDescription('Remux'),
        'Remux : copie directe du Blu-ray sans ré-encodage');
    expect(sourceDescription('WEB-DL'),
        'WEB-DL : téléchargé depuis un service de streaming sans perte');
    expect(videoCodecDescription('x265'),
        'Codec H.265 (HEVC) : compression efficace, qualité élevée');
    expect(hdrDescription('DV.HDR10+'),
        'Dolby Vision + HDR10+ : double format HDR dynamique');
    expect(audioDescription('TrueHD Atmos', '7.1'),
        'Dolby TrueHD : audio lossless haute fidélité - 7.1 canaux');
    expect(audioDescription('AAC', '2.0'), 'AAC : audio lossy compact');
    expect(audioDescription('EAC3'),
        'Dolby Digital Plus (EAC3) : audio lossy de qualité');
  });

  test('équipe et bonus', () {
    expect(releaseGroup('Film.2024.1080p.WEB.H264-GRP'), 'GRP');
    expect(releaseGroup('Film.2024.1080p.WEB.H264-NoTag.mkv'), 'NoTag');
    expect(releaseGroup('Film 2024 1080p'), isNull);
    expect(isBonus('Film.2024.BONUS.1080p-GRP'), isTrue);
    expect(isBonus('Bonusland.2024.1080p-GRP'), isFalse);
  });

  group('profil', () {
    test('libellés courts du site', () {
      expect([for (final p in C411Profile.values) p.short],
          ['Pure', 'HC Opti', 'Opti', 'Compat']);
      expect(C411Profile.fromKey('hc_optimized'), C411Profile.hcOptimized);
      expect(C411Profile.fromKey('autre'), isNull);
    });

    test('champ `quality` de C411', () {
      expect(qualityKey('hc_optimized'), 'hc_optimized');
      expect(qualityKey({'slug': 'pure', 'label': 'Pure'}), 'pure');
      expect(qualityKey(null), isNull);
      expect(qualityKey('excellent'), isNull);
    });

    test('le profil annoncé par C411 passe avant la déduction', () {
      const remux = 'Film.2024.1080p.BluRay.REMUX.AVC.DTS-HD.MA.5.1-GRP';
      expect(profileOf(_r(remux)), C411Profile.hcPure);
      expect(profileOf(_r(remux, quality: 'optimization')),
          C411Profile.optimization);
    });

    test('DTS:X reconnu comme sans perte', () {
      expect(
          ReleaseTraits.of(_r('Film.2024.2160p.BluRay.DTS:X.7.1.x265-GRP'))
              .lossless,
          isTrue);
    });
  });
}
