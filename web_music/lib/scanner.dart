import 'dart:convert';
import 'dart:io';

import 'package:c411_core/ftp.dart';
import 'package:c411_core/music_name.dart';

import 'config.dart';
import 'library.dart';
import 'transmission.dart';

// Le parcours, comme celui de la vidéothèque de l'application : d'abord
// les torrents terminés de Transmission (une requête), retrouvés sur le FTP
// par une correspondance des chemins, puis les dossiers choisis.

/// Un fichier audio d'un torrent terminé, chemin sur le serveur.
typedef TorrentAudio = ({String path, int size, String hash});

/// Part de l'audio, en octets, au-delà de laquelle un torrent est de la
/// musique : un jeu ou un film avec sa bande-son n'en est pas.
const musicShare = 0.5;

/// Les fichiers audio des torrents terminés qui sont de la musique.
List<TorrentAudio> musicOfTorrents(List<Map<String, dynamic>> torrents) {
  final out = <TorrentAudio>[];
  for (final t in torrents) {
    if (((t['percentDone'] as num?) ?? 0) < 1) continue;
    final files = (t['files'] as List? ?? const []).whereType<Map>().toList();
    var total = 0, audio = 0;
    final found = <TorrentAudio>[];
    for (final f in files) {
      final size = (f['length'] as num?)?.toInt() ?? 0;
      final path = '${t['downloadDir']}/${f['name']}'.replaceAll(RegExp('/+'), '/');
      total += size;
      if (isAudioPath(path)) {
        audio += size;
        if (size >= minTrackBytes) {
          found.add((path: path, size: size, hash: '${t['hashString'] ?? ''}'.toLowerCase()));
        }
      }
    }
    if (total > 0 && audio / total >= musicShare) out.addAll(found);
  }
  return out;
}

/// Garde les albums des dossiers parcourus qui ressemblent à de la musique :
/// au plus 100 pistes, de 1,5 Mo en moyenne au moins (les dossiers de
/// bruitages d'un jeu en ont des centaines, toutes petites).
List<MusicFile> plausibleAlbums(List<MusicFile> files) {
  final byDir = <String, List<MusicFile>>{};
  for (final f in files) {
    (byDir[f.albumDir] ??= []).add(f);
  }
  return [
    for (final group in byDir.values)
      if (group.length <= 100 &&
          group.fold(0, (n, f) => n + f.size) / group.length >= 1.5 * 1024 * 1024)
        ...group,
  ];
}

/// La correspondance Transmission → FTP de la vidéothèque de l'application
/// (préférences `mediaLibrary`), si elle en a une.
(String, String)? appPathMap(String? prefsPath) {
  if (prefsPath == null) return null;
  final file = File(prefsPath);
  if (!file.existsSync()) return null;
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map;
    final raw = json['flutter.mediaLibrary'] ?? json['mediaLibrary'];
    final library = raw is String ? jsonDecode(raw) as Map : raw as Map?;
    final from = library?['pathFrom'] as String?, to = library?['pathTo'] as String?;
    return from == null || to == null ? null : (from, to);
  } on Object {
    return null;
  }
}

/// Retrouve sur le FTP un fichier connu par son chemin sur le serveur : le
/// FTP montre en général la fin du chemin. Retourne (préfixe à retirer,
/// préfixe FTP). Même méthode que l'application.
Future<(String, String)?> detectPathMap(
    FtpClient ftp, String serverPath, int size, List<String> ftpRoots) async {
  final parts = serverPath.split('/').where((p) => p.isNotEmpty).toList();
  final prefixes = {
    '',
    for (final r in ftpRoots)
      if (r.trim().isNotEmpty && r.trim() != '/') r.trim().replaceAll(RegExp(r'/+$'), ''),
  };
  for (var i = 0; i < parts.length; i++) {
    for (final to in prefixes) {
      final candidate = '$to/${parts.sublist(i).join('/')}';
      final found = await ftp.size(candidate);
      if (found != null && (size == 0 || found == size)) {
        return ('/${parts.sublist(0, i).join('/')}', to);
      }
    }
  }
  return null;
}

/// Fichiers audio sous [roots] (8 niveaux au plus).
Future<List<MusicFile>> scanFolders(FtpClient ftp, List<String> roots,
    {void Function(String dir)? onFolder, int depth = 8}) async {
  final found = <MusicFile>[];
  Future<void> walk(String dir, int left) async {
    onFolder?.call(dir);
    final List<FtpEntry> entries;
    try {
      entries = await ftp.list(dir);
    } on FtpException {
      return; // Dossier illisible : on passe.
    }
    for (final e in entries) {
      if (e.name.startsWith('.')) continue;
      final path = dir == '/' ? '/${e.name}' : '$dir/${e.name}';
      if (e.isDir) {
        if (left > 0) await walk(path, left - 1);
      } else if (isAudioPath(path) && e.size >= minTrackBytes) {
        found.add(MusicFile(path: path, size: e.size));
      }
    }
  }

  for (final root in roots) {
    final r = root.trim();
    if (r.isEmpty) continue;
    await walk(r.length > 1 && r.endsWith('/') ? r.substring(0, r.length - 1) : r, depth);
  }
  return found;
}

/// Résultat d'un parcours : la discothèque, et un avertissement éventuel.
typedef ScanResult = ({MusicLibrary library, String? warning});

class Scanner {
  Scanner(this.config, {Future<FtpClient> Function()? connect, TransmissionRpc? rpc})
      : _connect = connect ??
            (() async {
              final ftp = FtpClient(config.ftp);
              await ftp.connect();
              return ftp;
            }),
        _rpc = rpc ??
            (config.hasTransmission
                ? TransmissionRpc(config.rpcUrl, user: config.rpcUser, password: config.rpcPassword)
                : null);

  final MusicConfig config;
  final Future<FtpClient> Function() _connect;
  final TransmissionRpc? _rpc;

  Future<ScanResult> scan(MusicLibrary previous, {void Function(String)? onStatus}) async {
    final roots = config.folders;
    final rpc = _rpc;
    var (pathFrom, pathTo) = (previous.pathFrom, previous.pathTo);
    if (pathFrom == null) {
      if (appPathMap(config.appLibrary) case (final from, final to)) {
        (pathFrom, pathTo) = (from, to);
      }
    }
    String? warning;
    final found = <String, MusicFile>{};
    FtpClient? ftp;
    Future<FtpClient> open() async {
      if (ftp != null) return ftp!;
      onStatus?.call('Connexion au FTP…');
      return ftp = await _connect();
    }

    try {
      if (rpc != null) {
        onStatus?.call('Torrents terminés…');
        final audio = musicOfTorrents(await rpc.torrents(
            ['hashString', 'downloadDir', 'percentDone', 'files']));
        if (audio.isNotEmpty) {
          final first = audio.first;
          if (pathFrom == null || !first.path.startsWith(pathFrom)) {
            onStatus?.call('Correspondance des chemins Transmission…');
            final map = await detectPathMap(await open(), first.path, first.size, roots);
            if (map != null) {
              (pathFrom, pathTo) = map;
            } else {
              warning = 'Fichiers des torrents introuvables sur le FTP (${first.path})';
            }
          }
          if (pathFrom != null) {
            for (final a in audio) {
              if (!a.path.startsWith(pathFrom)) continue;
              final path = '$pathTo${a.path.substring(pathFrom.length)}';
              found[path] = MusicFile(path: path, size: a.size, hash: a.hash);
            }
          }
        }
      }
      if (roots.isNotEmpty) {
        final client = await open();
        final files = await scanFolders(client, roots, onFolder: (d) => onStatus?.call('Dossier $d'));
        for (final f in plausibleAlbums(files)) {
          found.putIfAbsent(f.path, () => f);
        }
      }
    } finally {
      await ftp?.close();
    }

    final before = {for (final f in previous.files) f.path: f};
    final now = DateTime.now();
    return (
      library: MusicLibrary(
        files: [
          for (final f in found.values) f.copyWith(added: before[f.path]?.added ?? now),
        ],
        mb: previous.mb,
        scannedAt: now,
        pathFrom: pathFrom,
        pathTo: pathTo,
      ),
      warning: warning,
    );
  }

  void close() => _rpc?.close();
}
