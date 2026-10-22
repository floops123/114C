import 'package:c411_remote/api/content_kind.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/release_name.dart';
import 'package:flutter_test/flutter_test.dart';

/// Une sortie telle que la construit le client du tracker : C411 donne sa
/// sous-catégorie et sa fiche, Torznab le type deviné du nom et les noms du
/// `caps`, AstraTorrent sa sous-catégorie et l'une de ses 8 catégories.
Release _release(Tracker tracker, List<String> categories,
    {String name = 'Sortie.2024.MULTi.1080p.WEB-GRP', String? sub, String? mediaKind}) {
  return Release(
    tracker: tracker,
    id: '1',
    name: name,
    subcategory: sub ?? (tracker == Tracker.c411 ? categories.last : ReleaseName.parse(name).kind),
    categories: categories,
    mediaKind: mediaKind,
    createdAt: DateTime(2026),
  );
}

void main() {
  // Noms réels : C411 (fixtures et sorties vues), Nostradamus (son `caps`
  // public), AstraTorrent (ses catégories fixes), Torznab standard (Prowlarr,
  // Jackett). Chaque groupe doit donner la même étiquette dans Transmission.
  final cases = <String, List<Release>>{
    'Films': [
      _release(Tracker.c411, ['Films & Vidéos', 'Film'], mediaKind: 'movie'),
      _release(Tracker.nostradamus, ['Films', 'Films/Film']),
      _release(Tracker.nostradamus, ['Films', 'Films/Court-métrage']),
      _release(Tracker.nostradamus, ['Films', 'Films/Spectacle']),
      _release(Tracker.astra, ['Films'], sub: 'Longs-métrages / Cinéma'),
      _release(Tracker.tr4ker, ['Movies', 'Movies/HD']),
    ],
    'Séries': [
      _release(Tracker.c411, ['Films & Vidéos', 'Série TV'],
          name: 'Serie.S01E01.1080p.WEB-GRP', mediaKind: 'tv'),
      _release(Tracker.nostradamus, ['Séries TV', 'Séries TV/Série TV'],
          name: 'Serie.S01E01.1080p.WEB-GRP'),
      _release(Tracker.nostradamus, ['Séries TV', 'Séries TV/Émission TV'], name: 'Emission.2024-GRP'),
      _release(Tracker.astra, ['Séries'], name: 'Serie.S01.1080p.WEB-GRP'),
      _release(Tracker.draupnirr, ['TV', 'TV/HD'], name: 'Serie.S01E01.1080p.WEB-GRP'),
    ],
    'Documentaires': [
      _release(Tracker.c411, ['Films & Vidéos', 'Série Documentaire'], mediaKind: 'tv'),
      _release(Tracker.nostradamus, ['Films', 'Films/Documentaire']),
      _release(Tracker.nostradamus, ['Séries TV', 'Séries TV/Documentaire']),
      _release(Tracker.tr4ker, ['TV', 'TV/Documentary']),
    ],
    'Animation': [
      _release(Tracker.c411, ['Films & Vidéos', 'Animation Série'], mediaKind: 'tv'),
      _release(Tracker.c411, ['Films & Vidéos', 'Animation'], mediaKind: 'movie'),
      _release(Tracker.nostradamus, ['Films', 'Films/Animation']),
      _release(Tracker.nostradamus, ['Séries TV', 'Séries TV/Animation Série']),
      _release(Tracker.astra, ['Animés']),
      _release(Tracker.tr4ker, ['TV', 'TV/Anime']),
    ],
    'Musique': [
      _release(Tracker.c411, ['Audio', 'Musique'], name: 'Artiste.Album.2024.FLAC-GRP'),
      _release(Tracker.nostradamus, ['Audio', 'Audio/Musique'], name: 'Artiste.Album.2024.FLAC-GRP'),
      _release(Tracker.nostradamus, ['Audio', 'Audio/Podcast Radio'], name: 'Podcast.2024-GRP'),
      _release(Tracker.astra, ['Musique'], name: 'Artiste.Album.2024.FLAC-GRP'),
      _release(Tracker.tr4ker, ['Audio', 'Audio/Lossless'], name: 'Artiste.Album.2024.FLAC-GRP'),
    ],
    'Livres': [
      _release(Tracker.c411, ['Ebook', 'Livres'], name: 'Auteur.Roman.FRENCH.EPUB-GRP'),
      _release(Tracker.c411, ['Ebook', 'Audio'], name: 'Auteur.Roman.FRENCH.MP3-GRP'),
      _release(Tracker.nostradamus, ['eBook', 'eBook/Livres'], name: 'Auteur.Roman.FRENCH.EPUB-GRP'),
      _release(Tracker.nostradamus, ['eBook', 'eBook/Audio'], name: 'Auteur.Roman.FRENCH.MP3-GRP'),
      _release(Tracker.nostradamus, ['eBook', 'eBook/BDs'], name: 'Serie.BD.T01.CBZ-GRP'),
      _release(Tracker.nostradamus, ['eBook', 'eBook/Mangas'], name: 'Manga.T01.CBZ-GRP'),
      _release(Tracker.nostradamus, ['eBook', 'eBook/Presse'], name: 'Journal.2024.PDF-GRP'),
      _release(Tracker.astra, ['Livres'], name: 'Auteur.Roman.FRENCH.EPUB-GRP'),
      _release(Tracker.tr4ker, ['Books', 'Books/EBook'], name: 'Auteur.Roman.FRENCH.EPUB-GRP'),
      _release(Tracker.tr4ker, ['Audio', 'Audio/Audiobook'], name: 'Auteur.Roman.FRENCH.MP3-GRP'),
    ],
    'Jeux vidéo': [
      _release(Tracker.c411, ['Jeux Vidéo', 'Windows'], name: 'Jeu.v1.2-GRP'),
      _release(Tracker.nostradamus, ['Jeu vidéo', 'Jeu vidéo/Windows'], name: 'Jeu.v1.2-GRP'),
      _release(Tracker.nostradamus, ['Jeu vidéo', 'Jeu vidéo/Linux'], name: 'Jeu.v1.2-GRP'),
      _release(Tracker.nostradamus, ['Jeu vidéo', 'Jeu vidéo/Nintendo'], name: 'Jeu.NSW-GRP'),
      _release(Tracker.astra, ['Jeux'], name: 'Jeu.v1.2-GRP'),
      _release(Tracker.tr4ker, ['PC', 'PC/Games'], name: 'Jeu.v1.2-GRP'),
      _release(Tracker.tr4ker, ['Console', 'Console/PS4'], name: 'Jeu.PS4-GRP'),
    ],
    'Logiciels': [
      _release(Tracker.c411, ['Applications', 'Windows'], name: 'Logiciel.v3.0.x64-GRP'),
      _release(Tracker.astra, ['Logiciels'], name: 'Logiciel.v3.0.x64-GRP'),
      _release(Tracker.tr4ker, ['PC', 'PC/0day'], name: 'Logiciel.v3.0.x64-GRP'),
    ],
    'Adulte': [
      _release(Tracker.astra, ['XXX']),
      _release(Tracker.tr4ker, ['XXX', 'XXX/x264']),
    ],
  };

  for (final MapEntry(key: label, value: releases) in cases.entries) {
    test('étiquette « $label » quel que soit le tracker', () {
      for (final r in releases) {
        expect(ContentKind.of(r).labels, [label],
            reason: '${r.tracker.label} : ${r.categories.join(' › ')}');
      }
    });
  }

  test('étiquettes = noms des filtres du catalogue ; aucune pour un contenu inconnu', () {
    for (final k in ContentKind.values) {
      expect(k.labels, k == ContentKind.other ? isEmpty : [k.plural]);
      expect(k.plural, isNot(contains(',')), reason: 'Transmission sépare les étiquettes par des virgules');
    }
  });

  test('ajout à la main : catégorie devinée d’après le nom', () {
    expect(ContentKind.ofName('Serie.S01E01.1080p.WEB-GRP').labels, ['Séries']);
    expect(ContentKind.ofName('Film.2024.MULTi.2160p.WEB-GRP').labels, ['Films']);
    expect(ContentKind.ofName('Auteur.Roman.FRENCH.EPUB-GRP').labels, ['Livres']);
    expect(ContentKind.ofName('Artiste.Album.2024.FLAC-GRP').labels, ['Musique']);
    expect(ContentKind.ofName('Jeu-ElAmigos').labels, ['Jeux vidéo']);
    expect(ContentKind.ofName('').labels, isEmpty, reason: 'lien sans nom');
    expect(ContentKind.ofName('archive').labels, isEmpty);
  });

  test('AddOptions.withLabels : complète sans doublon ni perte des autres options', () {
    const base = AddOptions(downloadDir: '/data', paused: true, labels: ['cross-seed', 'Films'], bandwidthPriority: 1);
    final o = base.withLabels(['Films', 'Séries']);
    expect(o.labels, ['cross-seed', 'Films', 'Séries']);
    expect(o.toArgs(), {
      'download-dir': '/data',
      'paused': true,
      'labels': ['cross-seed', 'Films', 'Séries'],
      'bandwidthPriority': 1,
    });
    expect(const AddOptions().withLabels(const []).toArgs(), isNot(contains('labels')));
  });
}
