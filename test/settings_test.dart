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
    const defaults = BuildDefaults();
    if (defaults.hasAny) {
      final settings = defaults.toAppSettings();
      _store[_key] = jsonEncode(settings.toJson());
      return settings;
    }
    return const AppSettings();
  }
}

/// Simule un binaire compilé avec `--dart-define=C411_RPC_URL=...` : on
/// précompile les valeurs en passant par un `BuildDefaults` rechargé. En
/// production, c'est la compilation elle-même qui fournit les valeurs via
/// `String.fromEnvironment` ; pour le test, on surcharge `SettingsNotifier`
/// pour vérifier la logique d'application des défauts.
class _WithDefaults extends SettingsNotifier {
  _WithDefaults(this._store, this._defaults);
  final Map<String, String> _store;
  final AppSettings _defaults;
  static const _key = 'settings';

  @override
  Future<AppSettings> build() async {
    final raw = _store[_key];
    if (raw != null) {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    _store[_key] = jsonEncode(_defaults.toJson());
    return _defaults;
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
    final defaults = const AppSettings(
      rpcUrl: 'http://build',
      rpcUser: 'build-user',
      rpcPassword: 'build-pwd',
      tmdbKey: 'build-tmdb',
    );
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _WithDefaults(store, defaults)),
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
      settingsProvider.overrideWith(() => _WithDefaults(
            store,
            const AppSettings(rpcUrl: 'http://build'),
          )),
    ]);
    addTearDown(container.dispose);
    final s = await container.read(settingsProvider.future);
    expect(s.rpcUrl, 'http://existing');
    expect(s.rpcUser, 'existing');
  });

  test('BuildDefaults : aucune variable, hasAny false', () {
    expect(const BuildDefaults().hasAny, isFalse);
    expect(const BuildDefaults().toAppSettings().rpcUrl, isEmpty);
  });
}