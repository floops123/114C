import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Événement reçu sur le WebSocket (paquet Socket.IO `EVENT`).
class SocketEvent {
  SocketEvent(this.name, this.args, this.receivedAt);
  final String name;
  final List<Object?> args;
  final DateTime receivedAt;

  Object? get data => args.isEmpty ? null : args.first;
}

/// Accepte l'en-tête complet (`Cookie: a=1; b=2`) ou sa seule valeur, et
/// supprime retours à la ligne et espaces superflus.
String normalizeCookie(String raw) {
  var v = raw.trim();
  if (v.toLowerCase().startsWith('cookie:')) v = v.substring(7);
  return v
      .split(RegExp(r'[;\n\r]+'))
      .map((p) => p.trim())
      .where((p) => p.contains('='))
      .join('; ');
}

enum SocketStatus {
  disconnected('Déconnecté'),
  connecting('Connexion…'),
  connected('Connecté'),

  /// Cookie absent, invalide ou expiré : inutile de réessayer.
  unauthorized('Session refusée');

  const SocketStatus(this.label);
  final String label;
}

/// Client Socket.IO minimal (Engine.IO v4, transport WebSocket uniquement)
/// pour `wss://c411.org/ws/`. Le serveur exige l'en-tête `Origin` du site et
/// le cookie de session du navigateur (la clé API n'est pas acceptée).
///
/// Protocole : `0{…}` ouverture → on envoie `40` (connexion au namespace) →
/// `40{…}` accepté ou `44{…}` refusé ; `2` ping → `3` pong ;
/// `42["événement", …]` événement.
class C411Socket {
  C411Socket(this.cookie,
      {Uri? url, this.onStatus, this.onEvent, this.onError})
      : url = url ?? defaultUrl;

  static final defaultUrl =
      Uri.parse('wss://c411.org/ws/?EIO=4&transport=websocket');

  /// Adresse du WebSocket (modifiable pour les tests).
  final Uri url;
  static const origin = 'https://c411.org';

  /// Valeur de l'en-tête Cookie (ex. `nom=valeur; autre=valeur`).
  final String cookie;
  final void Function(SocketStatus status)? onStatus;
  final void Function(SocketEvent event)? onEvent;
  final void Function(String message)? onError;

  WebSocket? _ws;
  Timer? _retry;
  Timer? _watchdog;
  Duration _pingTimeout = const Duration(seconds: 60);
  Duration _pingInterval = const Duration(seconds: 25);
  int _attempt = 0;
  bool _closed = false;
  int _nextAck = 0;
  final _acks = <int, Completer<Object?>>{};
  SocketStatus _status = SocketStatus.disconnected;

  SocketStatus get status => _status;

  void _setStatus(SocketStatus s) {
    if (_status == s) return;
    _status = s;
    onStatus?.call(s);
  }

  Future<void> connect() async {
    if (_closed) return;
    _retry?.cancel();
    _setStatus(SocketStatus.connecting);
    try {
      final ws = await WebSocket.connect(url.toString(), headers: {
        'Origin': origin,
        'Cookie': cookie,
      }).timeout(const Duration(seconds: 15));
      if (_closed) {
        await ws.close();
        return;
      }
      _ws = ws;
      ws.listen(
        (m) => _onMessage(m is String ? m : utf8.decode(m as List<int>)),
        onDone: _onDone,
        onError: (Object e) => onError?.call('$e'),
        cancelOnError: true,
      );
    } catch (e) {
      onError?.call('Connexion impossible : $e');
      _scheduleRetry();
    }
  }

  void _onMessage(String m) {
    _resetWatchdog();
    if (m.isEmpty) return;
    switch (m[0]) {
      case '0': // ouverture Engine.IO
        final open = jsonDecode(m.substring(1)) as Map<String, dynamic>;
        _pingInterval = Duration(
            milliseconds: (open['pingInterval'] as num?)?.toInt() ?? 25000);
        _pingTimeout = Duration(
            milliseconds: (open['pingTimeout'] as num?)?.toInt() ?? 60000);
        _ws?.add('40');
      case '2': // ping du serveur
        _ws?.add('3');
      case '1': // fermeture demandée
        _ws?.close();
      case '4':
        _onSocketIo(m.substring(1));
    }
  }

  void _onSocketIo(String p) {
    if (p.isEmpty) return;
    switch (p[0]) {
      case '0': // CONNECT accepté
        _attempt = 0;
        _setStatus(SocketStatus.connected);
      case '4': // CONNECT_ERROR
        final err = _json(p.substring(1));
        var message = p;
        Object? code;
        if (err is Map) {
          message = '${err['message']}';
          final data = err['data'];
          if (data is Map) code = data['code'];
        }
        onError?.call('C411 : $message${code != null ? ' ($code)' : ''}');
        _setStatus(SocketStatus.unauthorized);
        _closed = true;
        _ws?.close();
      case '2': // EVENT, éventuellement avec namespace « /ns, » et id d'ack
        final start = p.indexOf('[');
        if (start < 0) return;
        final payload = _json(p.substring(start));
        if (payload is List && payload.isNotEmpty) {
          onEvent?.call(SocketEvent(
              '${payload.first}', payload.skip(1).toList(), DateTime.now()));
        }
      case '3': // ACK : `3<id>[réponse]`
        final start = p.indexOf('[');
        final id = int.tryParse(p.substring(1, start < 0 ? p.length : start));
        final payload = start < 0 ? null : _json(p.substring(start));
        final completer = id == null ? null : _acks.remove(id);
        completer?.complete(
            payload is List && payload.isNotEmpty ? payload.first : null);
      case '1': // DISCONNECT du namespace
        _ws?.close();
    }
  }

  static Object? _json(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }

  /// Sans ping du serveur dans le délai prévu, la connexion est morte.
  void _resetWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_pingInterval + _pingTimeout, () => _ws?.close());
  }

  void _onDone() {
    _watchdog?.cancel();
    _ws = null;
    _failAcks('Connexion perdue');
    if (_status != SocketStatus.unauthorized) {
      _setStatus(SocketStatus.disconnected);
      _scheduleRetry();
    }
  }

  /// Reconnexion avec délai croissant : 2 s, 4 s, 8 s… plafonné à 2 min.
  void _scheduleRetry() {
    if (_closed) return;
    _setStatus(SocketStatus.disconnected);
    final delay = Duration(seconds: math.min(120, 2 << math.min(_attempt, 6)));
    _attempt++;
    _retry = Timer(delay, connect);
  }

  /// Émet un événement Socket.IO (`42["événement", données]`). Ignoré si la
  /// connexion n'est pas établie.
  void emit(String event, [Object? data]) {
    if (_status != SocketStatus.connected) return;
    _ws?.add('42${jsonEncode([event, ?data])}');
  }

  /// Émet un événement en demandant un accusé de réception
  /// (`42<id>["événement", données]` → `43<id>[réponse]`) et renvoie la
  /// réponse du serveur.
  Future<Object?> emitWithAck(String event, Object? data,
      {Duration timeout = const Duration(seconds: 15)}) {
    if (_status != SocketStatus.connected || _ws == null) {
      return Future.error(const SocketException('Non connecté'));
    }
    final id = _nextAck++;
    final completer = Completer<Object?>();
    _acks[id] = completer;
    _ws!.add('42$id${jsonEncode([event, data])}');
    return completer.future.timeout(timeout, onTimeout: () {
      _acks.remove(id);
      throw const SocketException('Pas de réponse du serveur');
    });
  }

  void _failAcks(String reason) {
    for (final c in _acks.values) {
      if (!c.isCompleted) c.completeError(SocketException(reason));
    }
    _acks.clear();
  }

  Future<void> close() async {
    _failAcks('Connexion fermée');
    _closed = true;
    _retry?.cancel();
    _watchdog?.cancel();
    await _ws?.close();
    _ws = null;
  }
}
