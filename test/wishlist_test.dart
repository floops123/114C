import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:c411_remote/api/c411.dart';
import 'package:c411_remote/api/tmdb.dart';
import 'package:c411_remote/core/preferences.dart';
import 'package:c411_remote/core/release_profile.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/state/wishlist.dart';
import 'package:c411_remote/ui/releases_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:c411_remote/ui/wishlist_page.dart';
import 'package:c411_remote/ui/title_detail_page.dart';
import 'package:c411_remote/ui/wish_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tracker qui cherche la chaîne telle quelle.
class _Tracker implements TrackerApi {

  @override
  void close() {}
  _Tracker(this.results);
  final Map<String, List<Release>> results;
  final queries = <String>[];

  @override
  Tracker get tracker => Tracker.c411;
  @override
  List<ReleaseSort> get sorts => const [];
  @override
  Set<ReleaseSort> get serverSorts => const {};
  @override
  Future<List<Category>> categories() async => const [];
  @override
  Future<ReleasePage> releases({int page = 1, int perPage = 50, int? categoryId,
      int? subcategoryId, String query = '', ReleaseSort sort = ReleaseSort.date,
      bool ascending = false}) async {
    queries.add(query);
    final r = results[query] ?? const [];
    return ReleasePage(r, 1, 1, r.length);
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async => Uint8List(0);
}

Release _rel(String id, int? year, int seeders) => Release(
    tracker: Tracker.tr4ker, id: id, name: 'R$id', year: year, seeders: seeders,
    createdAt: DateTime(2026));

TmdbTitle _movie(int id, String date) => TmdbTitle(
    id: id, type: TmdbType.movie, title: 'Film $id', date: DateTime.parse(date));

void main() {
  test('TMDB : films et séries, aller-retour JSON', () {
    final movie = TmdbTitle.fromApi({
      'id': 1, 'title': 'Dune : Troisième partie', 'original_title': 'Dune: Part Three',
      'release_date': '2026-12-16', 'poster_path': '/a.jpg', 'overview': ' Suite. ',
      'vote_average': 7.83, 'vote_count': 1520,
    }, TmdbType.movie);
    expect((movie.title, movie.originalTitle, movie.year), ('Dune : Troisième partie', 'Dune: Part Three', 2026));
    expect(movie.posterUrl, 'https://image.tmdb.org/t/p/w500/a.jpg');
    expect(movie.overview, 'Suite.');
    final tv = TmdbTitle.fromApi(
        {'id': 2, 'name': 'Série', 'first_air_date': '', 'overview': ''}, TmdbType.tv);
    expect((tv.title, tv.date, tv.overview, tv.upcoming), ('Série', null, null, true));
    expect((movie.rating, movie.votes), (7.83, 1520));
    expect((tv.rating, tv.votes), (null, 0), reason: 'sans vote : pas de note');

    final back = TmdbTitle.fromJson(movie.toJson());
    expect(back, movie);
    expect((back.title, back.date, back.posterUrl), (movie.title, movie.date, movie.posterUrl));
    expect((back.rating, back.votes), (7.83, 1520));
    // Titre enregistré avant la note : votes inconnus, à relire.
    expect(TmdbTitle.fromJson({'id': 3, 'type': 'movie', 'title': 'Ancien'}).votes, isNull);
  });

  testWidgets('note TMDB sous l’affiche', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tmdbProvider.overrideWithValue(_Tmdb()),
        wishlistStoreProvider.overrideWithValue(MemoryWishlistStore()),
        trackersProvider.overrideWithValue(const {}),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: FeedPage(feed: TmdbFeed.discover().first),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2099  ★ 7,8'), findsOneWidget);
  });

  test('liste : ajout, retrait, sorties proches d’abord, mémorisée', () {
    final store = MemoryWishlistStore();
    ProviderContainer container() {
      final c = ProviderContainer(
          overrides: [wishlistStoreProvider.overrideWithValue(store)]);
      addTearDown(c.dispose);
      return c;
    }

    final c = container();
    final n = c.read(wishlistProvider.notifier);
    n.add(_movie(1, '2027-03-01'));
    n.add(_movie(2, '2026-11-20'));
    n.add(const TmdbTitle(id: 3, type: TmdbType.tv, title: 'Sans date'));
    n.add(_movie(1, '2027-03-01')); // déjà présent
    expect(c.read(wishlistProvider).map((i) => i.title.id), [2, 1, 3]);
    n.toggle(_movie(2, '2026-11-20'));
    expect(c.read(wishlistProvider).map((i) => i.title.id), [1, 3]);

    // Rechargée au prochain lancement.
    expect(container().read(wishlistProvider).map((i) => i.title.id), [1, 3]);
  });

  test('recherche sur un tracker : titres, points, année, seeders', () async {
    final api = _Tracker({
      'Dune.Troisieme.partie': [_rel('a', 2026, 5), _rel('b', 1984, 90)],
      'Dune: Part Three': [_rel('a', 2026, 5), _rel('c', null, 50), _rel('d', 2027, 1)],
    });
    final t = TmdbTitle(
        id: 1, type: TmdbType.movie, title: 'Dune Troisième partie',
        originalTitle: 'Dune: Part Three', date: DateTime(2026, 12, 16));
    final found = await searchWish(api, t);
    // Format des noms de release d'abord ; variante suivante tant que rien.
    expect(api.queries, [
      'Dune.Troisieme.partie',
      'Dune.Part.Three', 'Dune Part Three', 'Dune: Part Three',
    ]);
    // 1984 écarté ; la bonne année d'abord, puis par seeders.
    expect(found.map((r) => r.id), ['a', 'c', 'd']);

    // Série : pas de filtre d'année (saisons).
    final serie = await searchWish(api, const TmdbTitle(
        id: 2, type: TmdbType.tv, title: 'Dune.Troisième.partie'));
    expect(serie.map((r) => r.id), ['b', 'a']);
  });

  testWidgets('page de recherche d’un souhait : résultats par tracker', (tester) async {
    final api = _Tracker({'Film 1': [_rel('a', 2099, 5)]});
    await tester.pumpWidget(ProviderScope(
      overrides: [trackersProvider.overrideWithValue({Tracker.c411: api})],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: WishSearchPage(title: _movie(1, '2099-12-16')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(Tab), matching: find.text('C411')),
        findsOneWidget);
    expect(find.descendant(of: find.byType(Badge), matching: find.text('1')),
        findsOneWidget);
    expect(find.text('Ra'), findsOneWidget);
    expect(find.text('Sortie le 16/12/2099'), findsOneWidget);
  });

  test('dates françaises : salles, VOD, DVD ; tri sur la prochaine', () {
    final f = FrenchDates.fromApi({
      'results': [
        {'iso_3166_1': 'US', 'release_dates': [
          {'type': 3, 'release_date': '2026-01-01T00:00:00.000Z'},
        ]},
        {'iso_3166_1': 'FR', 'release_dates': [
          {'type': 1, 'release_date': '2026-02-01T00:00:00.000Z'},
          {'type': 3, 'release_date': '2026-02-11T00:00:00.000Z'},
          {'type': 3, 'release_date': '2026-02-10T00:00:00.000Z'},
          {'type': 4, 'release_date': '2099-06-10T00:00:00.000Z'},
        ]},
      ],
    });
    expect((f.cinema, f.digital, f.physical),
        (DateTime(2026, 2, 10), DateTime(2099, 6, 10), null));

    // Sorti en salles, VOD à venir : la VOD est la prochaine étape.
    final t = _movie(1, '2026-01-01').withFrench(f);
    expect(t.nextDate, DateTime(2099, 6, 10));
    expect(t.upcoming, isFalse);
    final back = TmdbTitle.fromJson(t.toJson());
    expect((back.french!.cinema, back.french!.digital), (f.cinema, f.digital));
  });

  test('fiche TMDB : équipe, distribution, bande-annonce, classification', () {
    final d = TmdbDetails.fromApi({
      'tagline': ' ', 'runtime': 166, 'status': 'Released', 'vote_average': 8.2,
      'vote_count': 5000, 'backdrop_path': '/b.jpg',
      'genres': [{'id': 878, 'name': 'Science-Fiction'}],
      'credits': {
        'cast': [{'name': 'Timothée Chalamet', 'character': 'Paul', 'profile_path': '/t.jpg'}],
        'crew': [
          {'name': 'Denis Villeneuve', 'job': 'Director'},
          {'name': 'Denis Villeneuve', 'job': 'Screenplay'},
          {'name': 'Jon Spaihts', 'job': 'Screenplay'},
          {'name': 'X', 'job': 'Editor'},
        ],
      },
      'videos': {'results': [
        {'site': 'YouTube', 'type': 'Teaser', 'iso_639_1': 'fr', 'key': 'teaserfr'},
        {'site': 'YouTube', 'type': 'Trailer', 'iso_639_1': 'en', 'key': 'traileren'},
        {'site': 'YouTube', 'type': 'Trailer', 'iso_639_1': 'fr', 'key': 'trailerfr'},
      ]},
      'release_dates': {'results': [
        {'iso_3166_1': 'FR', 'release_dates': [
          {'type': 3, 'release_date': '2024-02-28T00:00:00.000Z', 'certification': ''},
          {'type': 4, 'release_date': '2024-06-26T00:00:00.000Z', 'certification': 'Tous publics'},
        ]},
      ]},
      'recommendations': {'results': [{'id': 9, 'title': 'Dune'}]},
    }, TmdbType.movie);
    expect((d.tagline, d.runtime, d.status, d.rating, d.votes),
        (null, 166, 'Sorti', 8.2, 5000));
    expect(d.backdropUrl, 'https://image.tmdb.org/t/p/w780/b.jpg');
    expect(d.genres, ['Science-Fiction']);
    expect(d.directors.map((p) => p.name), ['Denis Villeneuve']);
    expect(d.writers.map((p) => p.name), ['Denis Villeneuve', 'Jon Spaihts']);
    expect((d.cast.single.name, d.cast.single.role, d.cast.single.photoUrl),
        ('Timothée Chalamet', 'Paul', 'https://image.tmdb.org/t/p/w185/t.jpg'));
    expect(d.trailer.toString(), 'https://www.youtube.com/watch?v=trailerfr');
    expect(d.certification, 'Tous publics');
    expect(d.french!.digital, DateTime(2024, 6, 26));
    expect(d.recommendations.single.key, 'movie:9');

    final tv = TmdbDetails.fromApi({
      'number_of_seasons': 2, 'number_of_episodes': 16, 'episode_run_time': [52],
      'status': 'Returning Series', 'created_by': [{'name': 'Créateur'}],
      'networks': [{'name': 'Canal+'}],
      'content_ratings': {'results': [{'iso_3166_1': 'FR', 'rating': '12'}]},
    }, TmdbType.tv);
    expect((tv.seasons, tv.episodes, tv.runtime, tv.status, tv.certification),
        (2, 16, 52, 'En cours', '12'));
    expect(tv.directors.single.name, 'Créateur');
    expect(tv.networks, ['Canal+']);
  });

  test('Découvrir : rangées centrées sur la France', () {
    final feeds = {for (final f in TmdbFeed.discover(DateTime(2026, 10, 17))) f.key: f};
    expect(feeds['fr_upcoming']!.query, {
      'region': 'FR',
      'with_release_type': '2|3',
      'release_date.gte': '2026-10-17',
      'release_date.lte': '2027-04-15',
      'sort_by': 'popularity.desc',
    });
    expect(feeds['fr_digital']!.query['release_date.gte'], '2026-07-19');
    expect(feeds['fr_movies']!.query['with_original_language'], 'fr');
    expect(feeds['fr_tv']!.type, TmdbType.tv);
    expect(feeds['trending']!.type, isNull, reason: 'films et séries mêlés');
    final g = TmdbFeed.genre(const TmdbGenre(28, 'Action'), TmdbType.movie);
    expect((g.path, g.query['with_genres'], g.query['region']), ('/discover/movie', '28', 'FR'));
    expect(TmdbApi.parseTitles({
      'results': [
        {'media_type': 'movie', 'id': 1, 'title': 'A'},
        {'media_type': 'person', 'id': 2, 'name': 'B'},
        {'media_type': 'tv', 'id': 3, 'name': 'C'},
      ],
    }).map((t) => t.key), ['movie:1', 'tv:3']);
  });

  testWidgets('Découvrir : rangées, fiche avec dates françaises, ajout', (tester) async {
    final api = _Tmdb();
    final store = MemoryWishlistStore();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tmdbProvider.overrideWithValue(api),
        wishlistStoreProvider.overrideWithValue(store),
        trackersProvider.overrideWithValue(const {}),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const WishlistPage(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Au cinéma en France'), findsOneWidget, reason: 'liste vide : Découvrir');
    await tester.scrollUntilVisible(find.text('Films par genre'), 400,
        scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down));
    expect(find.text('Action'), findsWidgets);

    await tester.scrollUntilVisible(find.text('Film 1').first, -400,
        scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down));
    await tester.tap(find.text('Film 1').hitTestable().first);
    await tester.pumpAndSettle();
    // Fiche : genres, durée, dates françaises, distribution.
    expect(find.text('Sorties en France'), findsOneWidget);
    expect(find.text('10/02/2099'), findsOneWidget);
    expect(find.textContaining('2 h 05'), findsOneWidget);
    expect(find.textContaining('Action'), findsWidgets);
    expect(find.text('Acteur A'), findsOneWidget);
    expect(find.text('Bande-annonce'), findsOneWidget);
    await tester.tap(find.text('Ajouter à la liste'));
    await tester.pumpAndSettle();
    expect(store.load().single.title.french?.cinema, DateTime(2099, 2, 10),
        reason: 'dates françaises lues à l’ajout');
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('fiche sans débordement : noms et rôles longs (texte ×$scale)',
        (tester) async {
      final api = _Tmdb(cast: const [
        TmdbPerson('Jean-Baptiste Maunier-Delacroix de la Tour',
            role: 'Le capitaine de la garde royale, dit « le Borgne »'),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          tmdbProvider.overrideWithValue(api),
          wishlistStoreProvider.overrideWithValue(MemoryWishlistStore()),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: TitleDetailPage(title: _movie(1, '2099-01-01')),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Film 2'), 300,
          scrollable: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  group('classement des résultats', () {
    Release r(String name, {int size = 0, int seeders = 0, String? source}) =>
        Release(tracker: Tracker.tr4ker, id: name, name: name, size: size,
            seeders: seeders, source: source, createdAt: DateTime(2026));
    final items = [
      r('Film.2026.1080p.WEB-DL-GRP', size: 4, seeders: 50),
      r('Film.2026.2160p.BluRay.REMUX-GRP', size: 60, seeders: 3),
      r('Film.2026.MULTi.1080p.BluRay-GRP', size: 12, seeders: 9),
      r('Film 2026 720p HDLight', size: 2, seeders: 1),
      r('Film.2026.FRENCH-GRP', size: 1, seeders: 20, source: 'WebDL'),
    ];
    List<String> names(WishSort s, [bool asc = false]) => [
          for (final (_, g) in sortWish(items, s, asc)) ...g.map((r) => r.id),
        ];
    List<String?> headers(WishSort s) =>
        [for (final (h, g) in sortWish(items, s, false)) '$h:${g.length}'];

    test('qualité et type lus dans le nom, sinon chez le tracker', () {
      expect(items.map(qualityOf), ['1080p', '2160p', '1080p', '720p', null]);
      // « BluRay.REMUX » : un Remux, pas un BluRay.
      expect(items.map(typeOf), ['WEB-DL', 'Remux', 'BluRay', 'HDLight', 'WEB-DL']);
    });

    test('qualité : groupes par résolution, source puis seeders', () {
      expect(names(WishSort.quality), [
        'Film.2026.2160p.BluRay.REMUX-GRP',
        'Film.2026.MULTi.1080p.BluRay-GRP', // BluRay avant WEB-DL
        'Film.2026.1080p.WEB-DL-GRP',
        'Film 2026 720p HDLight',
        'Film.2026.FRENCH-GRP',
      ]);
      expect(headers(WishSort.quality),
          ['2160p:1', '1080p:2', '720p:1', 'Qualité inconnue:1']);
      expect(names(WishSort.quality, true).first, 'Film.2026.FRENCH-GRP');
    });

    test('profil C411 : groupes du plus exigeant au plus léger', () {
      expect(headers(WishSort.profile),
          ['Home Cinéma Pure:1', 'Home Cinéma Optimisé:2', 'Non classé:2']);
      // Dans un groupe : la meilleure résolution d'abord.
      expect(names(WishSort.profile).take(3), [
        'Film.2026.2160p.BluRay.REMUX-GRP',
        'Film.2026.MULTi.1080p.BluRay-GRP',
        'Film 2026 720p HDLight',
      ]);
    });

    test('taille, seeders, pertinence : sans groupe', () {
      expect(names(WishSort.size).first, 'Film.2026.2160p.BluRay.REMUX-GRP');
      expect(names(WishSort.size, true).first, 'Film.2026.FRENCH-GRP');
      expect(names(WishSort.seeders).first, 'Film.2026.1080p.WEB-DL-GRP');
      expect(names(WishSort.relevance), items.map((r) => r.id));
      expect(headers(WishSort.size), ['null:5']);
    });
  });

  testWidgets('résultats : intertitres quand on classe par qualité', (tester) async {
    final api = _Tracker({'Film 1': [
      Release(tracker: Tracker.tr4ker, id: 'a', name: 'Film.1.2099.1080p.WEB-DL-G',
          year: 2099, createdAt: DateTime(2026)),
      Release(tracker: Tracker.tr4ker, id: 'b', name: 'Film.1.2099.2160p.BluRay-G',
          year: 2099, createdAt: DateTime(2026)),
    ]});
    final container = ProviderContainer(
        overrides: [trackersProvider.overrideWithValue({Tracker.c411: api})]);
    addTearDown(container.dispose);
    container.read(wishSortProvider.notifier).set(WishSort.quality, false);
    container.read(uiPrefsProvider.notifier).setReleasesGrid(false); // liste
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: WishSearchPage(title: _movie(1, '2099-12-16')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2160p (1)'), findsOneWidget);
    expect(find.text('1080p (1)'), findsOneWidget);
    expect(tester.getTopLeft(find.text('2160p (1)')).dy,
        lessThan(tester.getTopLeft(find.text('1080p (1)')).dy));

    // Par profil C411 : intertitre, description et étiquette sur la ligne.
    container.read(wishSortProvider.notifier).set(WishSort.profile, false);
    await tester.pumpAndSettle();
    expect(find.text('Home Cinéma Optimisé (1)'), findsOneWidget);
    expect(find.text(C411Profile.hcOptimized.description), findsOneWidget);
    expect(find.text('HC Opti'), findsOneWidget);
  });

  testWidgets('fiche : disponibilité par tracker, ouverture sur son onglet',
      (tester) async {
    final c411 = _Tracker({'Film 1': [
      Release(tracker: Tracker.tr4ker, id: 'a', name: 'Film.1.2020.MULTi.2160p.WEB-DL-G',
          year: 2020, seeders: 12, isFreeleech: true, createdAt: DateTime(2026)),
      Release(tracker: Tracker.tr4ker, id: 'b', name: 'Film.1.2020.VFF.1080p.BluRay-G',
          year: 2020, seeders: 40, createdAt: DateTime(2026)),
    ]});
    final tr4ker = _Tracker({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tmdbProvider.overrideWithValue(_Tmdb()),
        wishlistStoreProvider.overrideWithValue(MemoryWishlistStore()),
        trackersProvider.overrideWithValue({Tracker.c411: c411, Tracker.tr4ker: tr4ker}),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: TitleDetailPage(title: _movie(1, '2020-05-01')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sur les trackers'), findsOneWidget);
    // Carte façon Transferts : état, puis infos à icônes et étiquettes.
    expect(find.text('2 sorties'), findsOneWidget);
    expect(find.text('2160p'), findsOneWidget);
    expect(find.text('VFF/MULTI'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('FL 1'), findsOneWidget);
    expect(find.text('Rien pour l’instant'), findsOneWidget, reason: 'tr4ker');

    // Le résumé tr4ker ouvre la recherche sur l'onglet tr4ker.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rien pour l’instant'));
    await tester.pumpAndSettle();
    expect(find.text('Rien sur tr4ker pour l’instant.'), findsOneWidget);
  });

  testWidgets('fiche d’un titre à venir : disponibilité à la demande',
      (tester) async {
    final c411 = _Tracker({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tmdbProvider.overrideWithValue(_Tmdb()),
        wishlistStoreProvider.overrideWithValue(MemoryWishlistStore()),
        trackersProvider.overrideWithValue({Tracker.c411: c411}),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: TitleDetailPage(title: _movie(1, '2099-05-01')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(c411.queries, isEmpty);
    await tester.tap(find.text('Vérifier la disponibilité'));
    await tester.pumpAndSettle();
    expect(c411.queries, isNotEmpty);
    expect(find.text('Rien pour l’instant'), findsOneWidget);
  });

  testWidgets('fiche : l’affiche se pose sur le bas de l’image de fond',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tmdbProvider.overrideWithValue(_Tmdb(backdrop: 'https://image.tmdb.org/t/p/w780/b.jpg')),
        wishlistStoreProvider.overrideWithValue(MemoryWishlistStore()),
        trackersProvider.overrideWithValue(const {}),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: TitleDetailPage(title: _movie(1, '2099-01-01')),
      ),
    ));
    await tester.pumpAndSettle();
    // Image : moitié de la largeur, plafonnée à 460 px ; l'affiche (180 px)
    // commence 130 px avant son bas.
    final title = tester.getTopLeft(find.text('Film 1').first);
    expect(title.dy, greaterThan(300));
    expect(tester.takeException(), isNull);
  });

  group('C411 (réponse réelle de /api/torrents)', () {
    final page = C411Api.parsePage(jsonDecode(
        File('test/fixtures/c411_torrents.json').readAsStringSync()) as Map<String, dynamic>);
    Release byId(String id) => page.items.firstWhere((r) => r.id == id);

    test('fiche, technique, langues', () {
      final r = byId('764970');
      expect((r.mediaKind, r.title, r.originalTitle, r.year),
          ('movie', 'Dune : Deuxième partie', 'Dune: Part Two', 2024));
      expect((r.resolution, r.source, r.hdrFormat, r.audioCodec, r.audioChannels),
          ('2160p', 'WEB-DL', 'DV.HDR10+', 'TrueHD Atmos', '7.1'));
      expect(r.languages, ['MULTI', 'VFF', 'VFQ', 'VF2', 'ANGLAIS']);
      expect(hdrLabel(r), 'DV · HDR10+');
      expect(hdrLabel(byId('764437')), isNull, reason: 'SDR');
      expect(byId('765388').mediaKind, isNull, reason: 'livre sans fiche');
      expect(byId('762568').mediaKind, 'game');
    });

    test('titre au format des noms de release', () {
      expect(releaseQueries('Dune : Deuxième partie'),
          ['Dune.Deuxieme.partie', 'Dune Deuxieme partie', 'Dune : Deuxième partie']);
      expect(releaseQueries("Journal d'une femme de chambre").first,
          'Journal.d.une.femme.de.chambre');
      expect(releaseQueries('Dune'), ['Dune'], reason: 'pas de doublon');
    });

    test('recherche « dune » : seules les sorties de la bonne fiche', () async {
      // C411 cherche un morceau du nom : « dune » remonte aussi un
      // documentaire, un livre, un jeu et Dune (2021).
      final api = _Tracker({'Dune.Deuxieme.partie': page.items});
      final dune2 = TmdbTitle(
          id: 693134, type: TmdbType.movie, title: 'Dune : Deuxième partie',
          originalTitle: 'Dune: Part Two', date: DateTime(2024, 2, 27));
      final found = await searchWish(api, dune2);
      expect(found.map((r) => r.id), ['764830', '764970']);
      expect(api.queries.first, 'Dune.Deuxieme.partie');

      final s = summarizeReleases(found);
      expect((s.bestQuality, s.hdr, s.atmos, s.maxSeeders), ('2160p', true, true, 60));

      // Série : le documentaire, par son titre original.
      final doc = await searchWish(_Tracker({'Chernobyl.Inside.the.Meltdown': page.items}),
          const TmdbTitle(id: 1, type: TmdbType.tv, title: 'Tchernobyl : dans le cœur',
              originalTitle: 'Chernobyl: Inside the Meltdown'));
      expect(doc.map((r) => r.id), ['766027']);
    });
  });

  testWidgets('Souhaits : sélecteur Ma liste / Découvrir bien visible', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tmdbProvider.overrideWithValue(_Tmdb()),
        wishlistStoreProvider.overrideWithValue(MemoryWishlistStore()),
        trackersProvider.overrideWithValue(const {}),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const WishlistPage(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.explore_rounded), findsOneWidget);
    expect(find.text('Au cinéma en France'), findsOneWidget, reason: 'liste vide : Découvrir');

    expect(find.text('Films et séries, sorties en France'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget, reason: 'Découvrir actif');
    await tester.tap(find.text('Ma liste'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pour les ajouter à ta liste'), findsOneWidget);

    // Pendant une recherche, toucher un segment l'efface.
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Découvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Au cinéma en France'), findsOneWidget);
    expect(find.text('dune'), findsNothing);
  });

  testWidgets('Souhaits : les deux boutons tiennent sur un petit téléphone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tmdbProvider.overrideWithValue(_Tmdb()),
        wishlistStoreProvider.overrideWithValue(MemoryWishlistStore()),
        trackersProvider.overrideWithValue(const {}),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const WishlistPage(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Découvrir'), findsOneWidget);
    expect(find.text('Ma liste'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Tmdb extends TmdbApi {
  _Tmdb({this.cast = const [TmdbPerson('Acteur A', role: 'Rôle')], this.backdrop})
      : super('k');
  final List<TmdbPerson> cast;
  final String? backdrop;

  @override
  Future<({List<TmdbTitle> items, int totalPages})> feed(TmdbFeed feed,
          {int page = 1}) async =>
      (items: [_movie(1, '2099-01-01').withRating(7.83, 1520)], totalPages: 1);

  @override
  Future<List<TmdbGenre>> genres(TmdbType type) async => const [TmdbGenre(28, 'Action')];

  @override
  Future<FrenchDates> frenchDates(int movieId) async =>
      FrenchDates(cinema: DateTime(2099, 2, 10));

  @override
  Future<TmdbDetails> details(TmdbTitle t) async => TmdbDetails(
        genres: const ['Action'],
        runtime: 125,
        cast: cast,
        backdropUrl: backdrop,
        recommendations: [_movie(2, '2099-01-01')],
        trailer: Uri.parse('https://www.youtube.com/watch?v=x'),
        french: FrenchDates(cinema: DateTime(2099, 2, 10)),
      );
}
