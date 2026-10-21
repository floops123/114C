import 'package:xml/xml.dart';

import 'remote_zip.dart';

/// Ce qu'un fichier dit de lui-même : métadonnées d'un EPUB (OPF) ou d'une
/// BD (ComicInfo.xml), couverture, pages.
class Embedded {
  const Embedded({
    this.title,
    this.authors = const [],
    this.series,
    this.volume,
    this.description,
    this.publisher,
    this.date,
    this.language,
    this.subjects = const [],
    this.isbn,
    this.cover,
    this.pages,
    this.rightToLeft = false,
  });

  factory Embedded.fromJson(Map<String, dynamic> j) => Embedded(
        title: j['title'] as String?,
        authors: (j['authors'] as List? ?? const []).cast<String>(),
        series: j['series'] as String?,
        volume: (j['volume'] as num?)?.toDouble(),
        description: j['description'] as String?,
        publisher: j['publisher'] as String?,
        date: j['date'] as String?,
        language: j['language'] as String?,
        subjects: (j['subjects'] as List? ?? const []).cast<String>(),
        isbn: j['isbn'] as String?,
        cover: j['cover'] as String?,
        pages: (j['pages'] as num?)?.toInt(),
        rightToLeft: j['rtl'] as bool? ?? false,
      );

  final String? title;
  final List<String> authors;
  final String? series;
  final double? volume;
  final String? description;
  final String? publisher;

  /// Date telle qu'écrite (« 2012-09-19 », « 2012 »).
  final String? date;
  final String? language;
  final List<String> subjects;
  final String? isbn;

  /// Entrée de l'archive qui sert de couverture.
  final String? cover;

  /// Nombre de pages (BD).
  final int? pages;

  /// Manga à lire de droite à gauche (ComicInfo).
  final bool rightToLeft;

  int? get year => date == null || date!.length < 4 ? null : int.tryParse(date!.substring(0, 4));

  Map<String, dynamic> toJson() => {
        'title': ?title,
        if (authors.isNotEmpty) 'authors': authors,
        'series': ?series,
        'volume': ?volume,
        'description': ?description,
        'publisher': ?publisher,
        'date': ?date,
        'language': ?language,
        if (subjects.isNotEmpty) 'subjects': subjects,
        'isbn': ?isbn,
        'cover': ?cover,
        'pages': ?pages,
        if (rightToLeft) 'rtl': true,
      };
}

const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'avif', 'bmp'};

bool isImageName(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 && _imageExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// Pages d'une BD : les images, dans l'ordre naturel (2 avant 10), sans les
/// fichiers cachés ni les dossiers de macOS.
List<String> comicPages(Iterable<String> names) {
  final pages = [
    for (final n in names)
      if (isImageName(n) &&
          !n.startsWith('__MACOSX/') &&
          !n.split('/').last.startsWith('.'))
        n,
  ]..sort(naturalCompare);
  return pages;
}

/// Comparaison « naturelle » : les nombres comptent pour leur valeur.
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(a.toLowerCase()).toList(), y = re.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final p = x[i], q = y[i];
    final c = p[1] != null && q[1] != null
        ? int.parse(p[1]!).compareTo(int.parse(q[1]!))
        : p[0]!.compareTo(q[0]!);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

/// Texte simple depuis du HTML (résumés d'EPUB et de Google Books).
String plainText(String html) {
  var s = html
      .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</\s*(p|div|li|h\d)\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)));
  return s
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String? _text(XmlElement root, String local) {
  for (final e in root.descendants.whereType<XmlElement>()) {
    if (e.name.local == local) {
      final t = e.innerText.trim();
      if (t.isNotEmpty) return t;
    }
  }
  return null;
}

/// Métadonnées d'un EPUB : `META-INF/container.xml` donne le fichier OPF.
Future<Embedded> inspectEpub(RemoteZip zip) async {
  final container = zip.entry('META-INF/container.xml');
  if (container == null) throw const ZipException('EPUB sans container.xml');
  final rootfile = XmlDocument.parse(await zip.readText(container))
      .descendants
      .whereType<XmlElement>()
      .firstWhere((e) => e.name.local == 'rootfile',
          orElse: () => throw const ZipException('EPUB sans fichier OPF'))
      .getAttribute('full-path');
  final opfEntry = rootfile == null ? null : zip.entry(rootfile);
  if (opfEntry == null) throw const ZipException('EPUB sans fichier OPF');
  return parseOpf(await zip.readText(opfEntry), opfPath: opfEntry.name, names: [
    for (final e in zip.entries) e.name,
  ]);
}

/// Métadonnées d'un fichier OPF situé à [opfPath] dans l'archive.
Embedded parseOpf(String opf, {required String opfPath, Iterable<String> names = const []}) {
  final doc = XmlDocument.parse(opf);
  final elements = doc.descendants.whereType<XmlElement>().toList();
  Iterable<XmlElement> named(String local) => elements.where((e) => e.name.local == local);
  String? meta(String name) => named('meta')
      .where((e) => e.getAttribute('name') == name)
      .map((e) => e.getAttribute('content')?.trim())
      .whereType<String>()
      .firstOrNull;

  final title = named('title').map((e) => e.innerText.trim()).firstWhere(
      (t) => t.isNotEmpty && t.toLowerCase() != 'unknown',
      orElse: () => '');
  final authors = [
    for (final e in named('creator'))
      if (e.innerText.trim() case final a when a.isNotEmpty && a.toLowerCase() != 'unknown')
        // Rôle facultatif ; « aut » ou absent : un auteur.
        if (const {null, 'aut'}.contains(e.getAttribute('role') ?? e.getAttribute('opf:role'))) a,
  ];
  String? isbn;
  for (final e in named('identifier')) {
    final v = e.innerText.replaceAll(RegExp(r'[^0-9Xx]'), '');
    final scheme = (e.getAttribute('scheme') ?? e.getAttribute('opf:scheme') ?? '').toLowerCase();
    if ((v.length == 13 && (v.startsWith('978') || v.startsWith('979'))) ||
        (v.length == 10 && scheme == 'isbn')) {
      isbn = v;
      break;
    }
  }
  // Série : Calibre (meta name), ou EPUB 3 (belongs-to-collection).
  var series = meta('calibre:series');
  var volume = double.tryParse(meta('calibre:series_index') ?? '');
  if (series == null) {
    final collection = named('meta').where((e) => e.getAttribute('property') == 'belongs-to-collection').firstOrNull;
    if (collection != null) {
      series = collection.innerText.trim();
      final id = collection.getAttribute('id');
      final position = named('meta')
          .where((e) => e.getAttribute('property') == 'group-position' && e.getAttribute('refines') == '#$id')
          .firstOrNull;
      volume ??= double.tryParse(position?.innerText.trim() ?? '');
    }
  }

  // Couverture : meta name="cover" → item du manifeste ; EPUB 3 :
  // properties="cover-image" ; à défaut une image nommée « cover ».
  final items = named('item').toList();
  final dir = opfPath.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1) : '';
  String? href;
  final coverId = meta('cover');
  if (coverId != null) {
    href = items.where((i) => i.getAttribute('id') == coverId).firstOrNull?.getAttribute('href');
  }
  href ??= items
      .where((i) => (i.getAttribute('properties') ?? '').split(' ').contains('cover-image'))
      .firstOrNull
      ?.getAttribute('href');
  href ??= items
      .where((i) =>
          (i.getAttribute('media-type') ?? '').startsWith('image/') &&
          '${i.getAttribute('id')} ${i.getAttribute('href')}'.toLowerCase().contains('cover'))
      .firstOrNull
      ?.getAttribute('href');
  String? cover;
  if (href != null) {
    cover = _resolve(dir, Uri.decodeFull(href));
    final all = names.toList();
    if (all.isNotEmpty && !all.contains(cover)) {
      cover = all.where((n) => n.toLowerCase() == cover!.toLowerCase()).firstOrNull;
    }
  }

  final description = named('description').map((e) => plainText(e.innerText)).firstOrNull;
  return Embedded(
    title: title.isEmpty ? null : title,
    authors: authors,
    series: series == null || series.isEmpty ? null : series,
    volume: volume,
    description: description == null || description.isEmpty ? null : description,
    publisher: named('publisher').map((e) => e.innerText.trim()).where((t) => t.isNotEmpty).firstOrNull,
    date: named('date').map((e) => e.innerText.trim()).where((t) => t.isNotEmpty).firstOrNull,
    language: named('language').map((e) => e.innerText.trim()).where((t) => t.isNotEmpty).firstOrNull,
    subjects: [for (final e in named('subject')) if (e.innerText.trim().isNotEmpty) e.innerText.trim()],
    isbn: isbn,
    cover: cover,
  );
}

/// `OEBPS/` + `../Images/a.jpg` → `Images/a.jpg`.
String _resolve(String dir, String href) {
  final parts = [...dir.split('/').where((p) => p.isNotEmpty)];
  for (final p in href.split('/')) {
    if (p == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (p != '.' && p.isNotEmpty) {
      parts.add(p);
    }
  }
  return parts.join('/');
}

/// Métadonnées d'une BD : ses pages, et `ComicInfo.xml` s'il y en a un.
Future<Embedded> inspectComic(RemoteZip zip) async {
  final pages = comicPages([for (final e in zip.entries) e.name]);
  final info = zip.entries.where((e) => e.name.split('/').last.toLowerCase() == 'comicinfo.xml').firstOrNull;
  final base = info == null ? const Embedded() : parseComicInfo(await zip.readText(info));
  return Embedded(
    title: base.title,
    authors: base.authors,
    series: base.series,
    volume: base.volume,
    description: base.description,
    publisher: base.publisher,
    date: base.date,
    language: base.language,
    subjects: base.subjects,
    rightToLeft: base.rightToLeft,
    cover: pages.firstOrNull,
    pages: pages.length,
  );
}

/// Depuis `ComicInfo.xml` (format de ComicRack, repris par Komga, Kavita…).
Embedded parseComicInfo(String xml) {
  final XmlElement root;
  try {
    root = XmlDocument.parse(xml).rootElement;
  } on XmlException {
    return const Embedded();
  }
  String? t(String n) => _text(root, n);
  final year = int.tryParse(t('Year') ?? '');
  final month = int.tryParse(t('Month') ?? '');
  final day = int.tryParse(t('Day') ?? '');
  final authors = <String>{
    for (final role in ['Writer', 'Penciller', 'Artist'])
      ...?t(role)?.split(RegExp(r'\s*[,;]\s*')).where((a) => a.isNotEmpty),
  }.toList();
  return Embedded(
    title: t('Title'),
    series: t('Series'),
    volume: double.tryParse((t('Number') ?? t('Volume') ?? '').replaceAll(',', '.')),
    authors: authors,
    description: t('Summary') == null ? null : plainText(t('Summary')!),
    publisher: t('Publisher'),
    date: year == null
        ? null
        : [
            '$year',
            if (month != null) month.toString().padLeft(2, '0'),
            if (month != null && day != null) day.toString().padLeft(2, '0'),
          ].join('-'),
    language: t('LanguageISO'),
    subjects: [...?t('Genre')?.split(RegExp(r'\s*,\s*')).where((g) => g.isNotEmpty)],
    rightToLeft: (t('Manga') ?? '').toLowerCase() == 'yesandrighttoleft',
  );
}
