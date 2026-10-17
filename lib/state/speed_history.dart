import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'torrents.dart';

class SpeedSample {
  const SpeedSample(this.time, this.down, this.up);
  final DateTime time;
  final int down;
  final int up;
}

/// Historique des vitesses, enregistré par l'application à chaque
/// rafraîchissement de la liste (Transmission ne conserve aucun historique).
/// Il commence à l'ouverture de l'application et reste en mémoire.
class SpeedHistory {
  SpeedHistory(this.global, this.perTorrent, this.version);

  final ListQueue<SpeedSample> global;
  final Map<int, ListQueue<SpeedSample>> perTorrent;

  /// Change à chaque échantillon, pour notifier les écrans.
  final int version;
}

class SpeedHistoryNotifier extends Notifier<SpeedHistory> {
  /// 30 min d'historique global, 15 min par torrent (un point toutes les 2 s).
  static const globalWindow = Duration(minutes: 30);
  static const torrentWindow = Duration(minutes: 15);

  @override
  SpeedHistory build() {
    final history = SpeedHistory(ListQueue(), {}, 0);
    ref.listen(torrentsProvider, (_, next) {
      if (next.loaded) _record(next);
    });
    return history;
  }

  void _record(TorrentsState torrents) {
    final now = DateTime.now();
    final h = state;
    _push(h.global, SpeedSample(now, torrents.downloadRate, torrents.uploadRate),
        now.subtract(globalWindow));

    final limit = now.subtract(torrentWindow);
    for (final t in torrents.byId.values) {
      final series = h.perTorrent[t.id];
      // On ne commence une série qu'à la première activité : les torrents
      // inactifs ne coûtent rien.
      if (series == null && !t.isActive) continue;
      _push(h.perTorrent.putIfAbsent(t.id, ListQueue.new),
          SpeedSample(now, t.rateDownload, t.rateUpload), limit);
    }
    // Séries de torrents supprimés, ou restées à zéro sur toute la fenêtre.
    h.perTorrent.removeWhere((id, series) =>
        !torrents.byId.containsKey(id) ||
        series.every((s) => s.down == 0 && s.up == 0));

    state = SpeedHistory(h.global, h.perTorrent, h.version + 1);
  }

  static void _push(
      ListQueue<SpeedSample> series, SpeedSample sample, DateTime limit) {
    series.add(sample);
    while (series.isNotEmpty && series.first.time.isBefore(limit)) {
      series.removeFirst();
    }
  }
}

final speedHistoryProvider =
    NotifierProvider<SpeedHistoryNotifier, SpeedHistory>(
        SpeedHistoryNotifier.new);
