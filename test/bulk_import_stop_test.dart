import 'dart:typed_data';

import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/state/bulk_import.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Torrents extends TorrentsNotifier {
  @override
  TorrentsState build() => const TorrentsState(loaded: true);
}

class _Transmission extends TransmissionClient {
  _Transmission() : super(url: 'http://x');
  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async =>
      (torrents: <Map<String, dynamic>>[], removed: <int>[]);
}

/// Une sortie, dont le téléchargement plante d'une façon imprévue.
class _Broken implements TrackerApi {
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
            createdAt: DateTime(2026)),
      ], 1, 1, 1);
  @override
  Future<Uint8List> downloadTorrent(Release release) async =>
      throw StateError('en-tête inattendu');
}

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

void main() {
  test('stop() invalide la génération en cours', () async {
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_Settings.new),
      transmissionProvider.overrideWithValue(_Transmission()),
      torrentsProvider.overrideWith(_Torrents.new),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    final notifier = container.read(bulkImportProvider.notifier);
    final genBefore = container.read(bulkImportProvider).searched;
    // L'état initial : pas de recherche.
    expect(container.read(bulkImportProvider).loading, isFalse);
    // Une recherche en cours simule `loading = true` (search() le fait,
    // mais sans trackers configurés il n'y a rien à charger). On simule
    // l'état.
    notifier.update(const BulkCriteria(name: 'foo'));
    notifier.search();
    expect(container.read(bulkImportProvider).loading, isTrue);
    // On stoppe : le spinner s'arrête. La génération a avancé.
    notifier.stop();
    expect(container.read(bulkImportProvider).loading, isFalse);
    // Le critère saisi est préservé (c'est ce qu'on veut).
    expect(container.read(bulkImportProvider).criteria.name, 'foo');
    // (Recherche) : la génération a bien changé.
    expect(container.read(bulkImportProvider).searched, isNot(genBefore));
  });

  test('erreur imprévue à l’envoi : ligne en échec, bouton libéré', () async {
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_Settings.new),
      transmissionProvider.overrideWithValue(_Transmission()),
      torrentsProvider.overrideWith(_Torrents.new),
      trackersProvider.overrideWithValue({Tracker.c411: _Broken()}),
    ]);
    addTearDown(container.dispose);
    container.listen(bulkImportProvider, (_, _) {});
    final notifier = container.read(bulkImportProvider.notifier);
    notifier.search();
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(bulkImportProvider).selected, hasLength(1));

    expect(await notifier.send(), 0);
    final state = container.read(bulkImportProvider);
    expect(state.sending, isFalse);
    expect(state.toSend, 1);
    expect(state.items.single.failed, isTrue);
    expect(state.items.single.detail, contains('en-tête inattendu'));
  });
}
