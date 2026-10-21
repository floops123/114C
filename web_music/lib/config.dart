import 'dart:convert';
import 'dart:io';

import 'package:c411_core/ftp.dart';

/// Réglages du serveur : le JSON de réglages de l'application (voir
/// `personal.json.example`) pour le FTP, Transmission et les dossiers, plus
/// une section `music` facultative :
///
/// ```json
/// "music": {
///   "host": "127.0.0.1",
///   "port": 8412,
///   "password": "",
///   "folders": ["/musique"],
///   "state": "/chemin/vers/music.json",
///   "scanEvery": 180,
///   "contact": "https://exemple.org/moi"
/// }
/// ```
class MusicConfig {
  MusicConfig({
    required this.ftp,
    required this.state,
    this.rpcUrl = '',
    this.rpcUser = '',
    this.rpcPassword = '',
    this.folders = const [],
    this.appLibrary,
    this.host = '127.0.0.1',
    this.port = 8412,
    this.password = '',
    this.scanEvery = const Duration(minutes: 180),
    this.contact = defaultContact,
  });

  final FtpConfig ftp;

  /// Fichier de la discothèque (fichiers trouvés, fiches MusicBrainz).
  final String state;

  /// Transmission : les torrents terminés sont la première source.
  final String rpcUrl;
  final String rpcUser;
  final String rpcPassword;

  /// Dossiers du FTP à parcourir : `music.folders` et les `mediaFolders`
  /// de l'application.
  final List<String> folders;

  /// Préférences de l'application : la correspondance des chemins
  /// Transmission → FTP qu'elle a déjà établie pour la vidéothèque.
  final String? appLibrary;
  final String host;
  final int port;

  /// Vide : pas d'authentification (autorisé seulement en local).
  final String password;

  /// Intervalle entre deux parcours ; zéro : au démarrage et sur demande.
  final Duration scanEvery;

  /// Adresse de contact envoyée à MusicBrainz (User-Agent), qui l'exige.
  final String contact;

  static const defaultContact = 'https://codeberg.org/vachounet/114C';

  bool get hasTransmission => rpcUrl.isNotEmpty;

  static String get _home => Platform.environment['HOME'] ?? '';

  static String get defaultState => '$_home/.local/share/c411_music/library.json';

  /// Où l'application range ses préférences sous Linux.
  static String get defaultAppLibrary =>
      '$_home/.local/share/fr.c411remote.c411_remote/shared_preferences.json';

  /// Lit [path] ; [overrides] : options de la ligne de commande.
  static MusicConfig load(String path, {Map<String, String> overrides = const {}}) {
    final json = jsonDecode(File(path).readAsStringSync());
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Le fichier de réglages doit être un objet JSON');
    }
    final music = (json['music'] as Map?)?.cast<String, dynamic>() ?? const {};
    String text(Map<String, dynamic> m, String k) => (m[k] as String?)?.trim() ?? '';
    List<String> list(Object? v) => [
          for (final s in (v as List? ?? const []).whereType<String>())
            if (s.trim().isNotEmpty) s.trim(),
        ];

    final host = text(json, 'ftpHost');
    if (host.isEmpty) {
      throw const FormatException('ftpHost manquant dans le fichier de réglages');
    }
    final library = overrides['library'] ?? text(music, 'library');
    return MusicConfig(
      ftp: FtpConfig(
        host: host,
        port: (json['ftpPort'] as num?)?.toInt() ?? 21,
        user: text(json, 'ftpUser'),
        password: (json['ftpPassword'] as String?) ?? '',
        tls: json['ftpTls'] as bool? ?? true,
      ),
      rpcUrl: normalizeRpcUrl(text(json, 'rpcUrl')),
      rpcUser: text(json, 'rpcUser'),
      rpcPassword: (json['rpcPassword'] as String?) ?? '',
      folders: {
        ...?overrides['folder'] == null ? null : [overrides['folder']!],
        ...list(music['folders']),
        ...list(json['mediaFolders']),
      }.toList(),
      state: overrides['state'] ??
          (text(music, 'state').isEmpty ? defaultState : text(music, 'state')),
      appLibrary: library.isEmpty ? defaultAppLibrary : library,
      host: overrides['host'] ??
          (text(music, 'host').isEmpty ? '127.0.0.1' : text(music, 'host')),
      port: int.tryParse(overrides['port'] ?? '') ??
          (music['port'] as num?)?.toInt() ??
          8412,
      password: overrides['password'] ?? (music['password'] as String? ?? ''),
      scanEvery: Duration(
          minutes: int.tryParse(overrides['scan-every'] ?? '') ??
              (music['scanEvery'] as num?)?.toInt() ??
              180),
      contact: text(music, 'contact').isEmpty ? defaultContact : text(music, 'contact'),
    );
  }

  /// `https://hote:9091` → `https://hote:9091/transmission/rpc`, comme
  /// l'application.
  static String normalizeRpcUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return '';
    if (!u.contains('://')) u = 'http://$u';
    final uri = Uri.parse(u);
    if (uri.path.isEmpty || uri.path == '/') {
      return uri.replace(path: '/transmission/rpc').toString();
    }
    return u;
  }

  /// Écoute ailleurs qu'en local.
  bool get public => !const {'127.0.0.1', 'localhost', '::1'}.contains(host);
}
