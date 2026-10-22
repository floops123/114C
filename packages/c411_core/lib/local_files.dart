import 'dart:async';
import 'dart:io';

import 'remote_files.dart';

/// Fichiers dans un dossier de l'appareil (disque, NAS monté, partage
/// réseau) : [root] tient lieu de racine, les chemins demandés (`/Films/x.mkv`)
/// lui sont ajoutés.
class LocalConfig implements FilesConfig {
  const LocalConfig(this.root);
  final String root;

  @override
  bool get isEmpty => root.isEmpty;
}

class LocalFiles implements RemoteFiles {
  LocalFiles(this.config);
  final LocalConfig config;

  @override
  bool get concurrent => true;

  /// Chemin sur l'appareil ; `..` refusé (on reste sous la racine).
  String pathOf(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty && p != '.').toList();
    if (parts.contains('..')) {
      throw RemoteFilesException('Chemin hors du dossier : $path');
    }
    final root = config.root.endsWith(Platform.pathSeparator) && config.root.length > 1
        ? config.root.substring(0, config.root.length - 1)
        : config.root;
    return [root, ...parts].join(Platform.pathSeparator);
  }

  @override
  Future<void> connect() async {
    if (!await Directory(config.root).exists()) {
      throw RemoteFilesException('Dossier introuvable : ${config.root}');
    }
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final dir = Directory(pathOf(path));
    if (!await dir.exists()) {
      throw RemoteFilesException('Dossier introuvable : $path');
    }
    final entries = <RemoteEntry>[];
    try {
      await for (final e in dir.list(followLinks: true)) {
        final name = e.path.split(Platform.pathSeparator).lastWhere((s) => s.isNotEmpty);
        final stat = await e.stat();
        if (stat.type == FileSystemEntityType.directory) {
          entries.add(RemoteEntry(name, isDir: true));
        } else if (stat.type == FileSystemEntityType.file) {
          entries.add(RemoteEntry(name, isDir: false, size: stat.size));
        }
      }
    } on FileSystemException catch (e) {
      throw RemoteFilesException('Lecture du dossier refusée : ${e.message}');
    }
    return entries;
  }

  @override
  Future<int?> size(String path) async {
    final file = File(pathOf(path));
    return await file.exists() ? file.length() : null;
  }

  @override
  Future<Stream<List<int>>> read(String path, {int offset = 0}) async {
    final file = File(pathOf(path));
    if (!await file.exists()) {
      throw RemoteFilesException('Fichier introuvable : $path');
    }
    return file.openRead(offset);
  }

  @override
  Future<void> makeDirs(String path) async {
    try {
      await Directory(pathOf(path)).create(recursive: true);
    } on FileSystemException catch (e) {
      throw RemoteFilesException('Création du dossier refusée : ${e.message}');
    }
  }

  @override
  Future<void> write(String path, Stream<List<int>> data,
      {void Function(int sent)? onProgress}) async {
    final sink = File(pathOf(path)).openWrite();
    var sent = 0;
    try {
      await for (final chunk in data) {
        sink.add(chunk);
        sent += chunk.length;
        onProgress?.call(sent);
      }
      await sink.flush();
    } on FileSystemException catch (e) {
      throw RemoteFilesException('Écriture refusée : ${e.message}');
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> close() async {}
}
