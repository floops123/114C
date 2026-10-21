import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:c411_remote/api/astra.dart';
import 'package:c411_remote/api/c411.dart';
import 'package:c411_remote/api/torznab.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/state/bulk_import.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `caps` et `search` d'un indexeur Torznab, servis en local. Le film n'a pas
/// de motif de série dans son nom : `ReleaseName.kind` est vide, seule la
/// catégorie Torznab dit que c'est un film en HD.
const _caps = '''<?xml version="1.0" encoding="UTF-8"?>
<caps>
  <categories>
    <category id="2000" name="Movies">
      <subcat id="2040" name="Movies/HD"/>
      <subcat id="2045" name="Movies/UHD"/>
    </category>
    <category id="5000" name="TV">
      <subcat id="5040" name="TV/HD"/>
    </category>
  </categories>
</caps>''';

const _search = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:torznab="http://torznab.com/schemas/2015/feed">
  <channel>
    <torznab:response offset="0" total="2"/>
    <item>
      <title>Matrix.1999.MULTI.1080p.BluRay.x264-NoTag</title>
      <guid>1</guid>
      <size>1000</size>
      <category>2040</category>
      <torznab:attr name="category" value="2000"/>
      <torznab:attr name="category" value="2040"/>
      <torznab:attr name="seeders" value="5"/>
    </item>
    <item>
      <title>Show.S01E01.1080p.WEB.x264-NoTag</title>
      <guid>2</guid>
      <size>1000</size>
      <torznab:attr name="category" value="5040"/>
      <torznab:attr name="seeders" value="5"/>
    </item>
  </channel>
</rss>''';

/// Tracker sans réseau dont la réponse peut échouer.
class _Fake implements TrackerApi {
  _Fake(this.tracker, {this.cats = const [], this.failure});
  @override
  final Tracker tracker;
  final List<Category> cats;
  String? failure;
  final asked = <(int?, int?)>[];

  @override
  void close() {}
  @override
  List<ReleaseSort> get sorts => const [ReleaseSort.date];
  @override
  Set<ReleaseSort> get serverSorts => const {};
  @override
  Future<List<Category>> categories() async => cats;
  @override
  Future<ReleasePage> releases(
      {int page = 1,
      int perPage = 50,
      int? categoryId,
      int? subcategoryId,
      String query = '',
      ReleaseSort sort = ReleaseSort.date,
      bool ascending = false}) async {
    asked.add((categoryId, subcategoryId));
    if (failure != null) throw TrackerException(failure!);
    return const ReleasePage([], 1, 1, 0);
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async => Uint8List(0);
}

/// Liste des trackers modifiable pendant le test.
class _Trackers extends Notifier<Map<Tracker, TrackerApi>> {
  @override
  Map<Tracker, TrackerApi> build() => const {};
  void set(Map<Tracker, TrackerApi> value) => state = value;
}

final _trackers =
    NotifierProvider<_Trackers, Map<Tracker, TrackerApi>>(_Trackers.new);

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('Torznab : catégories du caps sur les sorties', () {
    late HttpServer server;
    late List<String> calls;
    late bool capsFails;

    setUp(() async {
      calls = [];
      capsFails = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final t = req.uri.queryParameters['t']!;
        calls.add(t);
        req.response.headers.contentType = ContentType('application', 'xml');
        req.response.write(t != 'caps'
            ? _search
            : capsFails
                ? '<error code="900" description="indisponible"/>'
                : _caps);
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    test('un film rangé dans « Movies/HD » le sait', () async {
      final api = TorznabApi(Tracker.tr4ker, 'KEY',
          baseUrl: 'http://127.0.0.1:${server.port}/api');
      addTearDown(api.close);
      final page = await api.releases();
      final film = page.items.first;
      // Le nom seul ne dit rien : avant, le filtre comparait ce champ vide
      // aux noms du caps et rejetait toutes les sorties Torznab.
      expect(film.subcategory, '');
      expect(film.categories, unorderedEquals(['Movies/HD', 'Movies']));
      expect(page.items.last.categories, ['TV/HD']);

      // Le caps n'est demandé qu'une fois.
      await api.releases(page: 2);
      expect(calls.where((c) => c == 'caps'), hasLength(1));
      expect(calls.where((c) => c == 'search'), hasLength(2));
    });

    test('caps en échec : les sorties arrivent quand même, sans catégories',
        () async {
      capsFails = true;
      final api = TorznabApi(Tracker.tr4ker, 'KEY',
          baseUrl: 'http://127.0.0.1:${server.port}/api');
      addTearDown(api.close);
      final page = await api.releases();
      expect(page.items, hasLength(2));
      expect(page.items.first.categories, isEmpty);

      // Retenté à l'appel suivant.
      capsFails = false;
      final again = await api.releases();
      expect(again.items.first.categories, unorderedEquals(['Movies/HD', 'Movies']));
      expect(calls.where((c) => c == 'caps'), hasLength(2));
    });
  });

  test('C411 : catégorie et sous-catégorie', () {
    final page = C411Api.parsePage(jsonDecode(
            File('test/fixtures/c411_torrents.json').readAsStringSync())
        as Map<String, dynamic>);
    final dune = page.items.firstWhere((r) => r.subcategory == 'Film');
    expect(dune.categories, ['Films & Vidéos', 'Film']);
  });

  test('AstraTorrent : catégorie du site', () {
    final items = AstraApi.parseTorrents(
        File('test/fixtures/astra_torrents.json').readAsStringSync(), 'P');
    expect(items.first.categories, ['Films']);
  });

  group('notifier', () {
    const c411Cats = [
      Category(1, 'Films & Vidéos', [Subcategory(6, 'Film'), Subcategory(7, 'Série')]),
    ];
    const astraCats = [Category(1, 'Films', []), Category(2, 'Séries', [])];

    test('les catégories sont celles du tracker choisi ; en changer vide la '
        'sélection', () async {
      final container = ProviderContainer(overrides: [
        trackersProvider.overrideWithValue({
          Tracker.c411: _Fake(Tracker.c411, cats: c411Cats),
          Tracker.astra: _Fake(Tracker.astra, cats: astraCats),
        }),
      ]);
      addTearDown(container.dispose);
      container.listen(bulkImportProvider, (_, _) {});
      await _settle();
      var state = container.read(bulkImportProvider);
      expect(state.criteria.tracker, Tracker.c411, reason: 'le premier');
      expect(state.categories, c411Cats);
      expect(state.loadingCategories, isFalse);

      final notifier = container.read(bulkImportProvider.notifier);
      notifier.update(const BulkCriteria(
          categories: {(category: 1, subcategory: 6)}));
      expect(container.read(bulkImportProvider).criteria.tracker, Tracker.c411,
          reason: 'update() sans tracker garde le tracker courant');

      notifier.selectTracker(Tracker.astra);
      await _settle();
      state = container.read(bulkImportProvider);
      expect(state.criteria.tracker, Tracker.astra);
      expect(state.criteria.categories, isEmpty,
          reason: 'les identifiants de C411 ne veulent rien dire chez Astra');
      expect(state.categories, astraCats);
    });

    test('tracker retiré des Réglages : on passe à un autre', () async {
      final container = ProviderContainer(overrides: [
        trackersProvider.overrideWith((ref) => ref.watch(_trackers)),
      ]);
      addTearDown(container.dispose);
      container.listen(bulkImportProvider, (_, _) {});
      await _settle();
      expect(container.read(bulkImportProvider).criteria.tracker, isNull);

      container.read(_trackers.notifier).set({
        Tracker.c411: _Fake(Tracker.c411, cats: c411Cats),
      });
      container.read(bulkImportProvider);
      await _settle();
      expect(container.read(bulkImportProvider).criteria.tracker, Tracker.c411);
      expect(container.read(bulkImportProvider).categories, c411Cats);

      container.read(_trackers.notifier).set({
        Tracker.astra: _Fake(Tracker.astra, cats: astraCats),
      });
      container.read(bulkImportProvider);
      await _settle();
      expect(container.read(bulkImportProvider).criteria.tracker, Tracker.astra);
      expect(container.read(bulkImportProvider).categories, astraCats);
    });

    test('catégories cochées : une requête par catégorie, avec les '
        'identifiants du tracker', () async {
      final c411 = _Fake(Tracker.c411, cats: c411Cats);
      final container = ProviderContainer(overrides: [
        trackersProvider.overrideWithValue({Tracker.c411: c411}),
      ]);
      addTearDown(container.dispose);
      container.listen(bulkImportProvider, (_, _) {});
      final notifier = container.read(bulkImportProvider.notifier);

      notifier.search();
      await _settle();
      expect(c411.asked, [(null, null)], reason: 'aucune cochée : tout');

      c411.asked.clear();
      notifier.update(const BulkCriteria(categories: {
        (category: 1, subcategory: 6),
        (category: 1, subcategory: 7),
      }));
      notifier.search();
      await _settle();
      expect(c411.asked, unorderedEquals([(1, 6), (1, 7)]));
    });

    test('erreur du tracker affichée, puis effacée à la recherche suivante',
        () async {
      final c411 = _Fake(Tracker.c411, failure: 'Clé API C411 refusée');
      final container = ProviderContainer(overrides: [
        trackersProvider.overrideWithValue({Tracker.c411: c411}),
      ]);
      addTearDown(container.dispose);
      container.listen(bulkImportProvider, (_, _) {});
      final notifier = container.read(bulkImportProvider.notifier);

      notifier.search();
      await _settle();
      expect(container.read(bulkImportProvider).error, 'Clé API C411 refusée');

      c411.failure = 'délai dépassé';
      notifier.search();
      expect(container.read(bulkImportProvider).error, isNull);
      await _settle();
      expect(container.read(bulkImportProvider).error,
          '${Tracker.c411.label} : délai dépassé');

      c411.failure = null;
      notifier.search();
      await _settle();
      expect(container.read(bulkImportProvider).error, isNull);
    });
  });
}
