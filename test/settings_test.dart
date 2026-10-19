import 'dart:convert';

import 'package:c411_remote/build_defaults.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `SettingsNotifier` de test : remplace le trousseau système (qui n'existe
/// pas en environnement de test) par une `Map<String, String>` en mémoire.
/// Reproduit la même logique que `SettingsNotifier` mais sans dépendre de
/// `FlutterSecureStorage`.
class _Memory extends SettingsNotifier {
  _Memory(this._store);
  final Map<String, String> _store;
  static const _key = 'settings';

  @override
  Future<AppSettings> build() async {
    final raw = _store[_key];
    if (raw != null) {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    final defaults = ref.read(buildDefaultsProvider);
    if (defaults.hasAny) {
      final settings = defaults.toAppSettings();
      _store[_key] = jsonEncode(settings.toJson());
      return settings;
    }
    return const AppSettings();
  }
}

void main() {
  test('trousseau vide, aucun défaut : AppSettings vide', () async {
    final store = <String, String>{};
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _Memory(store)),
      buildDefaultsProvider.overrideWithValue(BuildDefaults.empty()),
    ]);
    addTearDown(container.dispose);
    final s = await container.read(settingsProvider.future);
    expect(s.rpcUrl, isEmpty);
    expect(store, isEmpty,
        reason: 'rien à écrire quand le trousseau est vide et qu’il n’y a '
            'pas de défauts au build');
  });

  test('trousseau vide + défauts au build : défauts appliqués et persistés',
      () async {
    final store = <String, String>{};
    final defaults = BuildDefaults.fromMap({
      'C411_RPC_URL': 'http://build',
      'C411_RPC_USER': 'build-user',
      'C411_RPC_PASSWORD': 'build-pwd',
      'C411_TMDB_KEY': 'build-tmdb',
    });
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _Memory(store)),
      buildDefaultsProvider.overrideWithValue(defaults),
    ]);
    addTearDown(container.dispose);
    final s = await container.read(settingsProvider.future);
    expect(s.rpcUrl, 'http://build');
    expect(s.tmdbKey, 'build-tmdb');
    expect(store, isNotEmpty,
        reason: 'les défauts doivent être écrits dans le trousseau');
  });

  test('trousseau non vide : les défauts au build sont ignorés', () async {
    final store = <String, String>{
      'settings': jsonEncode({
        'rpcUrl': 'http://existing',
        'rpcUser': 'existing',
      }),
    };
    final defaults = BuildDefaults.fromMap({
      'C411_RPC_URL': 'http://build',
      'C411_TMDB_KEY': 'build-tmdb',
    });
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _Memory(store)),
      buildDefaultsProvider.overrideWithValue(defaults),
    ]);
    addTearDown(container.dispose);
    final s = await container.read(settingsProvider.future);
    expect(s.rpcUrl, 'http://existing');
    expect(s.rpcUser, 'existing');
  });
}