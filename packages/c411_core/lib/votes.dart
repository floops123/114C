import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Votes « j'aime / je n'aime pas » des serveurs web (watch, listen, read),
/// et favoris de chaque membre : **ses favoris sont ce qu'il a aimé** (👍),
/// du plus récent au plus ancien.
///
/// Anonymes : on ne garde pas le nom du membre, seulement son empreinte
/// (HMAC-SHA256 avec une clé propre au serveur). On sait ainsi qu'il a déjà
/// voté, et pour quoi, sans pouvoir dire qui il est ; les autres ne voient
/// que les totaux.
///
/// Le membre est celui qu'annonce le proxy (`Remote-User`, posé par Caddy
/// après la connexion Authelia). Sans cet en-tête (accès direct au
/// serveur), on voit les totaux mais on ne vote pas.
///
/// Fichier JSON `{"votes": {"<élément>": {"<empreinte>": 1 | -1}},
/// "likes": {"<empreinte>": ["<élément>", …]}}` (ordre des « j'aime »), écrit
/// par renommage ; la clé est à côté (`<fichier>.key`, lisible du seul
/// propriétaire), créée au premier lancement. L'ancien format (les votes
/// seuls, sans ordre) est relu.
class Votes {
  Votes(this.path) : _key = _loadKey('$path.key') {
    try {
      final json = jsonDecode(File(path).readAsStringSync()) as Map;
      final votes = json['votes'] is Map && json['likes'] is Map ? json['votes'] as Map : json;
      for (final MapEntry(:key, :value) in votes.entries) {
        if (value is Map) {
          _votes['$key'] = {
            for (final MapEntry(key: k, value: v) in value.entries)
              if (v == 1 || v == -1) '$k': v as int,
          };
        }
      }
      for (final MapEntry(:key, :value) in ((json['likes'] as Map?) ?? const {}).entries) {
        if (value is List) _likes['$key'] = [for (final v in value) '$v'];
      }
    } on Object {
      // Pas encore de votes (ou fichier illisible : on repart de zéro).
    }
    // « J'aime » sans ordre connu (ancien format) : à la fin.
    for (final MapEntry(key: item, value: votes) in _votes.entries) {
      for (final MapEntry(key: voter, value: v) in votes.entries) {
        final list = _likes[voter] ??= [];
        if (v == 1 && !list.contains(item)) list.add(item);
      }
    }
  }

  final String path;
  final List<int> _key;
  final _votes = <String, Map<String, int>>{};
  final _likes = <String, List<String>>{};

  static const header = 'remote-user';

  static List<int> _loadKey(String path) {
    final file = File(path);
    try {
      final text = file.readAsStringSync().trim();
      if (text.length >= 32) return utf8.encode(text);
    } on FileSystemException {
      // Première fois.
    }
    final random = Random.secure();
    final text = base64Url.encode(List.generate(32, (_) => random.nextInt(256)));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
    if (!Platform.isWindows) Process.runSync('chmod', ['600', path]);
    return utf8.encode(text);
  }

  String _voter(String user) => Hmac(sha256, _key).convert(utf8.encode('vote:$user')).toString().substring(0, 32);

  /// [pour, contre, mon vote (1, -1 ou 0)] d'un élément.
  List<int> tally(String item, String? user) {
    final votes = _votes[item] ?? const {};
    var up = 0, down = 0;
    for (final v in votes.values) {
      if (v > 0) {
        up++;
      } else {
        down++;
      }
    }
    return [up, down, user == null ? 0 : votes[_voter(user)] ?? 0];
  }

  /// Tous les éléments qui ont au moins un vote.
  Map<String, List<int>> all(String? user) => {
        for (final item in _votes.keys)
          if (_votes[item]!.isNotEmpty) item: tally(item, user),
      };

  /// Les favoris de [user] : ce qu'il a aimé, du plus récent au plus ancien.
  List<String> liked(String user) => List.unmodifiable(_likes[_voter(user)] ?? const []);

  /// Vote de [user] : 1 (pour, et favori), -1 (contre) ou 0 (retiré).
  List<int> vote(String item, String user, int value) {
    final voter = _voter(user);
    final votes = _votes[item] ??= {};
    if (value == 0) {
      votes.remove(voter);
      if (votes.isEmpty) _votes.remove(item);
    } else {
      votes[voter] = value.sign;
    }
    final likes = _likes[voter] ??= [];
    likes.remove(item);
    if (value > 0) likes.insert(0, item);
    if (likes.isEmpty) _likes.remove(voter);
    _save();
    return tally(item, user);
  }

  void _save() {
    final tmp = File('$path.tmp');
    tmp.parent.createSync(recursive: true);
    tmp.writeAsStringSync(jsonEncode({'votes': _votes, 'likes': _likes}));
    tmp.renameSync(path);
  }

  /// Routes communes aux trois serveurs ; false si la requête n'est pas
  /// pour elles :
  /// - `GET /api/votes` → `{"user": bool, "items": {id: [pour, contre, mien]}}` ;
  /// - `GET /api/favorites` → `{"user": bool, "items": [id, …]}` : ce que le
  ///   membre a aimé, plus récent d'abord ;
  /// - `POST /api/vote/<id>`, corps JSON `{"value": 1 | -1 | 0}` → `[pour, contre, mien]`.
  ///
  /// Le POST exige un corps JSON (une page d'un autre site ne peut pas en
  /// envoyer sans l'accord du serveur) et un élément qui existe ([exists]) ;
  /// retirer son vote d'un élément disparu reste permis.
  Future<bool> serve(HttpRequest request, {required bool Function(String id) exists}) async {
    final s = request.uri.pathSegments;
    if (s.length < 2 || s[0] != 'api' || !const {'votes', 'vote', 'favorites'}.contains(s[1])) return false;
    final user = request.headers.value(header)?.trim();
    final who = user == null || user.isEmpty ? null : user;
    final response = request.response;
    Future<bool> reply(Object data, [int status = HttpStatus.ok]) async {
      response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..write(jsonEncode(data));
      await response.close();
      return true;
    }

    final get = request.method == 'GET' && s.length == 2;
    if (get && s[1] == 'votes') return reply({'user': who != null, 'items': all(who)});
    if (get && s[1] == 'favorites') return reply({'user': who != null, 'items': who == null ? const [] : liked(who)});
    if (s[1] != 'vote' || s.length != 3 || request.method != 'POST') {
      return reply({'error': 'méthode'}, HttpStatus.methodNotAllowed);
    }
    if (who == null) return reply({'error': 'connexion requise pour voter'}, HttpStatus.forbidden);
    if (request.headers.contentType?.mimeType != 'application/json') {
      return reply({'error': 'JSON attendu'}, HttpStatus.unsupportedMediaType);
    }
    Object? value;
    try {
      final body = await utf8.decoder.bind(request).join();
      value = body.length > 1000 ? null : (jsonDecode(body) as Map)['value'];
    } on Object {
      value = null;
    }
    if (value != 1 && value != -1 && value != 0) return reply({'error': 'value : 1, -1 ou 0'}, HttpStatus.badRequest);
    if (s[2].length > 64 || (value != 0 && !exists(s[2]))) return reply({'error': 'inconnu'}, HttpStatus.notFound);
    return reply(vote(s[2], who, value as int));
  }
}
