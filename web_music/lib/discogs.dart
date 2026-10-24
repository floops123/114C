import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:c411_core/music_name.dart';
import 'package:c411_core/titles.dart';

import 'library.dart';

/// Client de l'API Discogs (https://www.discogs.com/developers/), avec un
/// jeton personnel (discogs.com → Réglages → Développeurs).
///
/// Deux usages, après MusicBrainz qui reste la source principale :
/// - [find] : un album que MusicBrainz ne connaît pas (fiche convertie en
///   [MbRelease], pistes comprises) ;
/// - [complete] : la pochette et les styles d'un album que MusicBrainz
///   connaît sans pochette ou sans genres.
///
/// Ses règles : un User-Agent qui dit qui appelle, 60 requêtes par minute
/// avec un jeton. Jamais d'exception : en panne ou saturé, null, et
/// l'identification continue avec ce qu'elle a.
class Discogs {
  Discogs({
    required String contact,
    required String token,
    HttpClient? http,
    this.base = 'https://api.discogs.com',
    this.interval = const Duration(milliseconds: 1100),
  })  : userAgent = 'C411Music/1.0 +$contact',
        token = token.trim().replaceFirst(RegExp(r'^Discogs token=', caseSensitive: false), ''),
        _http = http ?? HttpClient();

  final String userAgent;
  final String token;
  final String base;

  /// Écart minimal entre deux requêtes (60 par minute permises).
  final Duration interval;
  final HttpClient _http;
  Future<void> _queue = Future.value();
  DateTime _last = DateTime(2000);

  /// Discogs a dit « trop de requêtes » : laissé tranquille jusque-là.
  DateTime? _pausedUntil;

  /// Jeton refusé : Discogs écarté jusqu'au redémarrage (pour l'état).
  String? problem;

  bool get ready => problem == null && !(_pausedUntil?.isAfter(DateTime.now()) ?? false);

  Future<Map<String, dynamic>?> _get(String path, Map<String, String> query) {
    final done = Completer<Map<String, dynamic>?>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await _send(path, query));
      } on Object {
        done.complete(null); // Réseau, délai : rien de Discogs cette fois.
      }
    });
    return done.future;
  }

  Future<Map<String, dynamic>?> _send(String path, Map<String, String> query) async {
    if (!ready) return null;
    final wait = interval - DateTime.now().difference(_last);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _last = DateTime.now();
    final request = await _http.getUrl(Uri.parse('$base$path').replace(queryParameters: query.isEmpty ? null : query));
    request.headers
      ..set(HttpHeaders.userAgentHeader, userAgent)
      ..set(HttpHeaders.authorizationHeader, 'Discogs token=$token')
      ..set(HttpHeaders.acceptHeader, 'application/vnd.discogs.v2.discogs+json');
    final reply = await request.close().timeout(const Duration(seconds: 30));
    final body = await reply.transform(utf8.decoder).join();
    switch (reply.statusCode) {
      case 200:
        return jsonDecode(body) as Map<String, dynamic>;
      case 401 || 403:
        problem = 'jeton Discogs refusé';
      case 429:
        _pausedUntil = DateTime.now().add(const Duration(minutes: 1));
    }
    return null;
  }

  /// Résultats de recherche de parutions pour [guess].
  Future<List<Map<String, dynamic>>> _search(AlbumGuess guess) async {
    if (titleKey(guess.title).isEmpty) return const [];
    final json = await _get('/database/search', {
      'type': 'release',
      'release_title': guess.title,
      if (guess.artist != null && titleKey(guess.artist!).isNotEmpty) 'artist': guess.artist!,
      'per_page': '15',
    });
    return [for (final r in (json?['results'] as List? ?? const []).whereType<Map>()) r.cast<String, dynamic>()];
  }

  /// Un album que MusicBrainz ne connaît pas : la parution qui correspond
  /// (titre, artiste, puis nombre de pistes vérifié sur la fiche), ou null.
  Future<MbRelease?> find(AlbumGuess guess, {required int trackCount}) async {
    final ranked = rank(await _search(guess), guess);
    // Le nombre de pistes n'est que sur la fiche : les deux meilleures.
    for (final id in ranked.take(2)) {
      final json = await _get('/releases/$id', const {});
      if (json == null) continue;
      final release = parseRelease(json);
      final count = release.tracks.length;
      if (trackCount == 0 || count == 0 || (count - trackCount).abs() <= 2) return release;
    }
    return null;
  }

  /// Pochette et styles d'un album reconnu par MusicBrainz, d'après le
  /// meilleur résultat de recherche (une seule requête).
  Future<MbRelease> complete(MbRelease release, AlbumGuess guess) async {
    final known = AlbumGuess(title: release.title, artist: release.artistName ?? guess.artist, year: release.year);
    final results = await _search(known);
    final id = rank(results, known).firstOrNull;
    final best = results.where((r) => '${r['id']}' == id).firstOrNull;
    if (best == null) return release;
    final image = best['cover_image'] as String?;
    return release.withExtras(
      image: image == null || image.contains('spacer.gif') ? null : image,
      genres: release.genres.isNotEmpty ? null : _genres(best['style'], best['genre']),
    );
  }

  /// Identifiants des [results] qui correspondent, du meilleur au moins bon :
  /// titre qui correspond (« Artiste - Titre » chez Discogs), artiste en
  /// commun s'il est connu ; puis année, et formats numériques ou CD (ce que
  /// sont des fichiers) plutôt que vinyle.
  static List<String> rank(List<Map<String, dynamic>> results, AlbumGuess guess) {
    final wanted = titleKey(guess.title);
    final artistWords = guess.artist == null ? <String>{} : titleWords(guess.artist!).map((w) => w.toLowerCase()).toSet();
    final scored = <(String, int)>[];
    for (final r in results) {
      final full = r['title'] as String? ?? '';
      final dash = full.indexOf(' - ');
      final title = titleKey(dash < 0 ? full : full.substring(dash + 3));
      final artist = dash < 0 ? '' : full.substring(0, dash);
      if (title.isEmpty || (title != wanted && !title.startsWith(wanted) && !wanted.startsWith(title))) continue;
      final names = titleWords(cleanName(artist)).map((w) => w.toLowerCase()).toSet();
      if (artistWords.isNotEmpty && artistWords.intersection(names).isEmpty) continue;
      var score = title == wanted ? 50 : 30;
      final formats = (r['format'] as List? ?? const []).map((f) => '$f');
      if (formats.any((f) => f == 'CD' || f == 'File' || f == 'Digital')) score += 10;
      if (guess.year != null && '${r['year']}' == '${guess.year}') score += 10;
      if ((r['cover_image'] as String? ?? '').isNotEmpty) score += 2;
      scored.add(('${r['id']}', score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (id, _) in scored) id];
  }

  /// « Air (2) » → « Air » : Discogs numérote les homonymes.
  static String cleanName(String name) => name.replaceFirst(RegExp(r'\s*\(\d+\)$'), '').replaceAll('*', '').trim();

  static String _credit(Object? artists) => [
        for (final a in (artists as List? ?? const []).whereType<Map>())
          '${cleanName('${(a['anv'] as String?)?.isNotEmpty == true ? a['anv'] : a['name'] ?? ''}')}'
              '${(a['join'] as String?)?.isNotEmpty == true ? ' ${a['join']} ' : ''}',
      ].join().replaceAll(RegExp(r'\s+'), ' ').replaceAll(' , ', ', ').trim();

  /// Styles d'abord (plus fins : « Trip Hop »), puis genres ; quatre au plus.
  static List<String> _genres(Object? styles, Object? genres) => {
        for (final g in [...(styles as List? ?? const []), ...(genres as List? ?? const [])]) '$g',
      }.take(4).toList();

  /// Durée Discogs (« 4:32 », « 1:02:10 ») en millisecondes.
  static int? _duration(Object? text) {
    final parts = '${text ?? ''}'.split(':').map(int.tryParse).toList();
    if (parts.length < 2 || parts.any((p) => p == null)) return null;
    return parts.fold<int>(0, (s, p) => s * 60 + p!) * 1000;
  }

  /// Fiche Discogs (`/releases/<id>`) au format des fiches MusicBrainz.
  /// Positions : « 1-3 », « CD2-5 », « 2.4 » (disque et piste), « 7 »
  /// (piste), « A1 », « B2 » (vinyle : dans l'ordre) ; les intertitres
  /// (`heading`) et sous-pistes (`index`) ne sont pas des pistes.
  static MbRelease parseRelease(Map<String, dynamic> j) {
    final albumArtist = _credit(j['artists']);
    final first = (j['artists'] as List? ?? const []).whereType<Map>().firstOrNull;
    final tracks = <MbTrack>[];
    var order = 0;
    for (final t in (j['tracklist'] as List? ?? const []).whereType<Map>()) {
      if ((t['type_'] ?? 'track') != 'track') continue;
      order++;
      final position = '${t['position'] ?? ''}'.trim();
      final multi = RegExp(r'^(?:CD|DVD|Disc|Disk)?\s*(\d+)[-.](\d+)$', caseSensitive: false).firstMatch(position);
      final single = RegExp(r'^\d+$').hasMatch(position);
      final artist = _credit(t['artists']);
      tracks.add(MbTrack(
        disc: multi == null ? 1 : int.parse(multi.group(1)!),
        position: multi != null ? int.parse(multi.group(2)!) : single ? int.parse(position) : order,
        title: t['title'] as String? ?? '',
        length: _duration(t['duration']),
        artist: artist.isEmpty || artist == albumArtist ? null : artist,
      ));
    }
    final descriptions = [
      for (final f in (j['formats'] as List? ?? const []).whereType<Map>()) ...(f['descriptions'] as List? ?? const []).map((d) => '$d'),
    ];
    final label = (j['labels'] as List? ?? const []).whereType<Map>().firstOrNull?['name'] as String?;
    final images = (j['images'] as List? ?? const []).whereType<Map>().toList();
    final image = (images.where((i) => i['type'] == 'primary').firstOrNull ?? images.firstOrNull)?['uri'] as String?;
    final released = '${j['released'] ?? ''}'.replaceAll('-00', '');
    return MbRelease(
      source: 'discogs',
      id: '${j['id']}',
      title: j['title'] as String? ?? '',
      artist: albumArtist,
      artistName: first == null ? null : cleanName('${first['name'] ?? ''}'),
      date: released.isNotEmpty ? released : (j['year'] as num?)?.toString(),
      country: j['country'] as String?,
      label: label == null ? null : cleanName(label),
      type: const ['Album', 'EP', 'Single', 'Compilation'].where(descriptions.contains).firstOrNull,
      image: image == null || image.isEmpty ? null : image,
      genres: _genres(j['styles'], j['genres']),
      tracks: tracks,
    );
  }

  void close() => _http.close(force: true);
}
