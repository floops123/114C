import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/c411_profile.dart';
import 'palliative.dart';

/// Compte, niveau et Zen de C411 (cookie de session), relus toutes les
/// [refreshEvery] et à la demande (`ref.refresh(c411OverviewProvider.future)`).
/// null : pas de cookie de session.
final c411OverviewProvider = FutureProvider<C411Overview?>((ref) async {
  final api = ref.watch(c411SiteApiProvider);
  if (api == null) return null;
  final timer = Timer(refreshEvery, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return api.overview();
});

/// Bonus Zen du compte (grille et arbre) que le site applique aujourd'hui,
/// sinon au dernier versement ; null : inconnu (pas de cookie de session).
final zenBonusProvider = Provider<double?>((ref) {
  final o = ref.watch(c411OverviewProvider).value;
  final bp = o?.forecast?.today.bonusBp ?? o?.history?.latest?.bonusBp;
  return bp == null ? null : bp / 10000;
});

/// Part de la journée où les torrents sont partagés en moyenne (7 derniers
/// versements) ; null : inconnue. La journée en cours, incomplète, n'y est
/// pas.
final zenShareProvider = Provider<double?>((ref) {
  return ref.watch(c411OverviewProvider).value?.history?.shareOver()?.clamp(0.0, 1.0);
});

/// Le site recalcule la journée en cours régulièrement ; inutile d'insister.
const refreshEvery = Duration(minutes: 10);
