import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférences d'interface (non sensibles), chargées avant le premier rendu
/// pour éviter un flash de thème au démarrage.
final sharedPrefsProvider = Provider<SharedPreferencesWithCache>(
    (ref) => throw UnimplementedError('Surchargé dans main()'));

Future<SharedPreferencesWithCache> loadSharedPrefs() =>
    SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: {
        UiPrefsNotifier._themeKey,
        UiPrefsNotifier._gridKey,
        'tracker', // SelectedTrackerNotifier
      }),
    );

class UiPrefs {
  const UiPrefs({this.themeMode = ThemeMode.system, this.releasesGrid = true});
  final ThemeMode themeMode;
  final bool releasesGrid;
}

class UiPrefsNotifier extends Notifier<UiPrefs> {
  static const _themeKey = 'themeMode';
  static const _gridKey = 'releasesGrid';

  SharedPreferencesWithCache get _prefs => ref.read(sharedPrefsProvider);

  @override
  UiPrefs build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return UiPrefs(
      themeMode: ThemeMode.values.asNameMap()[prefs.getString(_themeKey)] ??
          ThemeMode.system,
      releasesGrid: prefs.getBool(_gridKey) ?? true,
    );
  }

  void setThemeMode(ThemeMode mode) {
    _prefs.setString(_themeKey, mode.name);
    state = UiPrefs(themeMode: mode, releasesGrid: state.releasesGrid);
  }

  void setReleasesGrid(bool grid) {
    _prefs.setBool(_gridKey, grid);
    state = UiPrefs(themeMode: state.themeMode, releasesGrid: grid);
  }
}

final uiPrefsProvider =
    NotifierProvider<UiPrefsNotifier, UiPrefs>(UiPrefsNotifier.new);
