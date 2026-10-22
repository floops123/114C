import 'dart:convert';
import 'dart:typed_data';

import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/state/release_watch.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:c411_remote/ui/content_art.dart';
import 'package:c411_remote/ui/release_watch_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tracker sans réseau : renvoie [items] (modifiable entre deux relevés).
class _Fake implements TrackerApi {
  _Fake(this.tracker, [List<Release>? items]) : items = items ?? [];
  @override
  final Tracker tracker;
  List<Release> items;
  String? failure;
  final sorts_ = <ReleaseSort>[];

  @override
  void close() {}
  @override
  List<ReleaseSort> get sorts => const [ReleaseSort.date];
  @override
  Set<ReleaseSort> get serverSorts => const {};
  @override
  Future<List<Category>> categories() async => const [];
  @override
  Future<ReleasePage> releases(
      {int page = 1,
      int perPage = 50,
      int? categoryId,
      int? subcategoryId,
      String query = '',
      ReleaseSort sort = ReleaseSort.date,
      bool ascending = false}) async {
    sorts_.add(sort);
    if (failure != null) throw TrackerException(failure!);
    return ReleasePage(items, 1, 1, items.length);
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async => Uint8List(0);
}

class _Torrents extends TorrentsNotifier {
  @override
  TorrentsState build() => const TorrentsState(loaded: true);
}

/// Transmission qui note les ajouts.
class _Transmission extends TransmissionClient {
  _Transmission() : super(url: 'http://x');
  int added = 0;
  @override
  Future<bool> addTorrent(
      {Uint8List? metainfo, String? filename, AddOptions options = const AddOptions()}) async {
    added++;
    return true;
  }

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async =>
      (torrents: <Map<String, dynamic>>[], removed: <int>[]);
}

class _Notifier implements SystemNotifier {
  final shown = <(String, String)>[];
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> show(String title, String body) async => shown.add((title, body));
}

Release _r(Tracker t, String id, {int day = 1}) => Release(
      tracker: t,
      id: id,
      name: 'Release.$id.1080p',
      size: 1000,
      createdAt: DateTime(2026, 10, day),
    );

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Harness {
  _Harness(Map<Tracker, TrackerApi> trackers) {
    container = ProviderContainer(overrides: [
      trackersProvider.overrideWithValue(trackers),
      watchStoreProvider.overrideWithValue(store),
      systemNotifierProvider.overrideWithValue(notifications),
      watchClockProvider.overrideWithValue(() => now),
    ]);
    container.listen(releaseWatchProvider, (_, _) {});
  }

  late final ProviderContainer container;
  final store = MemoryWatchStore();
  final notifications = _Notifier();
  DateTime now = DateTime(2026, 10, 21, 12);

  ReleaseWatchNotifier get notifier =>
      container.read(releaseWatchProvider.notifier);
  WatchState get state => container.read(releaseWatchProvider);
  void configure(WatchConfig c) =>
      container.read(watchConfigProvider.notifier).set(c);
}

void main() {
  test('premier relevé : la liste se remplit sans rien signaler', () async {
    final tr4ker = _Fake(Tracker.tr4ker, [_r(Tracker.tr4ker, 'a')]);
    final h = _Harness({Tracker.tr4ker: tr4ker});
    addTearDown(h.container.dispose);

    expect(await h.notifier.check(), 0);
    expect(h.state.items.single.release.id, 'a');
    expect(h.state.unseen, 0);
    expect(h.notifications.shown, isEmpty);
    expect(tr4ker.sorts_, [ReleaseSort.date]);
    expect(h.store.data.lastCheck, h.now);
  });

  test('relevé suivant : les nouvelles sorties, en tête et notifiées',
      () async {
    final tr4ker = _Fake(Tracker.tr4ker, [_r(Tracker.tr4ker, 'a')]);
    final h = _Harness({Tracker.tr4ker: tr4ker});
    addTearDown(h.container.dispose);
    await h.notifier.check();

    tr4ker.items = [
      _r(Tracker.tr4ker, 'c', day: 3),
      _r(Tracker.tr4ker, 'b', day: 2),
      _r(Tracker.tr4ker, 'a'),
    ];
    expect(await h.notifier.check(), 2);
    expect(h.state.items.map((i) => i.release.id), ['c', 'b', 'a']);
    expect(h.state.unseen, 2);
    final (title, body) = h.notifications.shown.single;
    expect(title, '2 nouveaux torrents sur ${Tracker.tr4ker.label}');
    expect(body, 'Release.c.1080p\nRelease.b.1080p');

    // Rien de neuf : pas de notification.
    expect(await h.notifier.check(), 0);
    expect(h.notifications.shown, hasLength(1));
  });

  test('notifications désactivées : la liste suit, sans notification',
      () async {
    final tr4ker = _Fake(Tracker.tr4ker, [_r(Tracker.tr4ker, 'a')]);
    final h = _Harness({Tracker.tr4ker: tr4ker});
    addTearDown(h.container.dispose);
    h.configure(const WatchConfig(notify: false));
    await h.notifier.check();
    tr4ker.items = [_r(Tracker.tr4ker, 'b'), ...tr4ker.items];
    expect(await h.notifier.check(), 1);
    expect(h.notifications.shown, isEmpty);
  });

  test('seuls les trackers choisis sont relevés', () async {
    final c411 = _Fake(Tracker.c411, [_r(Tracker.c411, '1')]);
    final tr4ker = _Fake(Tracker.tr4ker, [_r(Tracker.tr4ker, 'a')]);
    final h = _Harness({Tracker.c411: c411, Tracker.tr4ker: tr4ker});
    addTearDown(h.container.dispose);
    h.configure(const WatchConfig(trackers: {Tracker.c411}));
    await h.notifier.check();
    expect(c411.sorts_, hasLength(1));
    expect(tr4ker.sorts_, isEmpty);
    expect(h.state.items.map((i) => i.release.tracker), [Tracker.c411]);
  });

  test('un tracker en échec n’empêche pas les autres', () async {
    final c411 = _Fake(Tracker.c411)..failure = 'Clé API C411 refusée';
    final tr4ker = _Fake(Tracker.tr4ker, [_r(Tracker.tr4ker, 'a')]);
    final h = _Harness({Tracker.c411: c411, Tracker.tr4ker: tr4ker});
    addTearDown(h.container.dispose);
    await h.notifier.check();
    expect(h.state.errors, {Tracker.c411: 'Clé API C411 refusée'});
    expect(h.state.items, hasLength(1));

    // C411 répond enfin : premier relevé réussi, donc rien de « nouveau ».
    c411
      ..failure = null
      ..items = [_r(Tracker.c411, '1')];
    expect(await h.notifier.check(), 0);
    expect(h.state.errors, isEmpty);
    expect(h.state.items, hasLength(2));
  });

  test('vu, vidé : rien ne revient comme nouveau', () async {
    final tr4ker = _Fake(Tracker.tr4ker, [_r(Tracker.tr4ker, 'a')]);
    final h = _Harness({Tracker.tr4ker: tr4ker});
    addTearDown(h.container.dispose);
    await h.notifier.check();
    tr4ker.items = [_r(Tracker.tr4ker, 'b'), _r(Tracker.tr4ker, 'a')];
    await h.notifier.check();
    expect(h.state.unseen, 1);

    h.notifier.markAllSeen();
    expect(h.state.unseen, 0);
    expect(h.store.data.items.where((i) => i.isNew), isEmpty);

    h.notifier.clear();
    expect(h.state.items, isEmpty);
    expect(await h.notifier.check(), 0);
    expect(h.state.items, isEmpty);
  });

  test('veille active : relevé à l’ouverture, puis selon l’intervalle',
      () async {
    final tr4ker = _Fake(Tracker.tr4ker, [_r(Tracker.tr4ker, 'a')]);
    final h = _Harness({Tracker.tr4ker: tr4ker});
    addTearDown(h.container.dispose);
    h.configure(const WatchConfig(enabled: true, minutes: 30));
    h.container.read(releaseWatchProvider);
    await _settle();
    expect(tr4ker.sorts_, hasLength(1), reason: 'relevé immédiat');

    expect(h.notifier.isDue(h.now.add(const Duration(minutes: 29))), isFalse);
    expect(h.notifier.isDue(h.now.add(const Duration(minutes: 30))), isTrue);

    // Changer l'intervalle ne relance pas un relevé qui n'est pas dû.
    h.configure(const WatchConfig(enabled: true, minutes: 60));
    h.container.read(releaseWatchProvider);
    await _settle();
    expect(tr4ker.sorts_, hasLength(1));

    // Relevé dû (relancement de l'application plus tard) : refait.
    h.now = h.now.add(const Duration(hours: 2));
    h.configure(const WatchConfig(enabled: true, minutes: 15));
    h.container.read(releaseWatchProvider);
    await _settle();
    expect(tr4ker.sorts_, hasLength(2));
  });

  test('veille inactive : aucun relevé automatique', () async {
    final tr4ker = _Fake(Tracker.tr4ker, [_r(Tracker.tr4ker, 'a')]);
    final h = _Harness({Tracker.tr4ker: tr4ker});
    addTearDown(h.container.dispose);
    h.container.read(releaseWatchProvider);
    await _settle();
    expect(tr4ker.sorts_, isEmpty);
  });

  test('sérialisation : réglages et données', () {
    const config = WatchConfig(
        enabled: true, minutes: 60, trackers: {Tracker.c411}, notify: false);
    final back = WatchConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>);
    expect(back.enabled, isTrue);
    expect(back.minutes, 60);
    expect(back.trackers, {Tracker.c411});
    expect(back.notify, isFalse);
    expect(WatchConfig.fromJson(const {}).trackers, isNull,
        reason: 'par défaut : tous les trackers');

    final data = WatchData(
      items: [
        WatchedRelease(
          release: Release(
            tracker: Tracker.tr4ker,
            id: '7',
            name: 'X.2026.1080p',
            downloadUrl: 'https://x/dl/7',
            categories: const ['Movies/HD'],
            mediaKind: 'movie',
            size: 42,
            seeders: 3,
            createdAt: DateTime.utc(2026, 10, 20),
          ),
          foundAt: DateTime.utc(2026, 10, 21),
        ),
      ],
      known: const ['tr4ker:7'],
      baselined: const {Tracker.tr4ker},
      lastCheck: DateTime.utc(2026, 10, 21),
    );
    final d = WatchData.fromJson(
        jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
    final r = d.items.single.release;
    expect(r.id, '7');
    expect(r.downloadUrl, 'https://x/dl/7');
    expect(r.categories, ['Movies/HD']);
    expect(r.seeders, 3);
    expect(r.createdAt, DateTime.utc(2026, 10, 20));
    expect(d.items.single.isNew, isTrue);
    expect(d.items.single.release.mediaKind, 'movie', reason: 'type C411 conservé');
    expect(d.known, ['tr4ker:7']);
    expect(d.baselined, {Tracker.tr4ker});
    expect(d.lastCheck, DateTime.utc(2026, 10, 21));
  });

  test('texte des notifications', () {
    WatchedRelease w(Tracker t, String id) =>
        WatchedRelease(release: _r(t, id), foundAt: DateTime(2026));
    expect(notificationTitle([w(Tracker.c411, '1')]),
        'Nouveau torrent sur ${Tracker.c411.label}');
    expect(notificationTitle([w(Tracker.c411, '1'), w(Tracker.tr4ker, 'a')]),
        '2 nouveaux torrents');
    final many = [for (var i = 0; i < 6; i++) w(Tracker.c411, '$i')];
    expect(notificationBody(many).split('\n'), hasLength(5));
    expect(notificationBody(many), endsWith('et 2 autres…'));
  });

  testWidgets('page Nouveautés : liste, nouveautés vues à l’ouverture, '
      'réglages', (tester) async {
    final tr4ker = _Fake(Tracker.tr4ker, [_r(Tracker.tr4ker, 'a')]);
    final h = _Harness({Tracker.tr4ker: tr4ker});
    addTearDown(h.container.dispose);
    await tester.runAsync(() async {
      await h.notifier.check();
      tr4ker.items = [_r(Tracker.tr4ker, 'b'), _r(Tracker.tr4ker, 'a')];
      await h.notifier.check();
    });
    expect(h.state.unseen, 1);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: h.container,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const ReleaseWatchPage(),
      ),
    ));
    await tester.pump();
    expect(find.text('Release.b.1080p'), findsOneWidget);
    expect(find.text('Release.a.1080p'), findsOneWidget);
    // Signalée le temps de la visite, mais déjà marquée comme vue.
    expect(find.text('NOUVEAU'), findsOneWidget);
    expect(h.state.unseen, 0);

    // Veille désactivée : réglages dépliés ; on l'active depuis la page.
    expect(find.text('Veille désactivée'), findsOneWidget);
    await tester.tap(find.text('Vérifier les nouveaux torrents'));
    await tester.pump();
    expect(h.container.read(watchConfigProvider).enabled, isTrue);

    // Décocher le seul tracker : plus rien n'est surveillé.
    await tester.tap(find.widgetWithText(FilterChip, Tracker.tr4ker.label));
    await tester.pump();
    expect(h.container.read(watchConfigProvider).trackers, isEmpty);
    expect(find.text('Aucun tracker surveillé'), findsOneWidget);
  });

  test('libellé de catégorie : catégorie › sous-catégorie, Torznab, type', () {
    Release r(String sub, List<String> cats) => Release(
        tracker: Tracker.c411, id: '1', name: 'X', subcategory: sub, categories: cats,
        createdAt: DateTime(2026));
    expect(categoryLabel(r('Windows', ['Jeux Vidéo', 'Windows']), ContentKind.game),
        'Jeux Vidéo › Windows');
    expect(categoryLabel(r('', ['Movies', 'Movies/HD']), ContentKind.movie), 'Movies/HD');
    expect(categoryLabel(r('Film', const []), ContentKind.movie), 'Film');
    expect(categoryLabel(r('', const []), ContentKind.book), 'Livre');
  });

  testWidgets('Nouveautés : filtre par type de contenu', (tester) async {
    Release r(String id, String sub, List<String> cats) => Release(
        tracker: Tracker.c411, id: id, name: 'R$id', subcategory: sub, categories: cats,
        createdAt: DateTime(2026));
    final store = MemoryWatchStore()
      ..data = WatchData(items: [
        for (final rel in [
          r('1', 'Film', ['Films & Vidéos', 'Film']),
          r('2', 'Windows', ['Jeux Vidéo', 'Windows']),
          r('3', 'Série TV', ['Films & Vidéos', 'Série TV']),
        ])
          WatchedRelease(release: rel, foundAt: DateTime(2026), isNew: false),
      ]);
    final container = ProviderContainer(overrides: [
      trackersProvider.overrideWithValue(const {}),
      watchStoreProvider.overrideWithValue(store),
      systemNotifierProvider.overrideWithValue(_Notifier()),
    ]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const ReleaseWatchPage()),
    ));
    await tester.pump();
    expect(find.text('R1'), findsOneWidget);
    expect(find.text('JEUX VIDÉO › WINDOWS'), findsOneWidget);
    await tester.tap(find.text('Jeu vidéo · 1'));
    await tester.pump();
    expect(find.text('R2'), findsOneWidget);
    expect(find.text('R1'), findsNothing);
    expect(find.text('R3'), findsNothing);
    await tester.tap(find.text('Tout · 3'));
    await tester.pump();
    expect(find.text('R3'), findsOneWidget);
  });

  testWidgets('Nouveautés : sélection multiple et ajout groupé', (tester) async {
    final store = MemoryWatchStore()
      ..data = WatchData(items: [
        for (final id in ['1', '2', '3'])
          WatchedRelease(release: _r(Tracker.c411, id), foundAt: DateTime(2026), isNew: false),
      ]);
    final transmission = _Transmission();
    final container = ProviderContainer(overrides: [
      trackersProvider.overrideWithValue({Tracker.c411: _Fake(Tracker.c411)}),
      watchStoreProvider.overrideWithValue(store),
      systemNotifierProvider.overrideWithValue(_Notifier()),
      transmissionProvider.overrideWithValue(transmission),
      torrentsProvider.overrideWith(_Torrents.new),
    ]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const ReleaseWatchPage()),
    ));
    await tester.pump();

    await tester.longPress(find.text('Release.1.1080p'));
    await tester.pump();
    expect(find.text('1 sélectionnée'), findsOneWidget);
    await tester.tap(find.text('Release.2.1080p'));
    await tester.pump();
    expect(find.text('2 sélectionnées'), findsOneWidget);
    await tester.tap(find.byTooltip('Tout sélectionner'));
    await tester.pump();
    expect(find.text('3 sélectionnées'), findsOneWidget);

    await tester.tap(find.byTooltip('Envoyer à Transmission'));
    await tester.pumpAndSettle();
    expect(transmission.added, 3);
    expect(find.text('3 ajoutés à Transmission'), findsOneWidget);
    // Sélection refermée après l'envoi.
    expect(find.text('Nouveautés'), findsOneWidget);
  });
}
