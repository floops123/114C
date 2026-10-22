import 'package:c411_remote/api/c411_chat.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/notifications.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
