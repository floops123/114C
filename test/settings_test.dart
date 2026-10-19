import 'dart:convert';

import 'package:c411_remote/core/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `SettingsNotifier` de test : le trousseau est une `Map<String, String>`
/// en mémoire (pas de plugin sécurisé sur l'hôte de test).
class _Memory extends SettingsNotifier {
  _Memory(this._store, {this.simulateDefaults = false});
  final Map<String, String> _store;
  final bool simulateDefaults;
  static const _key = 'settings';

  @override
  Future<AppSettings> build() async {
    final raw = _store[_key];
    if (raw != null) {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    if (simulateDefaults) {
      // Simule ce que ferait `BuildDefaults` si des --dart-define étaient
      // passés : on construit un `AppSettings` non vide qu'on persiste.
      final settings = const AppSettings(
        rpcUrl: 'http://build',
        rpcUser: 'build-user',
        rpcPassword: 'build-pwd',
        tmdbKey: 'build-tmdb',
      );
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
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _Memory(store, simulateDefaults: true)),
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
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _Memory(store, simulateDefaults: true)),
    ]);
    addTearDown(container.dispose);
    final s = await container.read(settingsProvider.future);
    expect(s.rpcUrl, 'http://existing');
    expect(s.rpcUser, 'existing');
  });
}