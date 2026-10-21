import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Lit [length] octets à partir de [start] (une requête `Range`).
typedef RangeReader = Future<Uint8List> Function(int start, int length);

/// Une entrée d'archive ZIP.
class ZipEntry {
  const ZipEntry({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.size,
    required this.offset,
  });

  final String name;

  /// 0 : stockée ; 8 : deflate.
  final int method;
  final int compressedSize;
  final int size;

  /// Position de l'en-tête local.
  final int offset;

  bool get isDirectory => name.endsWith('/');
}

class ZipException implements Exception {
  const ZipException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Archive ZIP (EPUB, CBZ) lue à distance, par morceaux : le répertoire
/// central à la fin, puis seulement les entrées demandées. Une BD de 200 Mo
/// donne sa couverture en trois petites requêtes.
class RemoteZip {
  RemoteZip._(this._read, this.entries);

  final RangeReader _read;
  final List<ZipEntry> entries;

  /// Ouvre l'archive de [size] octets.
  static Future<RemoteZip> open(RangeReader read, int size) async {
    if (size < 22) throw const ZipException('Archive trop petite');
    // Fin de l'archive : le répertoire central y est décrit (commentaire de
    // 64 Ko au plus).
    final tailLength = size < 65557 ? size : 65557;
    final tail = await read(size - tailLength, tailLength);
    final data = ByteData.sublistView(tail);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (data.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw const ZipException('Archive ZIP illisible');
    var count = data.getUint16(eocd + 10, Endian.little);
    var cdSize = data.getUint32(eocd + 12, Endian.little);
    var cdOffset = data.getUint32(eocd + 16, Endian.little);
    // ZIP64 : le localisateur précède la fin d'archive.
    if (cdOffset == 0xffffffff || count == 0xffff) {
      final locator = eocd - 20;
      if (locator < 0 || data.getUint32(locator, Endian.little) != 0x07064b50) {
        throw const ZipException('Archive ZIP64 illisible');
      }
      final at = data.getUint64(locator + 8, Endian.little);
      final z = ByteData.sublistView(await read(at, 56));
      count = z.getUint64(32, Endian.little);
      cdSize = z.getUint64(40, Endian.little);
      cdOffset = z.getUint64(48, Endian.little);
    }
    final cdStart = size - tailLength;
    final cd = cdOffset >= cdStart && cdOffset + cdSize <= size
        ? Uint8List.sublistView(tail, cdOffset - cdStart, cdOffset - cdStart + cdSize)
        : await read(cdOffset, cdSize);
    return RemoteZip._(read, _parseDirectory(cd, count));
  }

  static List<ZipEntry> _parseDirectory(Uint8List cd, int count) {
    final data = ByteData.sublistView(cd);
    final entries = <ZipEntry>[];
    var p = 0;
    for (var n = 0; n < count && p + 46 <= cd.length; n++) {
      if (data.getUint32(p, Endian.little) != 0x02014b50) break;
      final flags = data.getUint16(p + 8, Endian.little);
      final method = data.getUint16(p + 10, Endian.little);
      var compressed = data.getUint32(p + 20, Endian.little);
      var size = data.getUint32(p + 24, Endian.little);
      final nameLength = data.getUint16(p + 28, Endian.little);
      final extraLength = data.getUint16(p + 30, Endian.little);
      final commentLength = data.getUint16(p + 32, Endian.little);
      var offset = data.getUint32(p + 42, Endian.little);
      final rawName = cd.sublist(p + 46, p + 46 + nameLength);
      // Bit 11 : UTF-8 ; sinon souvent UTF-8 quand même, à défaut latin-1.
      final name = (flags & 0x800) != 0
          ? utf8.decode(rawName, allowMalformed: true)
          : _decodeName(rawName);
      // Champ ZIP64 : tailles et position au-delà de 4 Go.
      var e = p + 46 + nameLength;
      final extraEnd = e + extraLength;
      while (e + 4 <= extraEnd) {
        final id = data.getUint16(e, Endian.little);
        final len = data.getUint16(e + 2, Endian.little);
        if (id == 1) {
          var q = e + 4;
          if (size == 0xffffffff) {
            size = data.getUint64(q, Endian.little);
            q += 8;
          }
          if (compressed == 0xffffffff) {
            compressed = data.getUint64(q, Endian.little);
            q += 8;
          }
          if (offset == 0xffffffff) offset = data.getUint64(q, Endian.little);
        }
        e += 4 + len;
      }
      entries.add(ZipEntry(
          name: name, method: method, compressedSize: compressed, size: size, offset: offset));
      p += 46 + nameLength + extraLength + commentLength;
    }
    return entries;
  }

  static String _decodeName(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  ZipEntry? entry(String name) {
    for (final e in entries) {
      if (e.name == name) return e;
    }
    final lower = name.toLowerCase();
    for (final e in entries) {
      if (e.name.toLowerCase() == lower) return e;
    }
    return null;
  }

  /// Contenu décompressé de [e] (en une requête le plus souvent).
  Future<Uint8List> read(ZipEntry e) async {
    // En-tête local (30 octets + nom + champ extra, de taille inconnue
    // d'avance) puis les données : une marge suffit presque toujours.
    const slack = 1024;
    var chunk = await _read(e.offset, 30 + slack + e.compressedSize);
    final data = ByteData.sublistView(chunk);
    if (chunk.length < 30 || data.getUint32(0, Endian.little) != 0x04034b50) {
      throw ZipException('Entrée illisible : ${e.name}');
    }
    final start = 30 + data.getUint16(26, Endian.little) + data.getUint16(28, Endian.little);
    if (chunk.length < start + e.compressedSize) {
      chunk = await _read(e.offset + start, e.compressedSize);
    } else {
      chunk = Uint8List.sublistView(chunk, start, start + e.compressedSize);
    }
    return switch (e.method) {
      0 => chunk,
      8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(chunk)),
      _ => throw ZipException('Compression non prise en charge (${e.method}) : ${e.name}'),
    };
  }

  Future<String> readText(ZipEntry e) async => utf8.decode(await read(e), allowMalformed: true);
}

/// Lecteur de plages pour une URL HTTP qui accepte `Range` (le relais FTP).
RangeReader httpRanges(HttpClient http, Uri url) => (start, length) async {
      final request = await http.getUrl(url);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-${start + length - 1}');
      final reply = await request.close();
      if (reply.statusCode != 206 && reply.statusCode != 200) {
        await reply.drain<void>();
        throw HttpException('Lecture impossible (HTTP ${reply.statusCode})');
      }
      final b = BytesBuilder(copy: false);
      await for (final chunk in reply) {
        b.add(chunk);
      }
      final bytes = b.takeBytes();
      // Un serveur qui ignore Range renvoie tout : on découpe.
      if (reply.statusCode == 200 && bytes.length > length) {
        return Uint8List.sublistView(bytes, start, start + length > bytes.length ? bytes.length : start + length);
      }
      return bytes;
    };
