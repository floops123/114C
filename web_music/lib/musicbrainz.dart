import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:c411_core/music_name.dart';
import 'package:c411_core/titles.dart';

import 'library.dart';

/// MusicBrainz est resté saturé malgré les nouvelles tentatives.
class MusicBrainzBusy implements Exception {
  const MusicBrainzBusy();
  @override
  String toString() => 'MusicBrainz saturé, réessaie plus tard';
}

/// Client de l'API MusicBrainz (https://musicbrainz.org/doc/MusicBrainz_API).
///
/// Ses règles : un User-Agent qui dit qui appelle (avec un contact), et une
/// requête par seconde au plus — les appels passent donc un par un.
class MusicBrainz {
  MusicBrainz({
    required String contact,
    HttpClient? http,
    this.base = 'https://musicbrainz.org/ws/2',
    this.interval = const Duration(milliseconds: 1100),
    this.backoff = const Duration(seconds: 2),
  })  : userAgent = 'C411Music/1.0 ( $contact )',
        _http = http ?? HttpClient();

  final String userAgent;
  final String base;

  /// Écart minimal entre deux requêtes.
  final Duration interval;

  /// Première attente quand MusicBrainz est saturé (503), doublée ensuite.
  final Duration backoff;
  final HttpClient _http;
  Future<void> _queue = Future.value();
  DateTime _last = DateTime(2000);

  /// GET [path] (JSON), à son tour dans la file. Réessaie si MusicBrainz
  /// est saturé (503, fréquent même au rythme permis) : jusqu'à 6 fois, en
  /// attendant de plus en plus (30 s au plus, ou ce que dit Retry-After).
  Future<Map<String, dynamic>?> _get(String path, Map<String, String> query) {
    final done = Completer<Map<String, dynamic>?>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await _send(path, query));
      } on Object catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  Future<Map<String, dynamic>?> _send(String path, Map<String, String> query) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      final wait = interval - DateTime.now().difference(_last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _last = DateTime.now();
      final request = await _http.getUrl(Uri.parse('$base$path').replace(
          queryParameters: {...query, 'fmt': 'json'}));
      request.headers
        ..set(HttpHeaders.userAgentHeader, userAgent)
        ..set(HttpHeaders.acceptHeader, 'application/json');
      final reply = await request.close();
      final body = await reply.transform(utf8.decoder).join();
      switch (reply.statusCode) {
        case 200:
          return jsonDecode(body) as Map<String, dynamic>;
        case 404:
          return null;
        case 503 || 429:
          final after = int.tryParse(reply.headers.value('retry-after') ?? '');
          final wait = after != null ? Duration(seconds: after) : backoff * (1 << attempt);
          await Future<void>.delayed(wait > const Duration(seconds: 30) ? const Duration(seconds: 30) : wait);
        default:
          throw HttpException('MusicBrainz : HTTP ${reply.statusCode}');
      }
    }
    throw const MusicBrainzBusy();
  }

  /// Cherche la parution qui correspond à [guess], dont on a [trackCount]
  /// pistes, puis lit sa fiche complète. null : rien de sûr.
  Future<MbRelease?> find(AlbumGuess guess, {required int trackCount}) async {
    if (titleKey(guess.title).isEmpty) return null;
    final terms = [
      'release:"${_quote(guess.title)}"',
      if (guess.artist != null && titleKey(guess.artist!).isNotEmpty)
        'artist:"${_quote(guess.artist!)}"',
    ];
    final json = await _get('/release', {'query': terms.join(' AND '), 'limit': '15'});
    final candidates = [
      for (final r in (json?['releases'] as List? ?? const []).whereType<Map>())
        r.cast<String, dynamic>(),
    ];
    final best = pick(candidates, guess, trackCount: trackCount);
    if (best == null) return null;
    return release(best);
  }

  /// La meilleure des [candidates] (résultats de recherche), ou null si
  /// aucune n'est assez sûre.
  static String? pick(List<Map<String, dynamic>> candidates, AlbumGuess guess,
      {required int trackCount}) {
    String? bestId;
    var bestScore = 0.0;
    for (final r in candidates) {
      final score = (r['score'] as num?)?.toDouble() ?? 0;
      if (score < 70) continue;
      final title = titleKey(r['title'] as String? ?? '');
      final wanted = titleKey(guess.title);
      // Le titre doit vraiment correspondre (la recherche est floue).
      if (title != wanted && !title.startsWith(wanted) && !wanted.startsWith(title)) continue;
      var s = score;
      final count = (r['track-count'] as num?)?.toInt();
      if (count == trackCount) {
        s += 25;
      } else if (count != null && (count - trackCount).abs() <= 2) {
        s += 8;
      }
      final date = r['date'] as String?;
      if (guess.year != null && date != null && date.startsWith('${guess.year}')) s += 10;
      if (r['status'] == 'Official') s += 5;
      if (title == wanted) s += 5;
      if (s > bestScore) {
        bestScore = s;
        bestId = r['id'] as String?;
      }
    }
    return bestId;
  }

  /// Fiche complète d'une parution : pistes, artistes, label, genres (ceux
  /// du groupe de parutions s'il n'y en a pas sur la parution).
  Future<MbRelease?> release(String id) async {
    final json = await _get('/release/$id', {
      'inc': 'recordings+artist-credits+release-groups+labels+genres',
    });
    if (json == null) return null;
    var release = parseRelease(json);
    if (release.genres.isEmpty && release.groupId != null) {
      final group = await _get('/release-group/${release.groupId}', {'inc': 'genres'});
      final genres = _genres(group);
      if (genres.isNotEmpty) release = release.withGenres(genres);
    }
    return release;
  }

  static List<String> _genres(Map<String, dynamic>? json) {
    final list = [
      for (final g in (json?['genres'] as List? ?? const []).whereType<Map>()) g,
    ]..sort((a, b) => ((b['count'] as num?) ?? 0).compareTo((a['count'] as num?) ?? 0));
    return [for (final g in list.take(4)) '${g['name']}'];
  }

  static String _credit(Object? credit) => [
        for (final c in (credit as List? ?? const []).whereType<Map>())
          '${c['name'] ?? (c['artist'] as Map?)?['name'] ?? ''}${c['joinphrase'] ?? ''}',
      ].join().trim();

  /// Depuis la réponse de `/release/<id>`.
  static MbRelease parseRelease(Map<String, dynamic> j) {
    final credit = (j['artist-credit'] as List? ?? const []).whereType<Map>().toList();
    final first = credit.isEmpty ? null : (credit.first['artist'] as Map?)?.cast<String, dynamic>();
    final group = (j['release-group'] as Map?)?.cast<String, dynamic>();
    final art = (j['cover-art-archive'] as Map?)?.cast<String, dynamic>();
    final albumArtist = _credit(credit);
    final labels = (j['label-info'] as List? ?? const []).whereType<Map>();
    final tracks = <MbTrack>[];
    for (final m in (j['media'] as List? ?? const []).whereType<Map>()) {
      final disc = (m['position'] as num?)?.toInt() ?? 1;
      for (final t in (m['tracks'] as List? ?? const []).whereType<Map>()) {
        final artist = _credit(t['artist-credit']);
        tracks.add(MbTrack(
          disc: disc,
          position: (t['position'] as num?)?.toInt() ?? 0,
          title: t['title'] as String? ?? '',
          length: (t['length'] as num?)?.toInt() ??
              ((t['recording'] as Map?)?['length'] as num?)?.toInt(),
          artist: artist.isEmpty || artist == albumArtist ? null : artist,
        ));
      }
    }
    return MbRelease(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      artist: albumArtist,
      artistName: first?['name'] as String?,
      artistId: first?['id'] as String?,
      groupId: group?['id'] as String?,
      date: switch (j['date']) {
        final String d when d.isNotEmpty => d,
        _ => group?['first-release-date'] as String?,
      },
      country: j['country'] as String?,
      label: labels.map((l) => (l['label'] as Map?)?['name']).whereType<String>().firstOrNull,
      type: group?['primary-type'] as String?,
      cover: art?['front'] == true,
      // Sans pochette propre, celle du groupe de parutions (la Cover Art
      // Archive choisit) : on essaie.
      groupCover: art?['front'] != true && group?['id'] != null,
      genres: _genres(j),
      tracks: tracks,
    );
  }

  static String _quote(String s) => s.replaceAll(RegExp(r'["\\]'), ' ');

  void close() => _http.close(force: true);
}
