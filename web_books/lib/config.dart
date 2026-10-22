import 'dart:convert';
import 'dart:io';

import 'package:c411_core/ftp.dart';

/// Réglages du serveur : le JSON de réglages de l'application (voir
/// `personal.json.example`) pour le FTP, plus une section `books`
/// facultative :
///
/// ```json
/// "books": {
///   "host": "127.0.0.1",
///   "port": 8413,
///   "password": "",
///   "library": "/chemin/vers/shared_preferences.json",
///   "state": "/chemin/vers/books.json",
///   "googleBooksKey": "",
///   "cacheGb": 2,
///   "contact": "https://exemple.org/moi"
/// }
/// ```
class BooksConfig {
  BooksConfig({
    required this.files,
    required this.library,
    required this.state,
    this.host = '127.0.0.1',
    this.port = 8413,
    this.password = '',
    this.googleBooksKey = '',
    this.cacheBytes = 2 << 30,
    this.contact = defaultContact,
  });

  final FilesConfig files;

  /// Préférences de l'application : sa base (clé `mediaLibrary`) contient les
  /// livres relevés par son parcours.
  final String library;

  /// Ce que le serveur sait des livres ; couvertures et copies locales dans
  /// le même dossier.
  final String state;
  final String host;
  final int port;

  /// Vide : pas d'authentification (autorisé seulement en local).
  final String password;

  /// Clé Google Books (gratuite) : de meilleurs résumés en français. Sans
  /// elle, Open Library seul.
  final String googleBooksKey;

  /// Place des copies locales (PDF, CBR lus en entier).
  final int cacheBytes;

  /// Adresse de contact envoyée à Open Library (User-Agent).
  final String contact;

  static const defaultContact = 'https://codeberg.org/vachounet/114C';

  static String get _home => Platform.environment['HOME'] ?? '';

  static String get defaultState => '$_home/.local/share/c411_books/books.json';

  /// Où l'application range ses préférences sous Linux.
  static String get defaultLibrary =>
      '$_home/.local/share/fr.c411remote.c411_remote/shared_preferences.json';

  /// Dossier des couvertures et des copies locales.
  String get cacheDir => File(state).parent.path;

  /// Lit [path] ; [overrides] : options de la ligne de commande.
  static BooksConfig load(String path, {Map<String, String> overrides = const {}}) {
    final json = jsonDecode(File(path).readAsStringSync());
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Le fichier de réglages doit être un objet JSON');
    }
    final books = (json['books'] as Map?)?.cast<String, dynamic>() ?? const {};
    String text(Map<String, dynamic> m, String k) => (m[k] as String?)?.trim() ?? '';
    String option(String key, String fallback) =>
        overrides[key] ?? (text(books, key).isEmpty ? fallback : text(books, key));

    final cacheGb = double.tryParse(overrides['cache-gb'] ?? '') ?? (books['cacheGb'] as num?)?.toDouble() ?? 2;
    return BooksConfig(
      files: filesConfigFromJson(json),
      library: option('library', defaultLibrary),
      state: option('state', defaultState),
      host: option('host', '127.0.0.1'),
      port: int.tryParse(overrides['port'] ?? '') ?? (books['port'] as num?)?.toInt() ?? 8413,
      password: overrides['password'] ?? (books['password'] as String? ?? ''),
      googleBooksKey: option('google-books-key', text(books, 'googleBooksKey')),
      cacheBytes: (cacheGb * (1 << 30)).round(),
      contact: option('contact', defaultContact),
    );
  }

  /// Écoute ailleurs qu'en local.
  bool get public => !const {'127.0.0.1', 'localhost', '::1'}.contains(host);
}
