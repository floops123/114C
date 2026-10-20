import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/draupnirr.dart';
import '../api/tracker.dart';
import '../core/settings.dart';

/// Client Draupnirr authentifié par la clé de l'utilisateur. `null` si
/// aucune clé n'est saisie dans les Réglages ; l'onglet n'apparaît pas.
final draupnirrApiProvider = Provider<DraupnirrApi?>((ref) {
  final key = ref.watch(settingsProvider.select(
      (s) => s.value?.apiKeys[Tracker.draupnirr.name] ?? ''));
  if (key.isEmpty) return null;
  final api = DraupnirrApi(key);
  ref.onDispose(api.close);
  return api;
});

/// État de l'onglet Draupnirr (compte + missions).
class DraupnirrState {
  const DraupnirrState({
    this.account,
    this.missions = const [],
    this.badges = const [],
    this.loadedAt,
    this.loading = false,
    this.error,
  });

  final DraupnirrAccount? account;
  final List<DraupnirrMission> missions;
  final List<DraupnirrBadge> badges;
  final DateTime? loadedAt;
  final bool loading;
  final String? error;

  bool get hasData => account != null || missions.isNotEmpty || badges.isNotEmpty;

  DraupnirrState copyWith({
    DraupnirrAccount? account,
    List<DraupnirrMission>? missions,
    List<DraupnirrBadge>? badges,
    DateTime? loadedAt,
    bool? loading,
    String? Function()? error,
  }) =>
      DraupnirrState(
        account: account ?? this.account,
        missions: missions ?? this.missions,
        badges: badges ?? this.badges,
        loadedAt: loadedAt ?? this.loadedAt,
        loading: loading ?? this.loading,
        error: error != null ? error() : this.error,
      );
}

/// Notifier qui charge le compte et les missions à la première lecture de
/// l'onglet. Le rafraîchissement est ensuite manuel (« Actualiser »).
class DraupnirrNotifier extends Notifier<DraupnirrState> {
  @override
  DraupnirrState build() {
    final api = ref.watch(draupnirrApiProvider);
    if (api == null) return const DraupnirrState();
    // Premier chargement automatique à l'ouverture de l'onglet. Si le
    // notifier est reconstruit sans qu'on ouvre l'onglet (prefs qui
    // passent), le microtask ne lance rien : `ref.mounted` sera false.
    Future.microtask(refresh);
    return const DraupnirrState(loading: true);
  }

  /// Recharge le compte, les missions et les badges depuis Draupnirr.
  Future<void> refresh() async {
    final api = ref.read(draupnirrApiProvider);
    if (api == null) return;
    state = state.copyWith(loading: true, error: () => null);
    try {
      // Compte en premier pour qu'il s'affiche même si les missions
      // échouent. Badges : si l'endpoint n'existe pas (404 ou
      // structure différente), on continue sans crasher.
      final account = await api.me();
      if (!ref.mounted) return;
      state = state.copyWith(
        account: account,
        loadedAt: DateTime.now(),
      );
      try {
        final missions = await api.missions();
        if (!ref.mounted) return;
        state = state.copyWith(missions: missions);
      } on Object catch (e, st) {
        developer.log('Draupnirr missions KO', error: e, stackTrace: st);
      }
      try {
        final badges = await api.badges();
        if (!ref.mounted) return;
        state = state.copyWith(badges: badges);
      } on Object catch (e, st) {
        developer.log('Draupnirr badges KO', error: e, stackTrace: st);
      }
      state = state.copyWith(loading: false);
    } on Object catch (e, st) {
      developer.log('Draupnirr refresh KO', error: e, stackTrace: st);
      if (ref.mounted) {
        state = state.copyWith(loading: false, error: () => e.toString());
      }
    }
  }
}

final draupnirrProvider =
    NotifierProvider<DraupnirrNotifier, DraupnirrState>(DraupnirrNotifier.new);