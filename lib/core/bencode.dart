import 'dart:convert';
import 'dart:typed_data';

/// Décodeur bencode minimal (format des fichiers .torrent).
/// Entiers → int, chaînes → Uint8List, listes → List, dictionnaires →
/// `Map<String, Object?>` (clés décodées en UTF-8).
Object? bdecode(Uint8List data) {
  var i = 0;

  Object? value() {
    if (i >= data.length) throw const FormatException('bencode tronqué');
    final c = data[i];
    if (c == 0x69) {
      // i<entier>e
      final end = data.indexOf(0x65, i);
      if (end < 0) throw const FormatException('entier bencode non terminé');
      final n = int.parse(ascii.decode(data.sublist(i + 1, end)));
      i = end + 1;
      return n;
    }
    if (c == 0x6c) {
      // l…e
      i++;
      final list = <Object?>[];
      while (data[i] != 0x65) {
        list.add(value());
      }
      i++;
      return list;
    }
    if (c == 0x64) {
      // d…e
      i++;
      final map = <String, Object?>{};
      while (data[i] != 0x65) {
        final key = utf8.decode(value() as Uint8List, allowMalformed: true);
        map[key] = value();
      }
      i++;
      return map;
    }
    // <longueur>:<octets>
    final colon = data.indexOf(0x3a, i);
    if (colon < 0) throw const FormatException('chaîne bencode invalide');
    final length = int.parse(ascii.decode(data.sublist(i, colon)));
    final start = colon + 1;
    if (start + length > data.length) {
      throw const FormatException('chaîne bencode tronquée');
    }
    i = start + length;
    return Uint8List.sublistView(data, start, start + length);
  }

  return value();
}

/// Fichiers décrits par un .torrent, avec les chemins tels que Transmission
/// les nomme : `nom` (torrent à un fichier) ou `nom/dossier/fichier`.
class TorrentContent {
  const TorrentContent(this.name, this.files, {this.pieceLength = 0, this.pieces});

  final String name;
  final List<(String path, int length)> files;

  /// Taille d'un morceau, et les empreintes SHA-1 des morceaux (20 octets
  /// chacune, bout à bout) : de quoi vérifier des données sans le client.
  final int pieceLength;
  final Uint8List? pieces;

  int get totalSize => files.fold(0, (sum, f) => sum + f.$2);

  factory TorrentContent.parse(Uint8List torrent) {
    final root = bdecode(torrent);
    if (root is! Map<String, Object?> || root['info'] is! Map<String, Object?>) {
      throw const FormatException('.torrent sans dictionnaire info');
    }
    final info = root['info'] as Map<String, Object?>;
    String text(Object? v) =>
        v is Uint8List ? utf8.decode(v, allowMalformed: true) : '$v';
    // `name.utf-8` prime quand il existe (anciens torrents).
    final name = text(info['name.utf-8'] ?? info['name']);
    final files = info['files'];
    final pieceLength = info['piece length'] is int ? info['piece length'] as int : 0;
    final pieces = info['pieces'] is Uint8List ? info['pieces'] as Uint8List : null;
    if (files is List) {
      return TorrentContent(name, pieceLength: pieceLength, pieces: pieces, [
        for (final f in files.whereType<Map<String, Object?>>())
          (
            [
              name,
              for (final part in (f['path.utf-8'] ?? f['path']) as List) text(part),
            ].join('/'),
            f['length'] as int,
          ),
      ]);
    }
    return TorrentContent(name, [(name, info['length'] as int)],
        pieceLength: pieceLength, pieces: pieces);
  }
}
