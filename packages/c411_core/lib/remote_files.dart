import 'ftp.dart';
import 'local_files.dart';
import 'webdav.dart';

/// Accès aux fichiers du serveur : FTP ([FtpConfig]), WebDAV
/// ([WebDavConfig]) ou un dossier de l'appareil ([LocalConfig]).
abstract interface class FilesConfig {
  bool get isEmpty;
}

class RemoteFilesException implements Exception {
  const RemoteFilesException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Élément d'un dossier.
class RemoteEntry {
  const RemoteEntry(this.name, {required this.isDir, this.size = 0});
  final String name;
  final bool isDir;
  final int size;
}

/// Ce que l'application et les serveurs web demandent aux fichiers du
/// serveur, quel que soit le protocole. Les chemins sont absolus (`/Films`).
abstract interface class RemoteFiles {
  Future<void> connect();

  /// Contenu d'un dossier.
  Future<List<RemoteEntry>> list(String path);

  /// Taille d'un fichier, ou null s'il n'existe pas.
  Future<int?> size(String path);

  /// Lit [path] à partir de [offset] ; annuler le flux arrête la lecture.
  Future<Stream<List<int>>> read(String path, {int offset = 0});

  /// Crée [path] et les dossiers au-dessus ; ceux qui existent ne gênent pas.
  Future<void> makeDirs(String path);

  /// Écrit [data] dans [path] (remplace le fichier existant).
  Future<void> write(String path, Stream<List<int>> data,
      {void Function(int sent)? onProgress});

  /// Plusieurs requêtes à la fois sur le même client (WebDAV) ; sinon une
  /// connexion par opération en parallèle (FTP).
  bool get concurrent;

  Future<void> close();
}

/// Client du protocole choisi (pas encore connecté).
RemoteFiles openRemoteFiles(FilesConfig config) => switch (config) {
      FtpConfig() => FtpClient(config),
      WebDavConfig() => WebDavClient(config),
      LocalConfig() => LocalFiles(config),
      _ => throw ArgumentError('Protocole inconnu : $config'),
    };

/// Accès aux fichiers depuis les réglages de l'application (JSON) :
/// `filesProtocol` (`ftp` par défaut, `webdav` ou `local`), puis `ftpHost`,
/// `ftpPort`, `ftpUser`, `ftpPassword`, `ftpTls`, ou `webdavUrl`,
/// `webdavUser`, `webdavPassword`, ou `localRoot`.
FilesConfig filesConfigFromJson(Map<String, dynamic> json) {
  String text(String k) => (json[k] as String?)?.trim() ?? '';
  if (text('filesProtocol') == 'local') {
    if (text('localRoot').isEmpty) {
      throw const FormatException('localRoot manquant dans le fichier de réglages');
    }
    return LocalConfig(text('localRoot'));
  }
  if (text('filesProtocol') == 'webdav') {
    if (text('webdavUrl').isEmpty) {
      throw const FormatException('webdavUrl manquant dans le fichier de réglages');
    }
    return WebDavConfig(
      url: text('webdavUrl'),
      user: text('webdavUser'),
      password: json['webdavPassword'] as String? ?? '',
    );
  }
  if (text('ftpHost').isEmpty) {
    throw const FormatException('ftpHost manquant dans le fichier de réglages');
  }
  return FtpConfig(
    host: text('ftpHost'),
    port: (json['ftpPort'] as num?)?.toInt() ?? 21,
    user: text('ftpUser'),
    password: json['ftpPassword'] as String? ?? '',
    tls: json['ftpTls'] as bool? ?? true,
  );
}
