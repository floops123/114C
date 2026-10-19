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
        UiPrefsNotifier._releaseSortKey,
        UiPrefsNotifier._releaseAscKey,
        UiPrefsNotifier._transferSortKey,
        UiPrefsNotifier._transferAscKey,
        'tracker', // SelectedTrackerNotifier
        'notifications', // PrefsNotificationStore
        'crossSeed', // PrefsCrossSeedCache
        'crossSeedDirections', // CrossSeedDirectionsNotifier
        'wishlist', // PrefsWishlistStore
        'playback', // PrefsPlaybackStore
        'mediaLibrary', // PrefsMediaLibraryStore
        'availability', // PrefsAvailabilityStore
        'tmdbMatches', // PrefsTmdbMatchStore
        'revive', // PrefsReviveStore
        'palliative', // PrefsPalliativeStore
      }),
    );

class UiPrefs {
  const UiPrefs({
    this.themeMode = ThemeMode.system,
    this.releasesGrid = true,
    this.releaseSort,
    this.releaseAscending = false,
    this.transferSort,
    this.transferAscending = false,
  });

  final ThemeMode themeMode;
  final bool releasesGrid;

  /// Noms des critères de tri (enums définis côté interface).
  final String? releaseSort;
  final bool releaseAscending;
  final String? transferSort;
  final bool transferAscending;

  UiPrefs copyWith({
    ThemeMode? themeMode,
    bool? releasesGrid,
    String? releaseSort,
    bool? releaseAscending,
    String? transferSort,
    bool? transferAscending,
  }) =>
      UiPrefs(
        themeMode: themeMode ?? this.themeMode,
        releasesGrid: releasesGrid ?? this.releasesGrid,
        releaseSort: releaseSort ?? this.releaseSort,
        releaseAscending: releaseAscending ?? this.releaseAscending,
        transferSort: transferSort ?? this.transferSort,
        transferAscending: transferAscending ?? this.transferAscending,
      );
}

class UiPrefsNotifier extends Notifier<UiPrefs> {
  static const _themeKey = 'themeMode';
  static const _gridKey = 'releasesGrid';
  static const _releaseSortKey = 'releaseSort';
  static const _releaseAscKey = 'releaseAscending';
  static const _transferSortKey = 'transferSort';
  static const _transferAscKey = 'transferAscending';

  SharedPreferencesWithCache get _prefs => ref.read(sharedPrefsProvider);

  @override
  UiPrefs build() {
    final SharedPreferencesWithCache prefs;
    try {
      prefs = ref.watch(sharedPrefsProvider);
    } on Object {
      return const UiPrefs(); // Préférences non initialisées (tests).
    }
    return UiPrefs(
      themeMode: ThemeMode.values.asNameMap()[prefs.getString(_themeKey)] ??
          ThemeMode.system,
      releasesGrid: prefs.getBool(_gridKey) ?? true,
      releaseSort: prefs.getString(_releaseSortKey),
      releaseAscending: prefs.getBool(_releaseAscKey) ?? false,
      transferSort: prefs.getString(_transferSortKey),
      transferAscending: prefs.getBool(_transferAscKey) ?? false,
    );
  }

  void setThemeMode(ThemeMode mode) {
    _prefs.setString(_themeKey, mode.name);
    state = state.copyWith(themeMode: mode);
  }

  void setReleasesGrid(bool grid) {
    try {
      _prefs.setBool(_gridKey, grid);
    } on Object {
      // Préférences non initialisées (tests) : en mémoire seulement.
    }
    state = state.copyWith(releasesGrid: grid);
  }

  void setReleaseSort(String sort, bool ascending) {
    _prefs.setString(_releaseSortKey, sort);
    _prefs.setBool(_releaseAscKey, ascending);
    state = state.copyWith(releaseSort: sort, releaseAscending: ascending);
  }

  void setTransferSort(String sort, bool ascending) {
    _prefs.setString(_transferSortKey, sort);
    _prefs.setBool(_transferAscKey, ascending);
    state = state.copyWith(transferSort: sort, transferAscending: ascending);
  }
}

final uiPrefsProvider =
    NotifierProvider<UiPrefsNotifier, UiPrefs>(UiPrefsNotifier.new);
