import 'dart:convert';
import 'dart:io';

import 'package:c411_core/ftp.dart';

/// Réglages du serveur : le JSON de réglages de l'application (voir
/// `personal.json.example`) pour le FTP, plus une section `music`
/// facultative :
///
/// ```json
/// "music": {
///   "host": "127.0.0.1",
///   "port": 8412,
///   "password": "",
///   "library": "/chemin/vers/shared_preferences.json",
///   "state": "/chemin/vers/music.json",
///   "contact": "https://exemple.org/moi",
///   "discogsToken": ""
/// }
/// ```
class MusicConfig {
  MusicConfig({
    required this.files,
    required this.library,
    required this.state,
    this.host = '127.0.0.1',
    this.port = 8412,
    this.password = '',
    this.contact = defaultContact,
    this.discogsToken = '',
  });

  final FilesConfig files;

  /// Préférences de l'application : sa base (clé `mediaLibrary`) contient la
  /// musique relevée par son parcours, comme les vidéos pour C411 TV.
  final String library;

  /// Fiches MusicBrainz des albums (et pochettes dans `covers/` à côté).
  final String state;
  final String host;
  final int port;

  /// Vide : pas d'authentification (autorisé seulement en local).
  final String password;

  /// Adresse de contact envoyée à MusicBrainz (User-Agent), qui l'exige.
  final String contact;

  /// Jeton personnel Discogs (discogs.com → Réglages → Développeurs) : albums
  /// inconnus de MusicBrainz, pochettes et styles manquants. Sans lui,
  /// Discogs n'est pas interrogé.
  final String discogsToken;

  static const defaultContact = 'https://codeberg.org/vachounet/114C';

  static String get _home => Platform.environment['HOME'] ?? '';

  static String get defaultState => '$_home/.local/share/c411_music/library.json';

  /// Où l'application range ses préférences sous Linux.
  static String get defaultLibrary =>
      '$_home/.local/share/fr.c411remote.c411_remote/shared_preferences.json';

  /// Lit [path] ; [overrides] : options de la ligne de commande.
  static MusicConfig load(String path, {Map<String, String> overrides = const {}}) {
    final json = jsonDecode(File(path).readAsStringSync());
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Le fichier de réglages doit être un objet JSON');
    }
    final music = (json['music'] as Map?)?.cast<String, dynamic>() ?? const {};
    String text(Map<String, dynamic> m, String k) => (m[k] as String?)?.trim() ?? '';
    String option(String key, String fallback) =>
        overrides[key] ?? (text(music, key).isEmpty ? fallback : text(music, key));

    return MusicConfig(
      files: filesConfigFromJson(json),
      library: option('library', defaultLibrary),
      state: option('state', defaultState),
      host: option('host', '127.0.0.1'),
      port: int.tryParse(overrides['port'] ?? '') ?? (music['port'] as num?)?.toInt() ?? 8412,
      password: overrides['password'] ?? (music['password'] as String? ?? ''),
      contact: option('contact', defaultContact),
      discogsToken: option('discogs-token', text(music, 'discogsToken')),
    );
  }

  /// Écoute ailleurs qu'en local.
  bool get public => !const {'127.0.0.1', 'localhost', '::1'}.contains(host);
}
