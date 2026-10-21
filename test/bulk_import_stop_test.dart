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
}