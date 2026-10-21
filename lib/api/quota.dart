import 'dart:async';
import 'dart:collection';
import 'dart:io' show HttpDate, HttpException;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'tracker.dart';

/// Quota de requêtes d'un tracker : au plus [limit] requêtes sur toute
/// fenêtre glissante de [window]. Au-delà, la requête attend son tour au lieu
/// de se faire refuser ; les rafales restent permises tant qu'on est sous la
/// limite. Partagé par toute l'application : import en masse, veille,
/// disponibilité, cross-seed… puisent dans le même budget.
class RequestQuota {
  RequestQuota(
    this.limit, {
    this.window = const Duration(minutes: 1),
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
  })  : _clock = clock ?? DateTime.now,
        _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  final int limit;
  final Duration window;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleep;

  /// Départs des dernières requêtes, au plus [limit].
  final _sent = Queue<DateTime>();
  DateTime? _pausedUntil;
  Future<void> _tail = Future.value();

  /// Fin de l'attente en cours, pour l'interface ; null : pas d'attente.
  final waitingUntil = ValueNotifier<DateTime?>(null);

  /// Attend qu'une requête puisse partir, et la compte. Les demandes sont
  /// servies dans l'ordre d'arrivée.
  Future<void> acquire() {
    final turn = _tail.then((_) => _waitTurn());
    _tail = turn.catchError((Object _) {});
    return turn;
  }

  Future<void> _waitTurn() async {
    while (true) {
      final now = _clock();
      while (_sent.isNotEmpty && !now.isBefore(_sent.first.add(window))) {
        _sent.removeFirst();
      }
      final paused = _pausedUntil;
      final until = paused != null && now.isBefore(paused)
          ? paused
          : _sent.length >= limit
              ? _sent.first.add(window)
              : null;
      if (until == null) {
        _sent.addLast(now);
        waitingUntil.value = null;
        return;
      }
      waitingUntil.value = until;
      await _sleep(until.difference(now));
    }
  }

  /// Le tracker a refusé (HTTP 429) : plus aucune requête avant [delay].
  void pause(Duration delay) {
    final until = _clock().add(delay);
    if (_pausedUntil == null || until.isAfter(_pausedUntil!)) {
      _pausedUntil = until;
    }
  }
}

/// Un quota par tracker, sous la limite annoncée pour garder une marge (les
/// requêtes faites ailleurs avec la même clé, l'horloge du serveur).
final trackerQuotas = {
  for (final t in Tracker.values)
    t: RequestQuota((t.requestsPerMinute * 0.9).floor()),
};

/// Attente après un 429 sans en-tête `Retry-After` exploitable.
const defaultRetryAfter = Duration(seconds: 60);

/// Délai demandé par `Retry-After` (secondes ou date HTTP), sinon null.
/// L'en-tête peut être répété (C411 le fait, sans doute via un proxy) : on
/// retient le plus long des délais lisibles. Ne lève jamais.
Duration? retryAfter(Headers headers, {DateTime? now}) {
  Duration? longest;
  final at = now ?? DateTime.now();
  for (final raw in headers['retry-after'] ?? const <String>[]) {
    // Répétitions repliées en une ligne : « 7, 9 ». Une date HTTP contient
    // aussi une virgule : on la tente d'abord entière.
    final whole = _retryDelay(raw.trim(), at);
    for (final d in whole != null
        ? [whole]
        : [for (final part in raw.split(',')) _retryDelay(part.trim(), at)]) {
      if (d != null && (longest == null || d > longest)) longest = d;
    }
  }
  return longest;
}

Duration? _retryDelay(String value, DateTime now) {
  if (value.isEmpty) return null;
  final seconds = int.tryParse(value);
  if (seconds != null) return Duration(seconds: seconds.clamp(0, 3600));
  try {
    final d = HttpDate.parse(value).difference(now);
    return d.isNegative ? Duration.zero : d;
  } on HttpException {
    return null;
  } on FormatException {
    return null;
  }
}

/// Envoie une requête vers [tracker] dans le respect de son quota. Sur un
/// 429, le quota est suspendu le temps demandé et la requête refaite
/// ([retries] fois) ; la réponse est rendue telle quelle, à l'appelant d'en
/// interpréter le statut.
Future<Response<T>> trackerRequest<T>(
  Tracker tracker,
  Future<Response<T>> Function() send, {
  int retries = 1,
}) async {
  final quota = trackerQuotas[tracker]!;
  for (var attempt = 0;; attempt++) {
    await quota.acquire();
    final res = await send();
    if (res.statusCode != 429 || attempt >= retries) return res;
    quota.pause(retryAfter(res.headers) ?? defaultRetryAfter);
  }
}
