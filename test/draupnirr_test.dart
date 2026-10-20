import 'package:c411_remote/api/draupnirr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DraupnirrAccount.fromJson', () {
    test('jeu de données réel : floops', () {
      final a = DraupnirrAccount.fromJson({
        'name': 'floops',
        'source_tag': 'DRAUPNIRR',
        'site_url': 'https://draupnirr.xyz',
        'class': 'nouveau',
        'credits': 0,
        'invites': 0,
        'freeleech_until': null,
        'freeleech_global': true,
        'uploaded': 0,
        'downloaded': 0,
        'bonus_upload': 107374182400,
        'buffer': 107374182400,
        'ratio': null,
        'seedtime_seconds': 0,
        'seedtime_cumulative_seconds': 0,
        'uploads_count': 0,
        'hnr_count': 0,
        'badges': [],
      });
      expect(a.username, 'floops');
      expect(a.userClass, 'nouveau');
      expect(a.sourceTag, 'DRAUPNIRR');
      expect(a.ratio, isNull);
      expect(a.uploaded, 0);
      expect(a.downloaded, 0);
      expect(a.credits, 0);
      expect(a.buffer, 107374182400);
      expect(a.invites, 0);
      expect(a.uploadsCount, 0);
      expect(a.hnrCount, 0);
      expect(a.freeleechGlobal, isTrue);
      expect(a.seedtimeHours, 0);
      expect(a.seedtimeCumulativeHours, 0);
      expect(a.badges, isEmpty);
    });

    test('seedtime_seconds : 3600 → 1 h', () {
      final a = DraupnirrAccount.fromJson({
        'seedtime_seconds': 3600,
        'seedtime_cumulative_seconds': 7200,
      });
      expect(a.seedtimeHours, 1);
      expect(a.seedtimeCumulativeHours, 2);
    });

    test('seedtime_seconds : null → null', () {
      final a = DraupnirrAccount.fromJson(const {});
      expect(a.seedtimeHours, isNull);
      expect(a.seedtimeCumulativeHours, isNull);
    });

    test('freeleech_global : false', () {
      final a = DraupnirrAccount.fromJson({'freeleech_global': false});
      expect(a.freeleechGlobal, isFalse);
    });

    test('freeleech_global : absent → null', () {
      final a = DraupnirrAccount.fromJson(const {});
      expect(a.freeleechGlobal, isNull);
    });

    test('username : name', () {
      final a = DraupnirrAccount.fromJson({'name': 'floops'});
      expect(a.username, 'floops');
    });

    test('username : pas de name → null', () {
      final a = DraupnirrAccount.fromJson(const {});
      expect(a.username, isNull);
    });
  });

  group('DraupnirrMission.fromJson', () {
    test('jeu de données réel : daily-complete-1 terminée', () {
      final m = DraupnirrMission.fromJson({
        'code': 'daily-complete-1',
        'period': 'daily',
        'title': 'Complète un torrent',
        'goal_type': 'complete_download',
        'goal_value': 1,
        'reward_credits': 15,
        'progress': 1,
        'completed': true,
      });
      expect(m.id, 'daily-complete-1');
      expect(m.title, 'Complète un torrent');
      expect(m.period, DraupnirrMissionPeriod.daily);
      expect(m.goalValue, 1);
      expect(m.progress, 1);
      expect(m.rewardCredits, 15);
      expect(m.completed, isTrue);
      expect(m.fraction, 1.0);
    });

    test('jeu de données réel : weekly-seed-50h 0 / 180000', () {
      final m = DraupnirrMission.fromJson({
        'code': 'weekly-seed-50h',
        'period': 'weekly',
        'title': 'Marathon',
        'goal_type': 'seed_seconds',
        'goal_value': 180000,
        'reward_credits': 250,
        'progress': 0,
        'completed': false,
      });
      expect(m.period, DraupnirrMissionPeriod.weekly);
      expect(m.fraction, 0.0);
      expect(m.rewardCredits, 250);
    });

    test('progress / goal_value : 50 %', () {
      final m = DraupnirrMission.fromJson({
        'progress': 90,
        'goal_value': 180,
      });
      expect(m.fraction, closeTo(0.5, 1e-9));
    });

    test('progress / goal_value : cap à 1', () {
      final m = DraupnirrMission.fromJson({
        'progress': 10,
        'goal_value': 1,
      });
      expect(m.fraction, 1.0);
    });

    test('progress sans goal_value : fraction directe (≤ 1)', () {
      final m = DraupnirrMission.fromJson({'progress': 0.42});
      expect(m.fraction, closeTo(0.42, 1e-9));
    });

    test('progress sans goal_value : pourcentage (> 1)', () {
      final m = DraupnirrMission.fromJson({'progress': 75});
      expect(m.fraction, closeTo(0.75, 1e-9));
    });

    test('period : values reconnues', () {
      expect(DraupnirrMissionPeriod.fromString('daily'),
          DraupnirrMissionPeriod.daily);
      expect(DraupnirrMissionPeriod.fromString('weekly'),
          DraupnirrMissionPeriod.weekly);
      expect(DraupnirrMissionPeriod.fromString('monthly'),
          DraupnirrMissionPeriod.monthly);
      expect(DraupnirrMissionPeriod.fromString('whatever'),
          DraupnirrMissionPeriod.other);
      expect(DraupnirrMissionPeriod.fromString(null),
          DraupnirrMissionPeriod.other);
    });
  });

  group('DraupnirrMissions.parse', () {
    test('tableau direct (format Draupnirr)', () {
      final list = DraupnirrMissions.parse([
        {'code': 'a', 'title': 'A', 'progress': 1, 'goal_value': 1, 'completed': true},
        {'code': 'b', 'title': 'B', 'progress': 0, 'goal_value': 100},
      ]);
      expect(list, hasLength(2));
      expect(list[0].id, 'a');
      expect(list[0].completed, isTrue);
      expect(list[1].fraction, 0.0);
    });

    test('objet avec data[] (compat)', () {
      final list = DraupnirrMissions.parse({
        'data': [
          {'code': 'a', 'title': 'A', 'progress': 1, 'goal_value': 1},
        ],
      });
      expect(list.single.id, 'a');
    });

    test('objet avec missions[] (compat)', () {
      final list = DraupnirrMissions.parse({
        'missions': [
          {'code': 'a', 'title': 'A'},
        ],
      });
      expect(list.single.id, 'a');
    });

    test('null / non-list / non-map : vide sans crash', () {
      expect(DraupnirrMissions.parse(null), isEmpty);
      expect(DraupnirrMissions.parse('oops'), isEmpty);
      expect(DraupnirrMissions.parse(42), isEmpty);
    });
  });

  group('DraupnirrBadge.fromJson', () {
    test('jeu de données réel : non obtenu', () {
      final b = DraupnirrBadge.fromJson({
        'slug': 'premier-upload',
        'name': 'Premier upload',
        'description': 'Ton premier torrent approuvé sur Draupnirr.',
        'earned': false,
        'awarded_at': null,
      });
      expect(b.slug, 'premier-upload');
      expect(b.name, 'Premier upload');
      expect(b.earned, isFalse);
      expect(b.awardedAt, isNull);
    });

    test('obtenu avec awarded_at ISO', () {
      final b = DraupnirrBadge.fromJson({
        'slug': 'graine',
        'name': 'Graine',
        'description': '100 heures de seed cumulées.',
        'earned': true,
        'awarded_at': '2026-04-01T12:00:00Z',
      });
      expect(b.earned, isTrue);
      expect(b.awardedAt, isNotNull);
      expect(b.awardedAt!.year, 2026);
    });
  });

  group('DraupnirrBadges.parse', () {
    test('tableau direct (format Draupnirr)', () {
      final list = DraupnirrBadges.parse([
        {'slug': 'a', 'name': 'A', 'earned': true},
        {'slug': 'b', 'name': 'B', 'earned': false},
      ]);
      expect(list, hasLength(2));
      expect(list.first.earned, isTrue);
      expect(list.last.earned, isFalse);
    });

    test('objet avec data[]', () {
      final list = DraupnirrBadges.parse({
        'data': [
          {'slug': 'a', 'name': 'A'},
        ],
      });
      expect(list.single.slug, 'a');
    });
  });
}