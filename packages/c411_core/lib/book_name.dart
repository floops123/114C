import 'music_name.dart' show extensionOf;
import 'titles.dart';

// Reconnaissance des livres, BD, mangas et magazines d'après les dossiers
// et les noms de fichiers :
//   /ebooks/Victor Hugo - Les Misérables (1862).epub → livre, Victor Hugo
//   /BD/Astérix/Astérix - T01 - Astérix le Gaulois.cbz → BD, série
//     « Astérix », tome 1
//   /Presse/Le Point N°2650 - 6 Juin 2025.pdf → magazine « Le Point », n° 2650

/// Extensions des livres numériques retenus.
const bookExtensions = {
  'epub', 'pdf', 'cbz', 'cbr', 'cb7', 'cbt', 'mobi', 'azw3', 'azw', 'fb2', 'djvu',
};

/// Archives d'images : BD, comics, mangas.
const comicExtensions = {'cbz', 'cbr', 'cb7', 'cbt'};

bool isBookPath(String path) => bookExtensions.contains(extensionOf(path));

/// Taille minimale : en dessous, notices, bons de commande, extraits.
const minBookBytes = 20 * 1024;

/// Un PDF plus petit que ça n'est sans doute pas un livre ni un magazine
/// (facture, notice, fiche).
const minPdfBytes = 150 * 1024;

/// Assez gros pour être un livre (règle plus stricte pour les PDF, très
/// courants dans les torrents de jeux et de logiciels).
bool isBookSize(String path, int size) =>
    size >= (extensionOf(path) == 'pdf' ? minPdfBytes : minBookBytes);

enum BookKind {
  book('Livre'),
  comic('BD'),
  manga('Manga'),
  magazine('Magazine');

  const BookKind(this.label);
  final String label;
}

/// Mois, en français et en anglais (avec et sans accents).
const _months = {
  'février': 2, 'févr': 2, 'août': 8, 'décembre': 12, 'déc': 12,
  'janvier': 1, 'fevrier': 2, 'mars': 3, 'avril': 4, 'mai': 5, 'juin': 6,
  'juillet': 7, 'aout': 8, 'septembre': 9, 'octobre': 10, 'novembre': 11,
  'decembre': 12, 'january': 1, 'february': 2, 'march': 3, 'april': 4,
  'may': 5, 'june': 6, 'july': 7, 'august': 8, 'september': 9, 'october': 10,
  'november': 11, 'december': 12, 'janv': 1, 'fev': 2, 'fevr': 2, 'avr': 4,
  'juil': 7, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Mots qui ne disent rien du titre : formats, sources, qualité.
final _tag = RegExp(
    r'^(?:e-?books?|epub|pdf|cbz|cbr|mobi|azw3|retail|french|fr|vf|vo|'
    r'multi|hq|hd|c2c|digital|numerique|scan|scans|ocr|v\d|team|'
    r'complet|complete|integrale|int|fixed|repack|proper|\d{3,4}p)$',
    caseSensitive: false);

bool _isTagWord(String s) {
  final words = foldAccents(s.trim()).split(RegExp(r'[\s,+/_-]+')).where((w) => w.isNotEmpty);
  return words.isEmpty || words.every((w) => _tag.hasMatch(w));
}

final _comicFolder = RegExp(r'\b(?:bd|b\.d\.|comics?|bandes? dessinees?)\b', caseSensitive: false);
final _mangaFolder = RegExp(r'\b(?:mangas?|manhwas?|manhuas?|webtoons?|scans?)\b', caseSensitive: false);
final _magazineFolder = RegExp(r'\b(?:magazines?|presse|journaux|journal|revues?|kiosque)\b', caseSensitive: false);

/// Numéro de magazine : « N°2650 », « n° 12 », « No.45 », « Numero 3 ».
final _issue = RegExp(r'\b(?:n\s?°|nº|no\.?|num(?:ero)?\.?)\s*(\d{1,5})\b', caseSensitive: false);

/// Tome : « Tome 3 », « T03 », « T.3 », « Vol. 2 », « Volume 12 », « #7 ».
final _volume = RegExp(
    r'(?:^|[\s(\[-])(?:tome|t|vol(?:ume)?|v|#)\.?\s?(\d{1,4}(?:[.,]\d)?)(?=$|[\s)\]._-])',
    caseSensitive: false);

/// Ce qu'on devine d'un livre numérique d'après son chemin.
class BookGuess {
  const BookGuess({
    required this.kind,
    required this.title,
    this.author,
    this.series,
    this.volume,
    this.issue,
    this.year,
    this.month,
    this.day,
  });

  final BookKind kind;

  /// Titre du livre, du tome, ou du magazine (sans le numéro).
  final String title;
  final String? author;

  /// Série (BD, manga) ou titre du magazine, pour regrouper.
  final String? series;
  final double? volume;

  /// Numéro de magazine.
  final int? issue;
  final int? year;
  final int? month;
  final int? day;

  /// Clé de regroupement : la série, sinon le titre.
  String get groupKey => '${kind.name}:${titleKey(series ?? title)}';

  static BookGuess parse(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return const BookGuess(kind: BookKind.book, title: '');
    final file = parts.last;
    final ext = extensionOf(file);
    final dirs = parts.sublist(0, parts.length - 1);
    final folders = foldAccents(dirs.join('/'));
    var base = ext.isEmpty ? file : file.substring(0, file.length - ext.length - 1);
    // Noms de scène : points ou soulignés à la place des espaces.
    if (!base.contains(' ')) base = base.replaceAll(RegExp(r'[._]+'), ' ');
    base = base.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    int? year, month, day;
    // Date complète : « 06.06.2025 », « 2025-06-06 ».
    final dmy = RegExp(r'\b(\d{1,2})[./-](\d{1,2})[./-]((?:19|20)\d{2})\b').firstMatch(base);
    final ymd = RegExp(r'\b((?:19|20)\d{2})[./-](\d{1,2})[./-](\d{1,2})\b').firstMatch(base);
    if (ymd != null) {
      (year, month, day) = (int.parse(ymd[1]!), int.parse(ymd[2]!), int.parse(ymd[3]!));
      base = base.replaceFirst(ymd[0]!, ' ');
    } else if (dmy != null) {
      (day, month, year) = (int.parse(dmy[1]!), int.parse(dmy[2]!), int.parse(dmy[3]!));
      base = base.replaceFirst(dmy[0]!, ' ');
    }
    // Mois en toutes lettres : « Juin 2025 », « 6 juin 2025 », « Juillet-Août 2025 ».
    final monthWord = '(?:${_months.keys.join('|')})';
    final monthName = RegExp(
            '(?<![A-Za-zÀ-ÿ])(?:(\\d{1,2})(?:er)?\\s+)?($monthWord)\\.?(?:\\s*[-/]\\s*$monthWord\\.?)?\\s+((?:19|20)\\d{2})\\b',
            caseSensitive: false)
        .firstMatch(base);
    if (monthName != null && month == null) {
      month = _months[monthName[2]!.toLowerCase()];
      year = int.parse(monthName[3]!);
      day = int.tryParse(monthName[1] ?? '');
      base = base.replaceFirst(monthName[0]!, ' ');
    }

    final issueMatch = _issue.firstMatch(base);
    final issue = int.tryParse(issueMatch?[1] ?? '');
    if (issueMatch != null) base = base.replaceFirst(issueMatch[0]!, ' ');

    // Groupes entre crochets ou parenthèses : année, format, équipe.
    base = base.replaceAllMapped(RegExp(r'[\[({]([^\])}]*)[\])}]'), (m) {
      final inner = m[1]!.trim();
      final y = RegExp(r'^\s*((?:1[5-9]|20)\d{2})\s*$').firstMatch(inner);
      if (y != null) {
        year ??= int.parse(y[1]!);
        return ' ';
      }
      if (m[0]!.startsWith('[') || _isTagWord(inner)) return ' ';
      return m[0]!;
    });

    final kind = comicExtensions.contains(ext)
        ? (_mangaFolder.hasMatch(folders) ? BookKind.manga : BookKind.comic)
        : _magazineFolder.hasMatch(folders) || issue != null || (month != null && year != null)
            ? BookKind.magazine
            : _mangaFolder.hasMatch(folders)
                ? BookKind.manga
                : _comicFolder.hasMatch(folders)
                    ? BookKind.comic
                    : BookKind.book;

    var fields = base
        .split(RegExp(r'\s+[-–—]\s+|\s+-|-\s+'))
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty && !_isTagWord(f))
        .toList();
    // Année seule dans un champ.
    fields = [
      for (final f in fields)
        if (RegExp(r'^(?:1[5-9]|20)\d{2}$').hasMatch(f))
          () {
            year ??= int.parse(f);
            return '';
          }()
        else
          f,
    ].where((f) => f.isNotEmpty).toList();
    if (fields.isEmpty) fields = [base.trim().isEmpty ? file : base.trim()];

    String clean(String s) {
      final words = s.trim().split(' ');
      // Formats, année, mots de liaison en fin : « Titre 2012 FRENCH EPUB »,
      // « 01net du ».
      while (words.length > 1 &&
          (_isTagWord(words.last) ||
              RegExp(r'^(?:(?:1[5-9]|20)\d{2}|du|de|des|le|la|the|of|-)$', caseSensitive: false)
                  .hasMatch(words.last))) {
        final w = words.removeLast();
        if (RegExp(r'^(?:1[5-9]|20)\d{2}$').hasMatch(w)) year ??= int.parse(w);
      }
      return words.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    switch (kind) {
      case BookKind.magazine:
        return BookGuess(
          kind: kind,
          title: clean(fields.first),
          series: clean(fields.first),
          issue: issue,
          year: year,
          month: month,
          day: day,
        );
      case BookKind.comic || BookKind.manga:
        // « Série - T01 - Titre », « Série T01 », « Série 03 ».
        double? volume;
        String? series, title;
        for (final (i, f) in fields.indexed) {
          final v = _volume.firstMatch(f);
          final bare = RegExp(r'^(\d{1,4})$').firstMatch(f);
          if (volume == null && (v != null || (bare != null && i > 0))) {
            volume = double.tryParse((v?[1] ?? bare![1]!).replaceAll(',', '.'));
            final before = (v == null ? '' : f.substring(0, v.start)).trim();
            series = before.isNotEmpty ? before : (i > 0 ? fields[i - 1] : null);
            final rest = fields.sublist(i + 1).join(' - ');
            title = rest.isNotEmpty ? rest : null;
            break;
          }
        }
        // « One Piece 012 » : numéro en fin de nom.
        if (volume == null) {
          final tail = RegExp(r'^(.*\D)\s+(\d{1,4})$').firstMatch(fields.first);
          if (tail != null) {
            series = tail[1]!.trim();
            volume = double.parse(tail[2]!);
          }
        }
        series = clean(series ?? fields.first);
        final parentSeries = dirs.isEmpty ? null : dirs.last;
        return BookGuess(
          kind: kind,
          title: clean(title ?? (volume == null ? fields.join(' - ') : '$series ${_volumeText(volume)}')),
          series: series.isEmpty ? parentSeries : series,
          volume: volume,
          year: year,
        );
      case BookKind.book:
        // « Auteur - Titre » le plus souvent ; « Nom, Prénom - Titre » chez
        // Calibre. Le titre peut contenir un tome (série).
        String? author;
        var title = fields.join(' - ');
        if (fields.length >= 2) {
          // « Titre T1 - Auteur » : le tome dit lequel est le titre.
          final swapped = _volume.hasMatch(fields.first) && !_volume.hasMatch(fields[1]);
          author = _author(swapped ? fields.last : fields.first);
          title = swapped
              ? fields.sublist(0, fields.length - 1).join(' - ')
              : fields.sublist(1).join(' - ');
        }
        final v = _volume.firstMatch(title);
        return BookGuess(
          kind: kind,
          title: clean(title),
          author: author,
          series: v == null ? null : clean(title.substring(0, v.start)).nullIfEmpty,
          volume: v == null ? null : double.tryParse(v[1]!.replaceAll(',', '.')),
          year: year,
        );
    }
  }

  static String _volumeText(double v) => v == v.roundToDouble() ? 'T${v.round()}' : 'T$v';

  /// « Hugo, Victor » → « Victor Hugo ».
  static String _author(String s) {
    final m = RegExp(r'^([^,]+),\s*([^,]+)$').firstMatch(s.trim());
    return m == null ? s.trim() : '${m[2]!.trim()} ${m[1]!.trim()}';
  }
}

extension on String {
  String? get nullIfEmpty => trim().isEmpty ? null : trim();
}

/// Un livre numérique : chemin, taille, infohash du torrent d'origine.
typedef EbookFile = ({String path, int size, String? hash});

/// Part des livres, en octets, au-delà de laquelle un torrent en est un
/// (pack de magazines, BD…) : la notice PDF d'un jeu ne compte pas.
const bookShare = 0.5;

/// Les livres numériques des torrents terminés (réponse `torrent-get`) qui
/// sont des torrents de livres : chemins sur le serveur.
List<EbookFile> booksOfTorrents(List<Map<String, dynamic>> torrents) {
  final out = <EbookFile>[];
  for (final t in torrents) {
    if (((t['percentDone'] as num?) ?? 0) < 1) continue;
    var total = 0, books = 0;
    final found = <EbookFile>[];
    for (final f in (t['files'] as List? ?? const []).whereType<Map>()) {
      final size = (f['length'] as num?)?.toInt() ?? 0;
      final path = '${t['downloadDir']}/${f['name']}'.replaceAll(RegExp('/+'), '/');
      total += size;
      if (!isBookPath(path)) continue;
      books += size;
      if (isBookSize(path, size)) {
        found.add((path: path, size: size, hash: '${t['hashString'] ?? ''}'.toLowerCase()));
      }
    }
    if (total > 0 && books / total >= bookShare) out.addAll(found);
  }
  return out;
}
