import 'dart:io';
import 'dart:typed_data';

import 'package:c411_remote/api/c411.dart';
import 'package:c411_remote/api/quota.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/bulk_import.dart';
import 'package:c411_remote/state/palliative.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _hash = '3751970ab74f645dbe7902d3c27399c94518ce22';
final _torrent = Uint8List.fromList('d4:infod4:name1:xee'.codeUnits);

/// Sortie C411 renvoyée par la recherche ; le téléchargement par la clé API
/// est compté, pour savoir quelle voie a servi.
class _C411 implements TrackerApi {
  var byApiKey = 0;
  @override
  Tracker get tracker => Tracker.c411;
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
          bool ascending = false}) async =>
      ReleasePage([
        Release(
            tracker: Tracker.c411,
            id: '1',
            name: 'X',
            infoHash: _hash,
            createdAt: DateTime(2026)),
      ], 1, 1, 1);
  @override
  Future<Uint8List> downloadTorrent(Release release) async {
    byApiKey++;
    return _torrent;
  }
}

class _Transmission extends TransmissionClient {
  _Transmission() : super(url: 'http://x');
  final added = <Uint8List>[];
  @override
  Future<({bool added, String? hash})> addTorrentWithHash({
    Uint8List? metainfo,
    String? filename,
    AddOptions options = const AddOptions(),
  }) async {
    added.add(metainfo!);
    return (added: true, hash: _hash);
  }

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields,
          {Object? ids}) async =>
      (torrents: <Map<String, dynamic>>[], removed: <int>[]);
}

class _Torrents extends TorrentsNotifier {
  @override
  TorrentsState build() => const TorrentsState(loaded: true);
}

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

void main() {
  late HttpServer server;
  late List<HttpRequest> requests;
  late int status;
  late RequestQuota saved;

  setUp(() async {
    requests = [];
    status = 200;
    // Pas d'espacement de 3 s entre téléchargements pendant les tests.
    saved = trackerQuotas[Tracker.c411]!;
    trackerQuotas[Tracker.c411] = RequestQuota(100);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add(req);
      req.response.statusCode = status;
      if (req.uri.path == '/api/torrents') {
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"data": [], "meta": {}}');
      } else {
        req.response.add(status == 200 ? _torrent : 'refusé'.codeUnits);
      }
      await req.response.close();
    });
  });
  tearDown(() async {
    trackerQuotas[Tracker.c411] = saved;
    await server.close(force: true);
  });

  C411SiteApi site() => C411SiteApi('session=abc',
      baseUrl: 'http://127.0.0.1:${server.port}');

  Release release({String? hash = _hash}) => Release(
      tracker: Tracker.c411, id: '1', name: 'X', infoHash: hash,
      createdAt: DateTime(2026));

  group('C411SiteApi.downloadTorrent', () {
    test('par le site, avec le cookie de session', () async {
      final api = site();
      addTearDown(api.close);
      expect(await api.downloadTorrent(release()), _torrent);
      final req = requests.single;
      expect(req.uri.path, '/api/torrents/$_hash/download');
      expect(req.headers.value('cookie'), 'session=abc');
      expect(req.uri.queryParameters, isEmpty, reason: 'pas de clé API');
    });

    test('pas d’espacement entre téléchargements par le cookie', () async {
      final slept = <Duration>[];
      var now = DateTime(2026);
      trackerQuotas[Tracker.c411] = RequestQuota(100,
          downloadSpacing: const Duration(seconds: 3),
          clock: () => now,
          sleep: (d) async {
            slept.add(d);
            now = now.add(d);
          });
      final api = site();
      addTearDown(api.close);
      for (var i = 0; i < 3; i++) {
        await api.downloadTorrent(release());
      }
      expect(requests, hasLength(3));
      expect(slept, isEmpty);
    });

    test('budget du cookie (200 / min), pas celui de la clé API', () async {
      expect(c411SessionQuota.limit, 200);
      // Budget de la clé API bloqué : s'il servait, le test échouerait.
      trackerQuotas[Tracker.c411] = RequestQuota(100,
          sleep: (_) async => throw StateError('budget de la clé API utilisé'))
        ..pause(const Duration(hours: 1));
      final api = site();
      addTearDown(api.close);
      for (var i = 0; i < 5; i++) {
        await api.downloadTorrent(release());
      }
      await api.palliative();
      expect(requests, hasLength(6));
    });

    test('cookie refusé : message explicite', () async {
      status = 403;
      final api = site();
      addTearDown(api.close);
      await expectLater(
          api.downloadTorrent(release()),
          throwsA(isA<TrackerException>()
              .having((e) => e.message, 'message', contains('Cookie'))));
    });

    test('sortie sans infohash : refusée sans requête', () async {
      final api = site();
      addTearDown(api.close);
      await expectLater(api.downloadTorrent(release(hash: null)),
          throwsA(isA<TrackerException>()));
      expect(requests, isEmpty);
    });
  });

  group('import en masse', () {
    Future<(_C411, _Transmission)> sendWith(C411SiteApi? cookie) async {
      final c411 = _C411();
      final transmission = _Transmission();
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith(_Settings.new),
        trackersProvider.overrideWithValue({Tracker.c411: c411}),
        transmissionProvider.overrideWithValue(transmission),
        torrentsProvider.overrideWith(_Torrents.new),
        c411SiteApiProvider.overrideWithValue(cookie),
      ]);
      addTearDown(container.dispose);
      container.listen(bulkImportProvider, (_, _) {});
      final notifier = container.read(bulkImportProvider.notifier);
      notifier.search();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(await notifier.send(), 1);
      return (c411, transmission);
    }

    test('C411 avec cookie : .torrent pris sur le site', () async {
      final api = site();
      addTearDown(api.close);
      final (c411, transmission) = await sendWith(api);
      expect(requests.single.uri.path, '/api/torrents/$_hash/download');
      expect(c411.byApiKey, 0);
      expect(transmission.added.single, _torrent);
    });

    test('C411 sans cookie : par la clé API, comme avant', () async {
      final (c411, transmission) = await sendWith(null);
      expect(requests, isEmpty);
      expect(c411.byApiKey, 1);
      expect(transmission.added.single, _torrent);
    });
  });
}
