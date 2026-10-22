import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

// Vrais .torrent pour les tests : morceaux et empreintes SHA-1 calculés sur
// les données, pour les comparaisons avec des fichiers du disque.

/// Bencode, avec les octets bruts (empreintes des morceaux).
Uint8List bencode(Object v) {
  final out = BytesBuilder();
  void w(Object v) {
    switch (v) {
      case int n:
        out.add(ascii.encode('i${n}e'));
      case Uint8List b:
        out
          ..add(ascii.encode('${b.length}:'))
          ..add(b);
      case String s:
        w(Uint8List.fromList(utf8.encode(s)));
      case List l:
        out.addByte(0x6c);
        for (final e in l) {
          w(e as Object);
        }
        out.addByte(0x65);
      case Map m:
        out.addByte(0x64);
        for (final k in (m.keys.cast<String>().toList()..sort())) {
          w(k);
          w(m[k] as Object);
        }
        out.addByte(0x65);
    }
  }

  w(v);
  return out.takeBytes();
}

/// Un vrai .torrent : morceaux de [pieceLength] octets et leurs SHA-1.
Uint8List realTorrent(String name, List<(List<String>, List<int>)> files, {int pieceLength = 16}) {
  final all = [for (final f in files) ...f.$2];
  final pieces = BytesBuilder();
  for (var i = 0; i < all.length; i += pieceLength) {
    pieces.add(sha1.convert(all.sublist(i, (i + pieceLength).clamp(0, all.length))).bytes);
  }
  final single = files.length == 1 && files.first.$1.isEmpty;
  return bencode({
    'announce': 'https://c411.org/announce/x',
    'info': {
      'name': name,
      'piece length': pieceLength,
      'pieces': pieces.takeBytes(),
      if (single)
        'length': files.first.$2.length
      else
        'files': [
          for (final (path, data) in files) {'path': path, 'length': data.length},
        ],
    },
  });
}

/// [n] octets reconnaissables (différents selon [seed]).
List<int> testBytes(int n, int seed) => List.generate(n, (i) => (i * 7 + seed) % 251);
