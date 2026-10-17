import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/transmission.dart';

class TorrentsState {
  const TorrentsState({
    this.byId = const {},
    this.hashes = const {},
    this.loaded = false,
    this.error,
  });

  final Map<int, Torrent> byId;
  final Set<String> hashes;
  final bool loaded;
  final String? error;

  int get downloadRate =>
      byId.values.fold(0, (sum, t) => sum + t.rateDownload);
  int get uploadRate => byId.values.fold(0, (sum, t) => sum + t.rateUpload);
}

/// Interroge Transmission toutes les 2 s. Seuls les torrents actifs récemment
/// sont redemandés (`recently-active`) ; une liste complète est rechargée
/// régulièrement et après chaque action pour rester cohérent.
class TorrentsNotifier extends Notifier<TorrentsState> {
  static const _interval = Duration(seconds: 2);
  static const _fullEvery = 15;

  Timer? _timer;
  bool _busy = false;
  int _tick = 0;

  @override
  TorrentsState build() {
    final client = ref.watch(transmissionProvider);
    ref.onDispose(() => _timer?.cancel());
    if (client == null) return const TorrentsState();
    _timer = Timer.periodic(_interval, (_) => refresh());
    Future.microtask(() => refresh(full: true));
    return const TorrentsState();
  }

  Future<void> refresh({bool full = false}) async {
    final client = ref.read(transmissionProvider);
    if (client == null || _busy) return;
    _busy = true;
    try {
      full = full || !state.loaded || ++_tick % _fullEvery == 0;
      final result = await client.torrentGet(
        TransmissionClient.listFields,
        ids: full ? null : 'recently-active',
      );
      if (!ref.mounted) return;
      final map = full ? <int, Torrent>{} : Map.of(state.byId);
      for (final json in result.torrents) {
        final id = (json['id'] as num).toInt();
        final previous = map[id];
        map[id] = previous == null ? Torrent(json) : previous.merge(json);
      }
      result.removed.forEach(map.remove);
      state = TorrentsState(
        byId: map,
        hashes: {for (final t in map.values) t.hash},
        loaded: true,
      );
    } on TransmissionException catch (e) {
      if (ref.mounted) {
        state = TorrentsState(
            byId: state.byId,
            hashes: state.hashes,
            loaded: state.loaded,
            error: e.message);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> run(Future<void> Function(TransmissionClient c) action) async {
    final client = ref.read(transmissionProvider);
    if (client == null) return;
    await action(client);
    await refresh(full: true);
  }
}

final torrentsProvider =
    NotifierProvider<TorrentsNotifier, TorrentsState>(TorrentsNotifier.new);

/// Détail complet d'un torrent, rafraîchi tant que l'écran est ouvert.
final torrentDetailProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, int>((ref, id) async* {
  final client = ref.watch(transmissionProvider);
  if (client == null) return;
  while (true) {
    final r = await client.torrentGet(TransmissionClient.detailFields, ids: [id]);
    yield r.torrents.isEmpty ? null : r.torrents.first;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
});
