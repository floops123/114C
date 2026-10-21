import 'dart:convert';
import 'dart:io';

import 'package:c411_remote/api/c411.dart';
import 'package:c411_remote/api/c411_profile.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('lecture des réponses du site', () {
    test('compte', () {
      final a = C411Account.parse(_fixture('c411_me'));
      expect(a.username, 'moi');
      expect(a.badge, 'Membre');
      expect(a.className, 'Swarm Keeper');
      expect((a.classTier, a.classLevel), ('bronze', 4));
      expect(a.emblemUrl, 'https://c411.org/images/class-emblems/swarm-keeper/bronze-4.webp');
      expect(a.freeDownloads, 3);
      expect(a.minRatio, 0.8);
      expect(a.canDownload, isTrue);
      expect(a.ratio, closeTo(1.069, 0.001));
      expect(a.createdAt, DateTime.utc(2026, 3, 8, 13, 46));
    });

    test('niveau et solde', () {
      final l = C411Level.parse(_fixture('c411_level'));
      expect((l.level, l.xp, l.xpToNext, l.streakDays), (24, 5081, 307, 6));
      final b = ZenBalance.parse(_fixture('c411_balance'));
      expect((b.balance, b.earned, b.spent, b.lastDaily), (1091, 1281, 190, 29));
    });

    test('versements : les chiffres affichés par le site', () {
      final h = ZenHistory.parse(_fixture('c411_daily_stats'));
      expect(h.days, 30);
      expect(h.bonusCapBp, 3000);
      final d = h.latest!;
      expect(d.date, DateTime(2026, 10, 21));
      // 734 torrents × 99,3 % × 0,20 × 1,12 ÷ 7 = 23,3 ; + 25 % → 29.
      expect(d.torrents, 734);
      expect(d.share, closeTo(0.993, 0.0005));
      expect(d.weight, closeTo(0.20, 0.005));
      expect(d.contribution / maxContribution, closeTo(0.56, 0.001));
      expect(d.beforeBonus, closeTo(23.3, 0.05));
      expect(d.bonus, 0.25);
      expect(d.paid, 29);
      expect((d.beforeBonus * (1 + d.bonus)).round(), d.paid);
      // Le plus ancien : 482 × 18,6 % × 0,35 × 1,12 ÷ 7 ≈ 5 ; +24 % → 6.
      final first = h.entries.last;
      expect(first.share, closeTo(0.186, 0.0005));
      expect(first.weight, closeTo(0.35, 0.005));
      expect((first.beforeBonus * (1 + first.bonus)).round(), 6);
      // Par jour 21 (107 ÷ 5), par mois 642, par heure 0,892.
      expect(h.perDay, closeTo(21.4, 0.001));
      expect(h.perDay * 30, closeTo(642, 0.5));
      expect(h.perDay / 24, closeTo(0.892, 0.0005));
    });

    test('réanimations : payée, en cours', () {
      final list = C411Revival.parseList(_fixture('c411_revivals'));
      expect(list.map((r) => r.id), [1950, 1920], reason: 'plus récente d’abord');
      final paid = list.last;
      expect(paid.paid, isTrue);
      expect(paid.zen, 3, reason: 'prime 2 + bonus du gardien 1');
      expect(paid.infoHash, '25e597ea1516ad054dcc8c49f60e681c9f83ed57');
      final running = list.first;
      expect(running.inProgress, isTrue);
      expect(running.progress, closeTo(1 / 3, 0.001), reason: '24 h sur 72 h');
      expect(running.deadline, DateTime.utc(2026, 11, 3, 10));
    });

    test('classement', () {
      final b = C411Leaderboard.parse(_fixture('c411_leaderboard'));
      expect(b.top.map((e) => e.rank), [1, 2]);
      expect(b.top.first.className, 'Tanker');
      expect(b.top.first.grade, 'Bronze IV');
      expect(b.top.first.avatarUrl, 'https://c411.org/uploads/avatars/1-md.webp');
      expect(b.top.last.avatarUrl, isNull);
      expect((b.rank, b.total, b.xp, b.dailyXp), (121567, 399543, 5081, 95));
    });

    test('journée en cours', () {
      final f = ZenForecast.parse(_fixture('c411_forecast'))!;
      expect(f.today.paid, 22);
      expect(f.projected, 33);
      expect(f.today.share, closeTo(0.379, 0.0005));
      expect(f.today.weight, closeTo(0.19, 0.005));
      expect(f.today.beforeBonus, closeTo(17.6, 0.05));
      expect(f.bonusCapBp, 3000);
      expect(ZenForecast.parse({'enabled': false}), isNull);
    });
  });

  group('overview : tous les endpoints avec le cookie', () {
    late HttpServer server;
    late Map<String, int> statuses;
    late List<String> cookies;

    setUp(() async {
      statuses = {};
      cookies = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        cookies.add(req.headers.value('cookie') ?? '');
        final name = switch (req.uri.path) {
          '/api/auth/me' => 'c411_me',
          '/api/ic/level' => 'c411_level',
          '/api/tokens/balance' => 'c411_balance',
          '/api/tokens/daily-stats' => 'c411_daily_stats',
          '/api/tokens/forecast' => 'c411_forecast',
          '/api/profile/revivals' => 'c411_revivals',
          '/api/ic/leaderboard/all_time' => 'c411_leaderboard',
          _ => null,
        };
        req.response.statusCode = statuses[req.uri.path] ?? (name == null ? 404 : 200);
        req.response.headers.contentType = ContentType.json;
        if (name != null && req.response.statusCode == 200) {
          req.response.write(File('test/fixtures/$name.json').readAsStringSync());
        }
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    C411SiteApi api() =>
        C411SiteApi('session=abc', baseUrl: 'http://127.0.0.1:${server.port}');

    test('tout arrive, avec le cookie', () async {
      final o = await api().overview();
      expect(o.account?.username, 'moi');
      expect(o.level?.level, 24);
      expect(o.balance?.balance, 1091);
      expect(o.history?.entries, hasLength(5));
      expect(o.forecast?.projected, 33);
      expect(o.revivals, hasLength(2));
      expect(o.leaderboard?.rank, 121567);
      expect(cookies, everyElement('session=abc'));
      expect(cookies, hasLength(7));
    });

    test('un endpoint en panne : le reste s’affiche', () async {
      statuses['/api/tokens/forecast'] = 500;
      final o = await api().overview();
      expect(o.forecast, isNull);
      expect(o.balance?.balance, 1091);
    });

    test('cookie refusé : erreur', () async {
      statuses['/api/auth/me'] = 401;
      await expectLater(api().overview(),
          throwsA(isA<TrackerException>().having((e) => e.message, 'message', contains('Cookie'))));
    });
  });
}
