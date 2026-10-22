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
        UiPrefsNotifier._fontKey,
        UiPrefsNotifier._gridKey,
        UiPrefsNotifier._releaseSortKey,
        UiPrefsNotifier._releaseAscKey,
        UiPrefsNotifier._transferSortKey,
        UiPrefsNotifier._transferAscKey,
        UiPrefsNotifier._autoRefreshKey,
        UiPrefsNotifier._transferLimitKey,
        'tracker', // SelectedTrackerNotifier
        'notifications', // PrefsNotificationStore
        'notifications.deleted', // PrefsNotificationStore.handledKey
        'crossSeed', // PrefsCrossSeedCache
        'crossSeedDirections', // CrossSeedDirectionsNotifier
        'wishlist', // PrefsWishlistStore
        'playback', // PrefsPlaybackStore
        'mediaLibrary', // PrefsMediaLibraryStore
        'availability', // PrefsAvailabilityStore
        'tmdbMatches', // PrefsTmdbMatchStore
        'revive', // PrefsReviveStore
        'palliative', // PrefsPalliativeStore
        'releaseWatch', // PrefsWatchStore
        'releaseWatchConfig', // WatchConfigNotifier
      }),
    );

class UiPrefs {
  const UiPrefs({
    this.themeMode = ThemeMode.system,
    this.font,
    this.releasesGrid = true,
    this.releaseSort,
    this.releaseAscending = false,
    this.transferSort,
    this.transferAscending = false,
    this.autoRefresh = true,
    this.transferLimit = 200,
  });

  final ThemeMode themeMode;

  /// Police de l'interface (nom d'`AppFont`) ; null : Inter.
  final String? font;
  final bool releasesGrid;

  /// Noms des critères de tri (enums définis côté interface).
  final String? releaseSort;
  final bool releaseAscending;
  final String? transferSort;
  final bool transferAscending;

  /// Transmission relu toutes les 2 s ; sinon, seulement à la demande.
  final bool autoRefresh;

  /// Torrents affichés au plus dans Transferts ; 0 : tous.
  final int transferLimit;

  UiPrefs copyWith({
    ThemeMode? themeMode,
    String? font,
    bool? releasesGrid,
    String? releaseSort,
    bool? releaseAscending,
    String? transferSort,
    bool? transferAscending,
    bool? autoRefresh,
    int? transferLimit,
  }) =>
      UiPrefs(
        themeMode: themeMode ?? this.themeMode,
        font: font ?? this.font,
        releasesGrid: releasesGrid ?? this.releasesGrid,
        releaseSort: releaseSort ?? this.releaseSort,
        releaseAscending: releaseAscending ?? this.releaseAscending,
        transferSort: transferSort ?? this.transferSort,
        transferAscending: transferAscending ?? this.transferAscending,
        autoRefresh: autoRefresh ?? this.autoRefresh,
        transferLimit: transferLimit ?? this.transferLimit,
      );
}

class UiPrefsNotifier extends Notifier<UiPrefs> {
  static const _themeKey = 'themeMode';
  static const _fontKey = 'font';
  static const _gridKey = 'releasesGrid';
  static const _releaseSortKey = 'releaseSort';
  static const _releaseAscKey = 'releaseAscending';
  static const _transferSortKey = 'transferSort';
  static const _transferAscKey = 'transferAscending';
  static const _autoRefreshKey = 'autoRefresh';
  static const _transferLimitKey = 'transferLimit';

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
      font: prefs.getString(_fontKey),
      releasesGrid: prefs.getBool(_gridKey) ?? true,
      releaseSort: prefs.getString(_releaseSortKey),
      releaseAscending: prefs.getBool(_releaseAscKey) ?? false,
      transferSort: prefs.getString(_transferSortKey),
      transferAscending: prefs.getBool(_transferAscKey) ?? false,
      autoRefresh: prefs.getBool(_autoRefreshKey) ?? true,
      transferLimit: prefs.getInt(_transferLimitKey) ?? 200,
    );
  }

  void setThemeMode(ThemeMode mode) {
    _prefs.setString(_themeKey, mode.name);
    state = state.copyWith(themeMode: mode);
  }

  void setFont(String font) {
    try {
      _prefs.setString(_fontKey, font);
    } on Object {
      // Préférences non initialisées (tests) : en mémoire seulement.
    }
    state = state.copyWith(font: font);
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

  void setAutoRefresh(bool on) {
    try {
      _prefs.setBool(_autoRefreshKey, on);
    } on Object {
      // Préférences non initialisées (tests) : en mémoire seulement.
    }
    state = state.copyWith(autoRefresh: on);
  }

  void setTransferLimit(int limit) {
    try {
      _prefs.setInt(_transferLimitKey, limit);
    } on Object {
      // Préférences non initialisées (tests) : en mémoire seulement.
    }
    state = state.copyWith(transferLimit: limit);
  }
}

final uiPrefsProvider =
    NotifierProvider<UiPrefsNotifier, UiPrefs>(UiPrefsNotifier.new);
