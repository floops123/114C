import 'dart:convert';
import 'dart:io';

import 'package:c411_core/ftp.dart';

/// Réglages du serveur : le JSON de réglages de l'application (celui de
/// `tool/build_personal.dart`, voir `personal.json.example`) pour le FTP et
/// TMDB, plus une section `web` facultative :
///
/// ```json
/// "web": {
///   "host": "127.0.0.1",
///   "port": 8411,
///   "password": "",
///   "library": "/chemin/vers/shared_preferences.json"
/// }
/// ```
class WebConfig {
  WebConfig({
    required this.files,
    required this.library,
    this.tmdbKey = '',
    this.host = '127.0.0.1',
    this.port = 8411,
    this.password = '',
  });

  final FilesConfig files;

  /// Fichier de la vidéothèque : les préférences de l'application (clé
  /// `mediaLibrary`), ou un export de la base seule.
  final String library;
  final String tmdbKey;
  final String host;
  final int port;

  /// Vide : pas d'authentification (autorisé seulement en local).
  final String password;

  /// Où l'application range ses préférences sous Linux.
  static String get defaultLibrary =>
      '${Platform.environment['HOME'] ?? ''}/.local/share/'
      'fr.c411remote.c411_remote/shared_preferences.json';

  /// Lit [path] ; [overrides] : options de la ligne de commande.
  static WebConfig load(String path, {Map<String, String> overrides = const {}}) {
    final json = jsonDecode(File(path).readAsStringSync());
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Le fichier de réglages doit être un objet JSON');
    }
    final web = (json['web'] as Map?)?.cast<String, dynamic>() ?? const {};
    String text(Map<String, dynamic> m, String k) => (m[k] as String?)?.trim() ?? '';

    return WebConfig(
      files: filesConfigFromJson(json),
      tmdbKey: text(json, 'tmdbKey'),
      library: overrides['library'] ??
          (text(web, 'library').isEmpty ? defaultLibrary : text(web, 'library')),
      host: overrides['host'] ?? (text(web, 'host').isEmpty ? '127.0.0.1' : text(web, 'host')),
      port: int.tryParse(overrides['port'] ?? '') ??
          (web['port'] as num?)?.toInt() ??
          8411,
      password: overrides['password'] ?? (web['password'] as String? ?? ''),
    );
  }

  /// Écoute ailleurs qu'en local.
  bool get public =>
      !const {'127.0.0.1', 'localhost', '::1'}.contains(host);
}
