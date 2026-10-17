import 'dart:convert';
import 'dart:io';

import 'package:c411_remote/api/c411.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/ui/content_art.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:c411_remote/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Release _named(String name, {String subcategory = ''}) => Release(
    tracker: Tracker.tr4ker, id: name, name: name, subcategory: subcategory,
    createdAt: DateTime(2026));

void main() {
  test('type de contenu : fiche C411, sous-catégorie, nom', () {
    final page = C411Api.parsePage(jsonDecode(
            File('test/fixtures/c411_torrents.json').readAsStringSync())
        as Map<String, dynamic>);
    final kinds = {for (final r in page.items) r.id: ContentKind.of(r)};
    expect(kinds, {
      '766027': ContentKind.documentary, // Série Documentaire
      '765388': ContentKind.book, // Livres, sans fiche
      '764970': ContentKind.movie,
      '764830': ContentKind.movie,
      '764437': ContentKind.movie,
      '763938': ContentKind.movie,
      '762568': ContentKind.game, // fiche « game »
    });

    ContentKind k(String name, [String sub = '']) =>
        ContentKind.of(_named(name, subcategory: sub));
    expect(k('The.Bear.S03E01.1080p.WEB-GRP'), ContentKind.series);
    expect(k('Roman.Auteur.FR.EPUB-GRP'), ContentKind.book);
    expect(k('Artiste.Album.2001.FLAC-GRP'), ContentKind.music);
    expect(k('Concert.2024.1080p.BluRay.FLAC-GRP'), ContentKind.movie,
        reason: 'vidéo avec piste FLAC');
    expect(k('Jeu.v1.2-ElAmigos'), ContentKind.game);
    expect(k('Truc', 'Animation Série'), ContentKind.animation);
    expect(k('Truc', 'Logiciels'), ContentKind.software);
    expect(k('Archive-GRP'), ContentKind.other);
  });

  testWidgets('affiche absente : image du type de contenu', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: Poster(null,
              width: 120,
              height: 180,
              fallback: const ContentArt(ContentKind.music)),
        ),
      ),
    ));
    expect(find.byIcon(Icons.album_rounded), findsOneWidget);
    expect(find.text('MUSIQUE'), findsOneWidget);
  });

  test('picto des catégories : noms des trackers', () {
    expect(categoryIcon(null), Icons.apps_rounded, reason: 'Tout');
    // C411
    expect(categoryIcon('Films & Vidéos'), ContentKind.movie.icon);
    expect(categoryIcon('Ebook'), ContentKind.book.icon);
    expect(categoryIcon('Audio'), ContentKind.music.icon);
    expect(categoryIcon('Jeux Vidéo'), ContentKind.game.icon);
    expect(categoryIcon('Série Documentaire'), ContentKind.documentary.icon);
    expect(categoryIcon('Windows'), ContentKind.software.icon);
    // Nostradamus
    expect(categoryIcon('Séries TV'), ContentKind.series.icon);
    expect(categoryIcon('Vidéo-clips'), Icons.videocam_rounded);
    expect(categoryIcon('Animation Série'), ContentKind.animation.icon);
    expect(categoryIcon('Sport'), Icons.sports_soccer_rounded);
    expect(categoryIcon('Karaoke'), Icons.mic_rounded);
    expect(categoryIcon('Nintendo'), ContentKind.game.icon);
    // AstraTorrent
    expect(categoryIcon('XXX'), ContentKind.adult.icon);
    expect(categoryIcon('Logiciels'), ContentKind.software.icon);
    expect(categoryIcon('Divers'), Icons.label_rounded);
  });

  testWidgets('pastilles : picto devant le libellé', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: ChipRow<String?>(
          items: const [null, 'Films & Vidéos', 'Audio'],
          selected: null,
          label: (n) => n ?? 'Tout',
          icon: categoryIcon,
          onSelected: (_) {},
        ),
      ),
    ));
    expect(find.byIcon(Icons.apps_rounded), findsOneWidget);
    expect(find.byIcon(ContentKind.movie.icon), findsOneWidget);
    expect(find.byIcon(ContentKind.music.icon), findsOneWidget);
  });
}
