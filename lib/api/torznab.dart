import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../core/release_name.dart';
import 'tracker.dart';

/// Client Torznab générique (format des indexeurs Prowlarr / Jackett).
/// Spécification : https://torznab.github.io/spec-1.3-draft/
class TorznabApi implements TrackerApi {
  TorznabApi(this.tracker, this.apiKey, {String? baseUrl})
      : _dio = trackerDio(
          baseUrl: baseUrl ?? tracker.baseUrl,
          headers: {
            if (tracker.apiKeyHeader != null) tracker.apiKeyHeader!: apiKey,
          },
        );

  @override
  final Tracker tracker;
  final String apiKey;
  final Dio _dio;

  /// Torznab renvoie les sorties par date (ou pertinence) sans tri possible :
  /// les tris sont faits localement. Pas de nombre de commentaires.
  @override
  List<ReleaseSort> get sorts =>
      ReleaseSort.values.where((s) => s != ReleaseSort.comments).toList();

  @override
  Set<ReleaseSort> get serverSorts => const {};

  Future<XmlDocument> _call(Map<String, dynamic> query) async {
    // Clé envoyée aussi en paramètre : c'est ce qu'attendent les outils *arr,
    // et l'en-tête du tracker (ex. X-Api-Key) est ajouté par le client HTTP.
    final res = await trackerGet<String>(_dio, tracker, '',
        query: {...query, 'apikey': apiKey}, type: ResponseType.plain);
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(res.data ?? '');
    } on XmlException {
      throw TrackerException('${tracker.label} : réponse Torznab illisible');
    }
    // Les erreurs Torznab arrivent en HTTP 200 : <error code="100" description="…"/>
    final root = doc.rootElement;
    if (root.name.local == 'error') {
      final code = root.getAttribute('code');
      final description = root.getAttribute('description') ?? 'erreur';
      throw TrackerException(code == '100' || code == '101'
          ? 'Clé API ${tracker.label} refusée'
          : '${tracker.label} : $description');
    }
    return doc;
  }

  @override
  Future<List<Category>> categories() async {
    final doc = await _call({'t': 'caps'});
    return doc
        .findAllElements('categories')
        .expand((e) => e.findElements('category'))
        .map((c) => Category(
              int.parse(c.getAttribute('id')!),
              c.getAttribute('name') ?? '',
              c
                  .findElements('subcat')
                  .map((s) => Subcategory(
                      int.parse(s.getAttribute('id')!), s.getAttribute('name') ?? ''))
                  .toList(),
            ))
        .toList();
  }

  /// Noms des catégories du `caps`, par identifiant (parentes et
  /// sous-catégories). Chargés une fois ; un échec est retenté au prochain
  /// appel, les sorties restant alors sans [Release.categories].
  Future<Map<int, String>>? _names;

  Future<Map<int, String>> _categoryNames() => _names ??= _loadNames();

  Future<Map<int, String>> _loadNames() async {
    try {
      return {
        for (final c in await categories()) ...{
          c.id: c.name,
          for (final s in c.subcategories) s.id: s.name,
        },
      };
    } on Object {
      _names = null;
      return const {};
    }
  }

  @override
  Future<ReleasePage> releases({
    int page = 1,
    int perPage = 50,
    int? categoryId,
    int? subcategoryId,
    String query = '',
    ReleaseSort sort = ReleaseSort.date,
    bool ascending = false,
  }) async {
    // Le caps (une fois) part en même temps que la recherche.
    final names = _categoryNames();
    final doc = await _call({
      't': 'search',
      if (query.isNotEmpty) 'q': query,
      'cat': ?(subcategoryId ?? categoryId),
      'offset': (page - 1) * perPage,
      'limit': perPage,
      'extended': 1,
    });

    final byId = await names;
    final items = [
      for (final item in doc.findAllElements('item')) _release(item, byId),
    ];
    // <torznab:response offset="0" total="1234"/> : facultatif selon les indexeurs.
    final response = doc
        .findAllElements('*')
        .where((e) => e.name.local == 'response')
        .firstOrNull;
    final total = int.tryParse(response?.getAttribute('total') ?? '');
    final totalPages = total != null
        ? (total / perPage).ceil()
        : (items.length < perPage ? page : page + 1);
    return ReleasePage(items, page, totalPages, total ?? 0);
  }

  @override
  Future<Uint8List> downloadTorrent(Release release) async {
    final url = release.downloadUrl;
    if (url == null) {
      throw TrackerException('${tracker.label} : pas de lien de téléchargement');
    }
    final res =
        await trackerGet<List<int>>(_dio, tracker, url,
            type: ResponseType.bytes, download: true);
    return checkTorrent(tracker, res.data);
  }

  @override
  void close() => _dio.close();

  Release _release(XmlElement item, Map<int, String> names) {
    String? text(String name) =>
        item.findElements(name).firstOrNull?.innerText.trim();
    final attrs = <String, String>{
      for (final a in item.childElements.where((e) => e.name.local == 'attr'))
        a.getAttribute('name')!: a.getAttribute('value') ?? '',
    };
    int? attrInt(String k) => int.tryParse(attrs[k] ?? '');
    // Plusieurs `category` possibles (parente et sous-catégorie), en attribut
    // torznab et/ou en élément RSS : `attrs` n'en garde qu'une.
    final categoryIds = {
      for (final a in item.childElements)
        if (a.name.local == 'attr' && a.getAttribute('name') == 'category')
          ?int.tryParse(a.getAttribute('value') ?? ''),
      for (final c in item.findElements('category'))
        ?int.tryParse(c.innerText.trim()),
    };

    final name = text('title') ?? '';
    final parsed = ReleaseName.parse(name);
    final enclosure = item.findElements('enclosure').firstOrNull;
    final seeders = attrInt('seeders') ?? 0;
    final pubDate = text('pubDate');

    return Release(
      tracker: tracker,
      id: text('guid') ?? attrs['infohash'] ?? name,
      infoHash: attrs['infohash']?.toLowerCase(),
      downloadUrl: enclosure?.getAttribute('url') ?? text('link'),
      name: name,
      title: parsed.title,
      year: parsed.year,
      subcategory: parsed.kind,
      categories: [for (final id in categoryIds) ?names[id]],
      size: int.tryParse(text('size') ?? '') ?? attrInt('size') ?? 0,
      seeders: seeders,
      // Torznab donne « peers » = seeders + leechers.
      leechers: ((attrInt('peers') ?? seeders) - seeders).clamp(0, 1 << 31),
      completions: attrInt('grabs') ?? 0,
      createdAt: (pubDate != null ? parseRfc822(pubDate) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isFreeleech: attrs['downloadvolumefactor'] == '0',
      posterUrl: attrs['coverurl'] ?? attrs['poster'],
      resolution: parsed.resolution,
      source: parsed.source,
      videoCodec: parsed.videoCodec,
      languages: parsed.languages,
    );
  }
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// `Sat, 17 Oct 2026 01:55:38 +0000` (ou `GMT`) → DateTime UTC.
DateTime? parseRfc822(String input) {
  final m = RegExp(
          r'(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|\w+)?')
      .firstMatch(input);
  if (m == null) return null;
  final month = _months[m.group(2)!.toLowerCase()];
  if (month == null) return null;
  var date = DateTime.utc(
    int.parse(m.group(3)!),
    month,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6) ?? '0'),
  );
  final zone = m.group(7);
  if (zone != null && (zone.startsWith('+') || zone.startsWith('-'))) {
    final sign = zone.startsWith('-') ? -1 : 1;
    final offset = Duration(
        hours: int.parse(zone.substring(1, 3)),
        minutes: int.parse(zone.substring(3, 5)));
    date = sign > 0 ? date.subtract(offset) : date.add(offset);
  }
  return date;
}
