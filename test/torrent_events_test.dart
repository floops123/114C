import 'dart:typed_data';

import 'package:c411_remote/api/c411.dart';
import 'package:c411_remote/api/c411_chat.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/preferences.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/notifications.dart';
import 'package:c411_remote/state/palliative.dart';
import 'package:c411_remote/state/torrent_updates.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'palliative_test.dart' show FakeTorrents;

const _hash = '3ab29254ca98bbc3fc19e6572f573326f56ddc50';

/// Notification réelle du site (`/api/notifications`).
final _deleted = {
  'id': 5867770,
  'type': 'torrent_deleted',
  'title': 'Torrent supprimé',
  'message': 'Le torrent "By.Click.Downloader.v2.4.30" a été supprimé (retiré par son uploader). '
      'Vous pouvez le retirer de votre client torrent.',
  'link': '/torrents/$_hash',
  'data': {
    'torrentId': 772126,
    'infoHash': _hash,
    'torrentName': 'By.Click.Downloader.v2.4.30',
    'deletedAt': '2026-10-22T00:30:08.097Z',
    'reasonCode': 'uploader_request',
  },
  'isRead': false,
  'createdAt': '2026-10-22T00:30:08.000Z',
};

final _levelUp = {
  'id': 5832408,
  'type': 'ic_level_up',
  'title': 'Niveau 25 atteint',
  'link': '/community/my-rank',
  'data': {'fromLevel': 24, 'toLevel': 25},
  'isRead': false,
  'createdAt': '2026-10-21T22:17:02.000Z',
};

class _Api extends C411ChatApi {
  _Api(this.items) : super('cookie');
  final List<Map<String, dynamic>> items;

  @override
  Future<({List<Map<String, dynamic>> items, bool hasMore, int unread})>
      notifications({int offset = 0, int perPage = 30}) async =>
          (items: items, hasMore: false, unread: items.length);
}

class _Client extends TransmissionClient {
  _Client({this.fail = false}) : super(url: 'http://seedbox:9091/transmission/rpc');
  bool fail;
  final calls = <String>[];
  Object? asked;

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async {
    if (fail) throw const TransmissionException('injoignable');
    asked = ids;
    return (
      torrents: [
        {'id': 7, 'hashString': _hash.toUpperCase(), 'name': 'By.Click.Downloader', 'labels': ['c411']},
      ],
      removed: <int>[],
    );
  }

  @override
  Future<void> action(String method, List<int>? ids) async => calls.add('$method $ids');

  @override
  Future<void> torrentSet(List<int> ids, Map<String, dynamic> args) async =>
      calls.add('set $ids $args');
}

class _NoSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

void main() {
  updates();
  prefs();

  test('empreinte d’une notification de suppression', () {
    expect(AppNotification.fromSite(_deleted).deletedHash, _hash);
    expect(AppNotification.fromSite({..._deleted, 'data': null}).deletedHash, _hash,
        reason: 'repli sur le lien');
    expect(AppNotification.fromSite(_levelUp).deletedHash, isNull);
  });

  test('torrent supprimé du site : en pause et étiqueté, une seule fois', () async {
    final client = _Client(fail: true);
    final store = MemoryNotificationStore();
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_NoSettings.new),
      chatApiProvider.overrideWithValue(_Api([_deleted, _levelUp])),
      transmissionProvider.overrideWithValue(client),
      torrentsProvider.overrideWith(FakeTorrents.new),
      notificationStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsProvider.notifier);

    // Client injoignable : rien n'est retenu, on réessaie au relevé suivant.
    await notifier.refreshNotifications();
    expect(store.handled, isEmpty);

    client.fail = false;
    await notifier.refreshNotifications();
    expect(client.asked, [_hash]);
    expect(client.calls, [
      'torrent-stop [7]',
      'set [7] {labels: [c411, $deletedLabel]}',
    ]);
    expect(store.handled, {5867770});
    expect(container.read(notificationsProvider).arrival, contains('By.Click.Downloader'));

    // Remis en route par l'utilisateur : pas de nouvelle pause.
    await notifier.refreshNotifications();
    expect(client.calls, hasLength(2));
  });
}

const _old = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _new = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class _Site extends C411SiteApi {
  _Site() : super('cookie');
  final asked = <String>[];

  @override
  Future<Uint8List> downloadTorrent(Release release) async {
    asked.add(release.infoHash!);
    if (release.infoHash != _new) throw const TrackerException('C411 : torrent introuvable');
    return Uint8List.fromList([1, 2, 3]);
  }
}

/// Transmission avec l'ancien torrent ; l'ajout donne [addedHash].
class _Swap extends TransmissionClient {
  _Swap(this.addedHash, {this.status = 6}) : super(url: 'http://seedbox:9091/transmission/rpc');
  final String addedHash;
  final int status;
  final calls = <String>[];

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async => (
        torrents: [
          if ((ids as List).contains(_old))
            {'id': 3, 'hashString': _old, 'name': 'Serie.S01', 'labels': ['c411'],
             'downloadDir': '/data/series', 'status': status},
          if (ids.contains(addedHash) && addedHash != _old) {'id': 9, 'hashString': addedHash},
        ],
        removed: <int>[],
      );

  @override
  Future<({bool added, String? hash})> addTorrentWithHash(
      {Uint8List? metainfo, String? filename, AddOptions options = const AddOptions()}) async {
    calls.add('add ${options.downloadDir} paused=${options.paused} ${options.labels}');
    return (added: addedHash != _old, hash: addedHash);
  }

  @override
  Future<void> torrentSet(List<int> ids, Map<String, dynamic> args) async => calls.add('set $ids $args');
  @override
  Future<void> remove(List<int> ids, {bool deleteData = false}) async => calls.add('remove $ids $deleteData');
  @override
  Future<void> action(String method, List<int>? ids) async => calls.add('$method $ids');
}

AppNotification _updated(Map<String, Object?> data) => AppNotification.fromSite({
      'id': 42, 'type': 'torrent_updated', 'title': 'Torrent modifié', 'link': '/torrents/$_new',
      'data': data, 'isRead': false, 'createdAt': '2026-10-22T10:00:00.000Z',
    });

void updates() {
  test('torrent modifié : reconnu, empreintes de la plus récente à l’ancienne', () {
    final n = _updated({'oldInfoHash': _old, 'newInfoHash': _new, 'torrentId': 1});
    expect(isTorrentUpdate(n), isTrue);
    expect(isTorrentUpdateType('torrent_deleted'), isFalse);
    expect(notificationHashes(n), [_new, _old]);
  });

  test('torrent modifié : nouveau .torrent à la place de l’ancien, données gardées', () async {
    final client = _Swap(_new);
    final site = _Site();
    final (outcome, name) =
        await updateModifiedTorrent(client, site, _updated({'oldInfoHash': _old, 'newInfoHash': _new}));
    expect((outcome, name), (UpdateOutcome.updated, 'Serie.S01'));
    expect(site.asked, [_new]);
    expect(client.calls, [
      'add /data/series paused=true [c411]',
      'set [9] {labels: [c411]}',
      'remove [3] false',
      'torrent-verify [9]',
      'torrent-start [9]',
    ]);
  });

  test('torrent modifié : en pause, il le reste ; même empreinte, rien à faire', () async {
    final paused = _Swap(_new, status: 0);
    await updateModifiedTorrent(paused, _Site(), _updated({'oldInfoHash': _old, 'newInfoHash': _new}));
    expect(paused.calls.last, 'torrent-verify [9]');

    final same = _Swap(_old);
    final (outcome, _) = await updateModifiedTorrent(same, _Site(), _updated({'infoHash': _old}));
    expect(outcome, UpdateOutcome.unchanged);
    expect(same.calls, ['add /data/series paused=true [c411]']);
  });

  test('torrent modifié : appliqué une fois depuis les notifications', () async {
    final client = _Swap(_new);
    final store = MemoryNotificationStore();
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_NoSettings.new),
      chatApiProvider.overrideWithValue(_Api([
        {'id': 42, 'type': 'torrent_updated', 'title': 'Torrent modifié', 'link': '/torrents/$_new',
         'data': {'oldInfoHash': _old}, 'isRead': false, 'createdAt': '2026-10-22T10:00:00.000Z'},
      ])),
      transmissionProvider.overrideWithValue(client),
      c411SiteApiProvider.overrideWithValue(_Site()),
      torrentsProvider.overrideWith(FakeTorrents.new),
      notificationStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(notificationsProvider.notifier);
    await notifier.refreshNotifications();
    expect(store.handled, {42});
    expect(container.read(notificationsProvider).arrival, 'Modifié sur le site, mis à jour : Serie.S01');
    final n = client.calls.length;
    await notifier.refreshNotifications();
    expect(client.calls, hasLength(n));
  });
}

void prefs() {
  test('notifications appliquées : enregistrées dans les préférences autorisées', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final store = PrefsNotificationStore(await loadSharedPrefs());
    store.saveHandled({1, 2});
    await Future<void>.delayed(Duration.zero);
    expect(store.loadHandled(), {1, 2});
    expect(PrefsNotificationStore(await loadSharedPrefs()).loadHandled(), {1, 2},
        reason: 'relu après redémarrage');
  });
}
