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

/// Le site recalcule la journée en cours régulièrement ; inutile d'insister.
const refreshEvery = Duration(minutes: 10);
