import 'dart:io';

import 'package:c411_remote/api/quota.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Horloge simulée : dormir avance le temps.
class _Clock {
  DateTime now = DateTime.utc(2026, 10, 21, 12);
  final slept = <Duration>[];

  Future<void> sleep(Duration d) async {
    slept.add(d);
    now = now.add(d);
  }

  RequestQuota quota(int limit, {Duration spacing = Duration.zero}) =>
      RequestQuota(limit,
          clock: () => now, sleep: sleep, downloadSpacing: spacing);
}

void main() {
  group('RequestQuota', () {
    test('sous la limite : les requêtes partent sans attendre', () async {
      final clock = _Clock();
      final quota = clock.quota(3);
      await Future.wait([quota.acquire(), quota.acquire(), quota.acquire()]);
      expect(clock.slept, isEmpty);
    });

    test('au-delà : on attend que la plus ancienne sorte de la fenêtre',
        () async {
      final clock = _Clock();
      final quota = clock.quota(2);
      await quota.acquire();
      clock.now = clock.now.add(const Duration(seconds: 20));
      await quota.acquire();
      final waits = <DateTime?>[];
      quota.waitingUntil.addListener(() => waits.add(quota.waitingUntil.value));

      await quota.acquire();
      // La première est partie à t0 : la troisième attend t0 + 60 s.
      expect(clock.slept, [const Duration(seconds: 40)]);
      expect(waits.first, isNotNull);
      expect(quota.waitingUntil.value, isNull, reason: 'attente finie');
    });

    test('fenêtre glissante : une minute plus tard, tout est libre', () async {
      final clock = _Clock();
      final quota = clock.quota(2);
      await quota.acquire();
      await quota.acquire();
      clock.now = clock.now.add(const Duration(minutes: 1));
      await quota.acquire();
      await quota.acquire();
      expect(clock.slept, isEmpty);
    });

    test('servies dans l’ordre d’arrivée', () async {
      final clock = _Clock();
      final quota = clock.quota(1);
      final order = <int>[];
      await Future.wait([
        for (var i = 0; i < 4; i++) quota.acquire().then((_) => order.add(i)),
      ]);
      expect(order, [0, 1, 2, 3]);
      expect(clock.slept, hasLength(3));
    });

    test('téléchargements espacés, sans bandeau ; le reste n’attend pas',
        () async {
      final clock = _Clock();
      final quota = clock.quota(100, spacing: const Duration(seconds: 3));
      final waits = <DateTime?>[];
      quota.waitingUntil.addListener(() => waits.add(quota.waitingUntil.value));
      await quota.acquire(download: true);
      await quota.acquire(); // une recherche passe tout de suite
      await quota.acquire(download: true);
      expect(clock.slept, [const Duration(seconds: 3)]);
      clock.now = clock.now.add(const Duration(seconds: 10));
      await quota.acquire(download: true);
      expect(clock.slept, hasLength(1), reason: 'écart déjà écoulé');
      expect(waits.whereType<DateTime>(), isEmpty);
    });

    test('pause après un refus : rien ne part avant la fin', () async {
      final clock = _Clock();
      final quota = clock.quota(100);
      quota.pause(const Duration(seconds: 30));
      quota.pause(const Duration(seconds: 5)); // plus courte : ignorée
      await quota.acquire();
      expect(clock.slept, [const Duration(seconds: 30)]);
    });
  });

  group('Retry-After', () {
    Headers h(String v) => Headers.fromMap({
          'retry-after': [v],
        });

    test('en secondes', () {
      expect(retryAfter(h('12')), const Duration(seconds: 12));
    });

    test('en date HTTP', () {
      final now = DateTime.utc(2026, 10, 21, 12);
      expect(retryAfter(h('Wed, 21 Oct 2026 12:00:45 GMT'), now: now),
          const Duration(seconds: 45));
    });

    test('répété : le plus long délai lisible, sans exception', () {
      final headers = Headers.fromMap({
        'retry-after': ['5', 'n’importe quoi', '30'],
      });
      expect(retryAfter(headers), const Duration(seconds: 30));
      expect(retryAfter(Headers.fromMap({'retry-after': ['7, 9']})),
          const Duration(seconds: 9));
    });

    test('absent ou illisible', () {
      expect(retryAfter(Headers()), isNull);
      expect(retryAfter(h('bientôt')), isNull);
    });
  });

  group('requêtes réelles', () {
    late HttpServer server;
    late List<int> statuses;
    late RequestQuota saved;
    late _Clock clock;
    var doubleRetryAfter = false;

    setUp(() async {
      clock = _Clock();
      doubleRetryAfter = false;
      saved = trackerQuotas[Tracker.tr4ker]!;
      trackerQuotas[Tracker.tr4ker] =
          clock.quota(100, spacing: const Duration(seconds: 2));
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final status = statuses.removeAt(0);
        req.response.statusCode = status;
        if (status == 429) {
          req.response.headers.add('Retry-After', '7');
          if (doubleRetryAfter) req.response.headers.add('Retry-After', '9');
        }
        req.response.write('ok');
        await req.response.close();
      });
    });
    tearDown(() async {
      trackerQuotas[Tracker.tr4ker] = saved;
      await server.close(force: true);
    });

    Dio dio() => trackerDio(baseUrl: 'http://127.0.0.1:${server.port}');

    test('429 : on attend le délai demandé puis on réessaie', () async {
      statuses = [429, 200];
      final res = await trackerGet<String>(dio(), Tracker.tr4ker, '/',
          type: ResponseType.plain);
      expect(res.data, 'ok');
      expect(clock.slept, [const Duration(seconds: 7)]);
    });

    test('429 avec Retry-After répété : attente puis nouvel essai', () async {
      statuses = [429, 200];
      doubleRetryAfter = true;
      final res = await trackerGet<String>(dio(), Tracker.tr4ker, '/',
          type: ResponseType.plain);
      expect(res.data, 'ok');
      expect(clock.slept, [const Duration(seconds: 9)]);
    });

    test('téléchargements de .torrent espacés', () async {
      statuses = [200, 200, 200];
      for (var i = 0; i < 2; i++) {
        await trackerGet<String>(dio(), Tracker.tr4ker, '/',
            type: ResponseType.plain, download: true);
      }
      await trackerGet<String>(dio(), Tracker.tr4ker, '/',
          type: ResponseType.plain);
      expect(clock.slept, hasLength(1));
      expect(clock.slept.single, lessThanOrEqualTo(const Duration(seconds: 2)));
    });

    test('429 deux fois : erreur explicite', () async {
      statuses = [429, 429];
      await expectLater(
          trackerGet<String>(dio(), Tracker.tr4ker, '/',
              type: ResponseType.plain),
          throwsA(isA<TrackerException>().having(
              (e) => e.message, 'message', contains('Limite de requêtes'))));
    });
  });

  test('budgets : sous la limite annoncée de chaque tracker', () {
    for (final t in Tracker.values) {
      expect(trackerQuotas[t]!.limit, lessThan(t.requestsPerMinute));
      expect(trackerQuotas[t]!.downloadSpacing, t.downloadSpacing);
    }
    // C411 refuse déjà sous ses 120 / min : budget et espacement prudents.
    expect(trackerQuotas[Tracker.c411]!.limit, 80);
    expect(Tracker.c411.downloadSpacing, const Duration(seconds: 3));
    expect(trackerQuotas[Tracker.tr4ker]!.limit, 108);
  });
}
