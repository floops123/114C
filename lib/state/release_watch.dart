import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/tracker.dart';
import '../core/preferences.dart';

// Veille des nouveautés : toutes les `WatchConfig.minutes`, la première page
// (par date) de chaque tracker surveillé est comparée aux sorties déjà vues ;
// les nouvelles entrent dans la liste et, si demandé, déclenchent une
// notification système. Tourne tant que l'application est ouverte.

/// Réglages de la veille (préférences, appliqués sans « Enregistrer »).
class WatchConfig {
  const WatchConfig({
    this.enabled = false,
    this.minutes = 15,
    this.trackers,
    this.notify = true,
  });

  /// Intervalles proposés, en minutes.
  static const choices = [5, 10, 15, 30, 60, 120, 240];

  final bool enabled;
  final int minutes;

  /// Trackers surveillés ; null = tous les trackers configurés.
  final Set<Tracker>? trackers;

  /// Notification système à l'arrivée de nouvelles sorties.
  final bool notify;

  bool watches(Tracker t) => trackers == null || trackers!.contains(t);

  WatchConfig copyWith({
    bool? enabled,
    int? minutes,
    Set<Tracker>? Function()? trackers,
    bool? notify,
  }) =>
      WatchConfig(
        enabled: enabled ?? this.enabled,
        minutes: minutes ?? this.minutes,
        trackers: trackers != null ? trackers() : this.trackers,
        notify: notify ?? this.notify,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'minutes': minutes,
        'trackers': trackers?.map((t) => t.name).toList(),
        'notify': notify,
      };

  factory WatchConfig.fromJson(Map<String, dynamic> json) {
    final names = json['trackers'] as List?;
    final byName = Tracker.values.asNameMap();
    return WatchConfig(
      enabled: json['enabled'] as bool? ?? false,
      minutes: (json['minutes'] as num?)?.toInt() ?? 15,
      trackers: names == null
          ? null
          : {for (final n in names) ?byName[n]},
      notify: json['notify'] as bool? ?? true,
    );
  }
}

class WatchConfigNotifier extends Notifier<WatchConfig> {
  static const key = 'releaseWatchConfig';

  @override
  WatchConfig build() {
    try {
      final raw = ref.watch(sharedPrefsProvider).getString(key);
      if (raw != null) {
        return WatchConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } on Object {
      // Préférences non initialisées (tests) ou illisibles : défaut.
    }
    return const WatchConfig();
  }

  void set(WatchConfig config) {
    try {
      ref.read(sharedPrefsProvider).setString(key, jsonEncode(config.toJson()));
    } on Object {
      // Préférences non initialisées (tests) : en mémoire seulement.
    }
    state = config;
  }
}

final watchConfigProvider =
    NotifierProvider<WatchConfigNotifier, WatchConfig>(WatchConfigNotifier.new);

/// Une sortie repérée par la veille.
class WatchedRelease {
  const WatchedRelease({
    required this.release,
    required this.foundAt,
    this.isNew = true,
  });

  final Release release;
  final DateTime foundAt;

  /// Pas encore vue dans la page Nouveautés.
  final bool isNew;

  String get key => watchKey(release);

  WatchedRelease seen() =>
      WatchedRelease(release: release, foundAt: foundAt, isNew: false);

  Map<String, Object?> toJson() {
    final r = release;
    return {
      'tracker': r.tracker.name,
      'id': r.id,
      'name': r.name,
      'hash': r.infoHash,
      'url': r.downloadUrl,
      'title': r.title,
      'year': r.year,
      'sub': r.subcategory,
      'cats': r.categories,
      'size': r.size,
      'seeders': r.seeders,
      'leechers': r.leechers,
      'created': r.createdAt.toIso8601String(),
      'poster': r.posterUrl,
      'quality': r.qualityProfile,
      'kind': r.mediaKind,
      'found': foundAt.toIso8601String(),
      'new': isNew,
    };
  }

  /// Null si le tracker n'existe plus.
  static WatchedRelease? fromJson(Map<String, dynamic> j) {
    final tracker = Tracker.values.asNameMap()[j['tracker']];
    if (tracker == null) return null;
    return WatchedRelease(
      release: Release(
        tracker: tracker,
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        infoHash: j['hash'] as String?,
        downloadUrl: j['url'] as String?,
        title: j['title'] as String?,
        year: (j['year'] as num?)?.toInt(),
        subcategory: j['sub'] as String? ?? '',
        categories: [...?(j['cats'] as List?)?.whereType<String>()],
        size: (j['size'] as num?)?.toInt() ?? 0,
        seeders: (j['seeders'] as num?)?.toInt() ?? 0,
        leechers: (j['leechers'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(j['created'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        posterUrl: j['poster'] as String?,
        qualityProfile: j['quality'] as String?,
        mediaKind: j['kind'] as String?,
      ),
      foundAt: DateTime.tryParse(j['found'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isNew: j['new'] as bool? ?? false,
    );
  }
}

String watchKey(Release r) => '${r.tracker.name}:${r.id}';

/// Ce que la veille garde d'une session à l'autre.
class WatchData {
  const WatchData({
    this.items = const [],
    this.known = const [],
    this.baselined = const {},
    this.lastCheck,
  });

  /// Les plus récentes d'abord.
  final List<WatchedRelease> items;

  /// Clés des sorties déjà rencontrées, plus récentes à la fin. Distinctes de
  /// [items] pour qu'une sortie sortie de la liste ne revienne pas « nouvelle ».
  final List<String> known;

  /// Trackers déjà relevés une fois : au premier relevé, leurs sorties
  /// entrent dans la liste sans être signalées comme nouvelles.
  final Set<Tracker> baselined;
  final DateTime? lastCheck;

  Map<String, Object?> toJson() => {
        'items': [for (final i in items) i.toJson()],
        'known': known,
        'baselined': [for (final t in baselined) t.name],
        'lastCheck': lastCheck?.toIso8601String(),
      };

  factory WatchData.fromJson(Map<String, dynamic> j) {
    final byName = Tracker.values.asNameMap();
    return WatchData(
      items: [
        for (final i in (j['items'] as List? ?? const []).whereType<Map>())
          ?WatchedRelease.fromJson(i.cast<String, dynamic>()),
      ],
      known: [...?(j['known'] as List?)?.whereType<String>()],
      baselined: {
        for (final n in (j['baselined'] as List? ?? const [])) ?byName[n],
      },
      lastCheck: DateTime.tryParse(j['lastCheck'] as String? ?? ''),
    );
  }
}

abstract class WatchStore {
  WatchData load();
  void save(WatchData data);
}

class PrefsWatchStore implements WatchStore {
  PrefsWatchStore(this._prefs);
  final SharedPreferencesWithCache _prefs;
  static const key = 'releaseWatch';

  @override
  WatchData load() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return const WatchData();
      return WatchData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const WatchData();
    }
  }

  @override
  void save(WatchData data) => _prefs.setString(key, jsonEncode(data.toJson()));
}

class MemoryWatchStore implements WatchStore {
  WatchData data = const WatchData();
  @override
  WatchData load() => data;
  @override
  void save(WatchData data) => this.data = data;
}

final watchStoreProvider = Provider<WatchStore>((ref) {
  try {
    return PrefsWatchStore(ref.watch(sharedPrefsProvider));
  } on Object {
    return MemoryWatchStore(); // Préférences non initialisées (tests).
  }
});

/// Notifications du système (libnotify sous Linux, Android…).
abstract class SystemNotifier {
  /// Demande l'autorisation d'afficher des notifications (Android 13+).
  Future<bool> requestPermission();

  /// Remplace la notification de veille précédente.
  Future<void> show(String title, String body);
}

class LocalSystemNotifier implements SystemNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  static const _id = 411;
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'releaseWatch',
      'Nouveaux torrents',
      channelDescription: 'Sorties repérées par la veille des trackers',
    ),
    linux: LinuxNotificationDetails(),
  );

  Future<bool> _init() async {
    try {
      return await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              linux: LinuxInitializationSettings(defaultActionName: 'Ouvrir'),
              iOS: DarwinInitializationSettings(),
              macOS: DarwinInitializationSettings(),
            ),
          ) ??
          false;
    } on Object catch (e) {
      debugPrint('Notifications système indisponibles : $e');
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!await (_ready ??= _init())) return false;
    try {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> show(String title, String body) async {
    if (!await (_ready ??= _init())) return;
    try {
      await _plugin.show(
          id: _id, title: title, body: body, notificationDetails: _details);
    } on Object catch (e) {
      debugPrint('Notification non affichée : $e');
    }
  }
}

final systemNotifierProvider =
    Provider<SystemNotifier>((ref) => LocalSystemNotifier());

/// Horloge, remplacée dans les tests.
final watchClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class WatchState {
  const WatchState({
    this.items = const [],
    this.lastCheck,
    this.checking = false,
    this.errors = const {},
  });

  final List<WatchedRelease> items;
  final DateTime? lastCheck;
  final bool checking;

  /// Échec du dernier relevé, par tracker.
  final Map<Tracker, String> errors;

  int get unseen => items.where((i) => i.isNew).length;

  WatchState copyWith({
    List<WatchedRelease>? items,
    DateTime? lastCheck,
    bool? checking,
    Map<Tracker, String>? errors,
  }) =>
      WatchState(
        items: items ?? this.items,
        lastCheck: lastCheck ?? this.lastCheck,
        checking: checking ?? this.checking,
        errors: errors ?? this.errors,
      );
}

class ReleaseWatchNotifier extends Notifier<WatchState> {
  /// Sorties demandées à chaque tracker par relevé.
  static const perPage = 50;

  /// Taille de la liste affichée.
  static const maxItems = 300;

  /// Clés mémorisées : largement plus que trackers × [perPage].
  static const maxKnown = 3000;

  /// Fréquence à laquelle on regarde si un relevé est dû : un intervalle
  /// changé, ou une mise en veille de la machine, sont pris en compte sans
  /// attendre la fin d'un long minuteur.
  static const tick = Duration(minutes: 1);

  Timer? _timer;
  bool _checking = false;

  WatchStore get _store => ref.read(watchStoreProvider);

  @override
  WatchState build() {
    final config = ref.watch(watchConfigProvider);
    final trackers = ref.watch(trackersProvider);
    final data = ref.watch(watchStoreProvider).load();
    _timer?.cancel();
    _timer = null;
    if (config.enabled && trackers.keys.any(config.watches)) {
      _timer = Timer.periodic(tick, (_) => _checkIfDue());
      Future.microtask(_checkIfDue);
    }
    ref.onDispose(() => _timer?.cancel());
    return WatchState(items: data.items, lastCheck: data.lastCheck);
  }

  /// Relevé dû : jamais fait, ou plus vieux que l'intervalle choisi.
  bool isDue(DateTime now) {
    final last = state.lastCheck;
    final minutes = ref.read(watchConfigProvider).minutes;
    return last == null || now.difference(last).inMinutes >= minutes;
  }

  Future<void> _checkIfDue() async {
    if (!ref.mounted || !ref.read(watchConfigProvider).enabled) return;
    if (isDue(ref.read(watchClockProvider)())) await check();
  }

  /// Relève les trackers surveillés et renvoie le nombre de nouvelles sorties.
  Future<int> check() async {
    if (_checking) return 0;
    final config = ref.read(watchConfigProvider);
    final all = ref.read(trackersProvider);
    final targets = [for (final t in all.keys) if (config.watches(t)) t];
    if (targets.isEmpty) return 0;
    final clock = ref.read(watchClockProvider);
    final store = _store;

    _checking = true;
    state = state.copyWith(checking: true);
    final results = await Future.wait([
      for (final t in targets)
        () async {
          try {
            final page = await all[t]!.releases(
              perPage: perPage,
              sort: ReleaseSort.date,
            );
            return (t, page.items, null);
          } on Object catch (e) {
            return (t, null, '$e');
          }
        }(),
    ]);
    _checking = false;
    if (!ref.mounted) return 0;

    final now = clock();
    final data = store.load();
    final known = {...data.known};
    final added = <String>[];
    final baselined = {...data.baselined};
    final errors = <Tracker, String>{};
    final fresh = <WatchedRelease>[];
    for (final (t, items, failure) in results) {
      if (items == null) {
        errors[t] = failure!;
        continue;
      }
      final first = !baselined.contains(t);
      baselined.add(t);
      for (final r in items) {
        final key = watchKey(r);
        if (!known.add(key)) continue;
        added.add(key);
        fresh.add(WatchedRelease(release: r, foundAt: now, isNew: !first));
      }
    }
    fresh.sort((a, b) => b.release.createdAt.compareTo(a.release.createdAt));

    final items = [...fresh, ...data.items].take(maxItems).toList();
    final allKnown = [...data.known, ...added];
    final next = WatchData(
      items: items,
      known: allKnown.length > maxKnown
          ? allKnown.sublist(allKnown.length - maxKnown)
          : allKnown,
      baselined: baselined,
      lastCheck: now,
    );
    store.save(next);
    state = WatchState(items: items, lastCheck: now, errors: errors);

    final arrivals = [for (final f in fresh) if (f.isNew) f];
    if (arrivals.isNotEmpty && config.notify) {
      await ref
          .read(systemNotifierProvider)
          .show(notificationTitle(arrivals), notificationBody(arrivals));
    }
    return arrivals.length;
  }

  /// La page Nouveautés a été ouverte : plus rien n'est « nouveau ».
  void markAllSeen() {
    if (state.unseen == 0) return;
    final items = [for (final i in state.items) i.isNew ? i.seen() : i];
    final data = _store.load();
    _store.save(WatchData(
      items: items,
      known: data.known,
      baselined: data.baselined,
      lastCheck: data.lastCheck,
    ));
    state = state.copyWith(items: items);
  }

  /// Vide la liste. Les sorties déjà vues restent connues : elles ne
  /// reviendront pas comme nouvelles au prochain relevé.
  void clear() {
    final data = _store.load();
    _store.save(WatchData(
      known: data.known,
      baselined: data.baselined,
      lastCheck: data.lastCheck,
    ));
    state = state.copyWith(items: const []);
  }
}

String notificationTitle(List<WatchedRelease> arrivals) {
  final trackers = {for (final a in arrivals) a.release.tracker};
  final where = trackers.length == 1 ? ' sur ${trackers.single.label}' : '';
  return arrivals.length == 1
      ? 'Nouveau torrent$where'
      : '${arrivals.length} nouveaux torrents$where';
}

String notificationBody(List<WatchedRelease> arrivals) {
  const shown = 4;
  return [
    for (final a in arrivals.take(shown)) a.release.name,
    if (arrivals.length > shown) 'et ${arrivals.length - shown} autres…',
  ].join('\n');
}

final releaseWatchProvider =
    NotifierProvider<ReleaseWatchNotifier, WatchState>(
        ReleaseWatchNotifier.new);
