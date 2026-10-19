import 'dart:convert';
import 'dart:io';

/// Convertit un JSON de réglages personnels en `--dart-define` à passer à
/// `flutter build`. Les valeurs sont compilées dans le binaire (pas
/// embarquées comme asset : le JSON lui-même ne va pas dans l'APK).
///
/// Usage :
///
/// ```sh
/// # Imprimer les flags (un par ligne) :
/// dart run tool/build_personal.dart personal.json
///
/// # Lancer directement un build Android :
/// dart run tool/build_personal.dart personal.json --build apk
///
/// # Cible libre : apk, appbundle, linux, web, etc.
/// dart run tool/build_personal.dart personal.json --build linux
/// ```
///
/// Le format JSON est celui de [`AppSettings.toJson()`] (cf.
/// `lib/core/settings.dart`). Tous les champs sont facultatifs.
///
/// Format du JSON :
///
/// ```json
/// {
///   "rpcUrl": "http://seedbox.local:9091/transmission/rpc",
///   "rpcUser": "admin",
///   "rpcPassword": "secret",
///   "sessionCookie": "connect_sid=xyz",
///   "tmdbKey": "...",
///   "jellyfinUrl": "http://seedbox.local:8096",
///   "jellyfinKey": "...",
///   "ftpHost": "app.seedbox.local",
///   "ftpPort": 21,
///   "ftpUser": "...",
///   "ftpPassword": "...",
///   "ftpTls": true,
///   "mediaFolders": ["/torrents/completed", "/data/media"],
///   "apiKeys": {
///     "c411": "...",
///     "tr4ker": "...",
///     "nostradamus": "...",
///     "astratorrent": "..."
///   }
/// }
/// ```
void main(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stderr.writeln('Usage :');
    stderr.writeln('  dart run tool/build_personal.dart <personal.json>');
    stderr.writeln('     → imprime les --dart-define (un par ligne)');
    stderr.writeln(
        '  dart run tool/build_personal.dart <personal.json> --build <cible>');
    stderr.writeln('     → lance `flutter build <cible> --dart-define=…`');
    exit(args.isEmpty ? 1 : 0);
  }

  final jsonPath = args.first;
  final buildIndex = args.indexOf('--build');
  final buildTarget =
      buildIndex >= 0 && buildIndex + 1 < args.length ? args[buildIndex + 1] : null;

  final flags = personalJsonToFlags(loadJson(jsonPath));

  if (buildTarget == null) {
    for (final f in flags) {
      stdout.writeln(f);
    }
    return;
  }

  final result = await Process.run(
    'flutter',
    ['build', buildTarget, ...flags],
    runInShell: true,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exit(result.exitCode);
}

/// Charge et décode un JSON de réglages. Leve `FormatException` si le JSON
/// est mal formé ou absent.
Map<String, dynamic> loadJson(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FormatException('Fichier introuvable : $path');
  }
  final raw = file.readAsStringSync();
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('La racine du JSON doit être un objet : $path');
  }
  return decoded;
}

/// Construit la liste de `--dart-define` à partir d'un JSON de réglages.
/// Pure (pas d'I/O, pas d'horloge) : facile à tester.
List<String> personalJsonToFlags(Map<String, dynamic> json) {
  final out = <String>[];

  // Champs scalaires : JSON key → variable d'environnement.
  for (final entry in const {
    'rpcUrl': 'C411_RPC_URL',
    'rpcUser': 'C411_RPC_USER',
    'rpcPassword': 'C411_RPC_PASSWORD',
    'sessionCookie': 'C411_SESSION_COOKIE',
    'tmdbKey': 'C411_TMDB_KEY',
    'jellyfinUrl': 'C411_JELLYFIN_URL',
    'jellyfinKey': 'C411_JELLYFIN_KEY',
    'ftpHost': 'C411_FTP_HOST',
    'ftpPort': 'C411_FTP_PORT',
    'ftpUser': 'C411_FTP_USER',
    'ftpPassword': 'C411_FTP_PASSWORD',
    'ftpTls': 'C411_FTP_TLS',
  }.entries) {
    final value = json[entry.key];
    if (value == null) continue;
    final s = value.toString();
    if (s.isEmpty) continue;
    out.add('--dart-define=${entry.value}=$s');
  }

  // Liste de dossiers : CSV en C411_MEDIA_FOLDERS.
  final folders = json['mediaFolders'];
  if (folders is List && folders.isNotEmpty) {
    final csv = folders.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join(',');
    if (csv.isNotEmpty) out.add('--dart-define=C411_MEDIA_FOLDERS=$csv');
  }

  // Clés d'API par tracker : C411_<TRACKER>_KEY.
  final apiKeys = json['apiKeys'];
  if (apiKeys is Map) {
    for (final entry in apiKeys.entries) {
      final value = entry.value;
      if (value == null) continue;
      final s = value.toString();
      if (s.isEmpty) continue;
      out.add('--dart-define=C411_${entry.key.toString().toUpperCase()}_KEY=$s');
    }
  }

  return out;
}