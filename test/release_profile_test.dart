import 'dart:convert';
import 'dart:io';

import 'package:c411_remote/api/c411.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/core/release_profile.dart';
import 'package:flutter_test/flutter_test.dart';

Release _named(String name) =>
    Release(tracker: Tracker.tr4ker, id: name, name: name, createdAt: DateTime(2026));

void main() {
  test('C411 : profil d’après les infos techniques du tracker', () {
    final page = C411Api.parsePage(jsonDecode(
            File('test/fixtures/c411_torrents.json').readAsStringSync())
        as Map<String, dynamic>);
    final profiles = {for (final r in page.items) r.id: profileOf(r)};
    expect(profiles, {
      // WEBRip H.265 : slot « WR » du Home Cinéma Optimisé.
      '766027': C411Profile.hcOptimized,
      '765388': null, // livre
      // WEB-DL DV, TrueHD Atmos 7.1.
      '764970': C411Profile.hcOptimized,
      '764830': C411Profile.hcOptimized, // 4KLight
      '764437': C411Profile.hcPure, // Remux
      '763938': C411Profile.hcOptimized,
      '762568': null, // jeu
    });
    final dune2 = ReleaseTraits.of(page.items.firstWhere((r) => r.id == '764970'));
    expect((dune2.lossless, dune2.channels, dune2.dolbyVision, dune2.codec),
        (true, '7.1', true, 'H.265'));
  });

  test('autres trackers : profil lu dans le nom, d’après la grille C411', () {
    String? p(String name) => profileOf(_named(name))?.label;
    String? slot(String name) => ReleaseTraits.of(_named(name)).slot?.slot.id;
    expect(p('Film.2024.MULTi.1080p.WEB.H264.AAC.2.0-GRP'), 'Compatibilité');
    expect(p('Film.2024.MULTi.1080p.WEB.H264.AAC.5.1-GRP'), 'Compatibilité',
        reason: 'COMPAT-01 n’impose pas de maximum de canaux');
    expect(slot('Film.2024.MULTi.1080p.BluRay.HDLight.x265.AC3.5.1-GRP'),
        'HCOPT-1080-WR-H265', reason: 'critères respectés à la lettre');
    expect(slot('Film.2024.MULTi.2160p.BluRay.4KLight.HDR10.x265.AC3.5.1-GRP'),
        'OPTI-2160-HDR-4KL');
    expect(p('Film.2024.MULTi.2160p.WEB-DL.DV.HDR.DDP.5.1.H265-GRP'),
        'Home Cinéma Optimisé');
    expect(p('Film.2024.1080p.BluRay.DTS-HD.MA.5.1.x264-GRP'), 'Compatibilité',
        reason: 'aucun créneau HC Opti n’accepte le H.264 ; Compat accepte '
            'l’audio sans perte en repli');
    expect(p('Film.2024.MULTi.1080p.WEB.AV1.OPUS.5.1-GRP'), 'Home Cinéma Optimisé');
    expect(slot('Film.2024.1080p.BluRay.REMUX.AVC.DTS-HD.MA.5.1-GRP'),
        'PURE-BD-REMUX');
    expect(p('Film.2024.MULTi.2160p.BluRay.REMUX.HEVC.DV.TrueHD.7.1-GRP'),
        'Home Cinéma Pure');
    expect(p('Livre.2024.FRENCH.EPUB-GRP'), isNull, reason: 'pas une vidéo');
  });

  test('grille : bornes de canaux et replis', () {
    String? slot(String name) => ReleaseTraits.of(_named(name)).slot?.slot.id;
    // Opti : 2 à 6 canaux ; un 7.1 lossy en H.265 SDR part en HC Opti.
    expect(slot('Film.2024.MULTi.2160p.WEB-DL.DDP.7.1.H265-GRP'),
        'HCOPT-2160-WR-H265');
    // VC-1 : seul le créneau Remux VC-1 l'accepte.
    expect(slot('Film.2024.1080p.BluRay.REMUX.VC-1.DTS-HD.MA.5.1-GRP'),
        'PURE-BD-VC1');
  });
}
