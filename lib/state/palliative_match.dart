import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/bencode.dart';
import 'cross_seed.dart' show sameFiles;

// Soins palliatifs, deux autres sources que les trackers : un dossier de
// l'ordinateur, et les torrents déjà dans Transmission. Une sortie C411
// correspond si ses fichiers (chemins et tailles) sont là ; pour le disque,
// on vérifie en plus les empreintes du premier et du dernier morceau,
// comme le ferait le client.

/// Les fichiers d'un dossier de l'ordinateur, par taille.
class LocalIndex {
  LocalIndex(this.files) {
    for (final (path, size) in files) {
      (_bySize[size] ??= []).add(path);
      // Taille de chaque dossier parent : une sortie à plusieurs fichiers
      // correspond à un dossier de même taille totale.
      for (var dir = File(path).parent; dir.path != dir.parent.path; dir = dir.parent) {
        _dirSizes[dir.path] = (_dirSizes[dir.path] ?? 0) + size;
      }
    }
    for (final MapEntry(key: dir, value: size) in _dirSizes.entries) {
      (_dirsBySize[size] ??= []).add(dir);
    }
  }

  /// (chemin absolu, taille).
  final List<(String, int)> files;
  final _bySize = <int, List<String>>{};
  final _dirSizes = <String, int>{};
  final _dirsBySize = <int, List<String>>{};

  /// Un fichier ou un dossier de [size] octets existe : la sortie vaut la
  /// peine de télécharger son .torrent pour comparer.
  bool mayHold(int size) => size > 0 && (_bySize.containsKey(size) || _dirsBySize.containsKey(size));

  List<String> filesOfSize(int size) => _bySize[size] ?? const [];
  List<String> dirsOfSize(int size) => _dirsBySize[size] ?? const [];

  /// Parcourt [root] (sans les dossiers cachés ni les liens) ; [onCount]
  /// reçoit le nombre de fichiers vus.
  static Future<LocalIndex> scan(String root, {void Function(int count)? onCount}) async {
    final files = <(String, int)>[];
    final pending = [Directory(root)];
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      try {
        await for (final e in dir.list(followLinks: false)) {
          final name = e.path.split(Platform.pathSeparator).last;
          if (name.startsWith('.')) continue;
          if (e is Directory) {
            pending.add(e);
          } else if (e is File) {
            files.add((e.path, await e.length()));
            if (files.length % 500 == 0) onCount?.call(files.length);
          }
        }
      } on FileSystemException {
        // Dossier illisible : on passe.
      }
    }
    onCount?.call(files.length);
    return LocalIndex(files);
  }
}

/// Où sont, sur l'ordinateur, les fichiers d'un torrent.
class LocalMatch {
  const LocalMatch(this.root, this.files);

  /// Le fichier (torrent à un fichier) ou le dossier du torrent.
  final String root;

  /// Pour chaque fichier du torrent, dans son ordre : chemin dans le
  /// torrent, chemin local, taille.
  final List<(String, String, int)> files;
}

/// Cherche les fichiers de [t] dans [index] : même taille, mêmes chemins
/// sous un dossier (son nom peut différer), puis empreintes du premier et du
/// dernier morceau. null : pas sur ce disque.
Future<LocalMatch?> matchLocal(TorrentContent t, LocalIndex index) async {
  final sep = Platform.pathSeparator;
  final single = t.files.length == 1 && t.files.first.$1 == t.name;
  final candidates = <LocalMatch>[];
  if (single) {
    final length = t.files.first.$2;
    // Même nom d'abord.
    final paths = [...index.filesOfSize(length)]
      ..sort((a, b) => (a.endsWith('$sep${t.name}') ? 0 : 1).compareTo(b.endsWith('$sep${t.name}') ? 0 : 1));
    for (final p in paths) {
      candidates.add(LocalMatch(p, [(t.name, p, length)]));
    }
  } else {
    final dirs = [...index.dirsOfSize(t.totalSize)]
      ..sort((a, b) => (a.endsWith('$sep${t.name}') ? 0 : 1).compareTo(b.endsWith('$sep${t.name}') ? 0 : 1));
    for (final dir in dirs) {
      final files = <(String, String, int)>[];
      for (final (path, length) in t.files) {
        // Chemin dans le torrent : « nom/sous/fichier » ; sous le dossier
        // local, sans le premier élément.
        final relative = path.split('/').skip(1).join(sep);
        final local = '$dir$sep$relative';
        final file = File(local);
        if (!file.existsSync() || file.lengthSync() != length) break;
        files.add((path, local, length));
      }
      if (files.length == t.files.length) candidates.add(LocalMatch(dir, files));
    }
  }
  for (final m in candidates) {
    if (await piecesMatch(t, m)) return m;
  }
  return null;
}

/// Le premier et le dernier morceau des fichiers locaux ont les empreintes
/// du torrent. Sans empreintes (torrent incomplet) : vrai.
Future<bool> piecesMatch(TorrentContent t, LocalMatch m) async {
  final pieces = t.pieces;
  if (pieces == null || t.pieceLength <= 0 || pieces.length < 20) return true;
  final total = t.totalSize;
  if (total == 0) return true;
  final count = pieces.length ~/ 20;
  for (final index in {0, count - 1}) {
    final start = index * t.pieceLength;
    final length = (start + t.pieceLength > total ? total - start : t.pieceLength);
    final data = await _read(m.files, start, length);
    if (data == null) return false;
    final digest = sha1.convert(data).bytes;
    for (var i = 0; i < 20; i++) {
      if (digest[i] != pieces[index * 20 + i]) return false;
    }
  }
  return true;
}

/// [length] octets à partir de [start] dans les fichiers mis bout à bout.
Future<Uint8List?> _read(List<(String, String, int)> files, int start, int length) async {
  final out = BytesBuilder(copy: false);
  var offset = 0;
  for (final (_, path, size) in files) {
    final end = offset + size;
    if (end > start && offset < start + length) {
      final from = start > offset ? start - offset : 0;
      final to = (start + length < end ? start + length : end) - offset;
      final raf = await File(path).open();
      try {
        await raf.setPosition(from);
        out.add(await raf.read(to - from));
      } on FileSystemException {
        return null;
      } finally {
        await raf.close();
      }
    }
    offset = end;
    if (offset >= start + length) break;
  }
  final bytes = out.takeBytes();
  return bytes.length == length ? bytes : null;
}

/// Le torrent terminé de Transmission (réponse `torrent-get` avec `files`,
/// `percentDone`) qui a exactement les fichiers de [t], ou null.
Map<String, dynamic>? matchClient(TorrentContent t, List<Map<String, dynamic>> torrents) {
  for (final c in torrents) {
    if (((c['percentDone'] as num?) ?? 0) < 1) continue;
    final files = [
      for (final f in (c['files'] as List? ?? const []).whereType<Map>())
        ('${f['name']}', (f['length'] as num?)?.toInt() ?? -1),
    ];
    if (files.fold(0, (n, f) => n + f.$2) != t.totalSize) continue;
    if (sameFiles(files, t.files)) return c;
  }
  return null;
}
