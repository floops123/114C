import 'package:c411_remote/api/draupnirr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DraupnirrAccount.fromJson', () {
    test('tous les champs renommés', () {
      final a = DraupnirrAccount.fromJson({
        'username': 'vache',
        'ratio': 2.5,
        'uploaded': 1234567890,
        'downloaded': 987654321,
        'credits': 50000000,
        'seedtime': 720,
        'hnr_count': 2,
        'badges': ['founder', 'vip', 'top10'],
      });
      expect(a.username, 'vache');
      expect(a.ratio, 2.5);
      expect(a.uploaded, 1234567890);
      expect(a.downloaded, 987654321);
      expect(a.credits, 50000000);
      expect(a.seedtimeHours, 720);
      expect(a.hnrCount, 2);
      expect(a.badges, ['founder', 'vip', 'top10']);
    });

    test('alias tolérés : uploaded_bytes, buffer, hit_and_runs', () {
      final a = DraupnirrAccount.fromJson({
        'name': 'alice',
        'uploaded_bytes': 1000,
        'downloaded_bytes': 200,
        'buffer': 300,
        'seedtime_hours': 5,
        'hit_and_runs': 1,
      });
      expect(a.username, 'alice');
      expect(a.uploaded, 1000);
      expect(a.downloaded, 200);
      expect(a.credits, 300);
      expect(a.seedtimeHours, 5);
      expect(a.hnrCount, 1);
    });

    test('champs absents : null (pas de crash)', () {
      final a = DraupnirrAccount.fromJson(const {});
      expect(a.username, isNull);
      expect(a.ratio, isNull);
      expect(a.uploaded, isNull);
      expect(a.badges, isEmpty);
    });

    test('badges : liste d\'objets {id} ou {name}', () {
      final a = DraupnirrAccount.fromJson({
        'badges': [
          {'id': 'founder'},
          {'name': 'vip'},
          'freeform-tag',
        ],
      });
      expect(a.badges, ['founder', 'vip', 'freeform-tag']);
    });
  });

  group('DraupnirrMission.fromJson', () {
    test('progress décimal', () {
      final m = DraupnirrMission.fromJson({
        'id': 'upload-1gb',
        'title': 'Uploade 1 Go',
        'progress': 0.42,
        'reward': '5000 points',
      });
      expect(m.id, 'upload-1gb');
      expect(m.title, 'Uploade 1 Go');
      expect(m.progress, 0.42);
      expect(m.fraction, closeTo(0.42, 1e-9));
      expect(m.reward, '5000 points');
    });

    test('progress en pourcentage (0-100)', () {
      final m = DraupnirrMission.fromJson({
        'id': 'x',
        'title': 'X',
        'progress': 75,
      });
      expect(m.fraction, closeTo(0.75, 1e-9));
    });

    test('current/target', () {
      final m = DraupnirrMission.fromJson({
        'id': 'x',
        'title': 'X',
        'current': 3,
        'target': 10,
      });
      expect(m.fraction, closeTo(0.3, 1e-9));
    });

    test('reward : objet sérialisé en string', () {
      final m = DraupnirrMission.fromJson({
        'id': 'x',
        'title': 'X',
        'reward': {'points': 100, 'badge': 'upload-1gb'},
      });
      expect(m.reward, contains('points'));
    });
  });

  group('DraupnirrMissions.parse', () {
    test('champ `data`', () {
      final list = DraupnirrMissions.parse({
        'data': [
          {'id': 'a', 'title': 'A', 'progress': 0.5},
          {'id': 'b', 'title': 'B', 'current': 1, 'target': 2},
        ],
      });
      expect(list, hasLength(2));
      expect(list[0].id, 'a');
      expect(list[1].fraction, 0.5);
    });

    test('champ `missions`', () {
      final list = DraupnirrMissions.parse({
        'missions': [
          {'id': 'a', 'title': 'A'},
        ],
      });
      expect(list.single.id, 'a');
    });

    test('racine = liste', () {
      final list = DraupnirrMissions.parse({
        '': null,
      });
      // Pas de liste : vide, sans crash.
      expect(list, isEmpty);
    });
  });

  group('DraupnirrBadge.fromJson', () {
    test('earned via `earned`', () {
      final b = DraupnirrBadge.fromJson({'id': 'x', 'name': 'X', 'earned': true});
      expect(b.earned, isTrue);
    });

    test('earned via `obtained`', () {
      final b = DraupnirrBadge.fromJson({'slug': 'x', 'obtained': true});
      expect(b.earned, isTrue);
    });

    test('non earned par défaut', () {
      final b = DraupnirrBadge.fromJson({'id': 'x', 'name': 'X'});
      expect(b.earned, isFalse);
    });
  });
}