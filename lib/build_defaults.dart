import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/settings.dart';

/// Réglages injectés au build : permettent de produire une variante de
/// l'application avec tous les identifiants préenregistrés. Au premier
/// lancement (trousseau vide), les valeurs sont écrites dans le trousseau du
/// système ; les lancements suivants lisent depuis le trousseau et les
/// modifications dans *Réglages* priment toujours.
///
/// Deux sources, fusionnées (la première gagne) :
///
/// 1. **Fichier JSON** : `--dart-define=C411_DEFAULTS_FILE=<chemin>`. Si le
///    chemin commence par `assets/`, le fichier est lu depuis le bundle
///    d'assets de Flutter (à déclarer dans `pubspec.yaml` côté utilisateur).
///    Sinon, il est lu depuis le système de fichiers. Le format est celui
///    de [`AppSettings.toJson()`](../lib/core/settings.dart).
/// 2. **Variables individuelles** : `--dart-define=C411_<NOM>=<valeur>`.
///    Voir la liste complète dans [allVariables]. Pratique pour surcharger
///    une ou deux valeurs du fichier, ou pour ne pas en utiliser.
///
/// Les variables individuelles l'emportent sur le fichier quand les deux
/// définissent la même clé : on peut ainsi corriger une valeur dans la
/// ligne de commande sans éditer le fichier.
///
/// **Sécurité** : les deux mécanismes placent les valeurs dans le binaire
/// (l'asset est intégré à l'APK, le fichier lu sur disque n'est
/// généralement utile qu'en développement). Pour une distribution
/// largement partagée, garder les secrets dans le trousseau (Réglage
/// normal). Pour une image *personnelle* ou familiale, c'est l'usage prévu.
class BuildDefaults {
  /// Construit un `BuildDefaults` vide (cas par défaut : aucun défaut au
  /// build, l'utilisateur saisit ses réglages).
  BuildDefaults.empty() : _values = Map.unmodifiable(const {});

  /// Construit un `BuildDefaults` à partir d'une map explicite. Réservé
  /// aux tests : en production, passer par [load].
  @visibleForTesting
  BuildDefaults.fromMap(Map<String, String> values)
      : _values = Map.unmodifiable(values);

  /// Lit les valeurs depuis les variables `--dart-define` et le fichier
  /// JSON pointé par `C411_DEFAULTS_FILE`. Le fichier est lu *après* les
  /// variables individuelles : ces dernières gagnent en cas de doublon.
  static Future<BuildDefaults> load() async {
    final values = <String, String>{};

    // 1) Fichier JSON (s'il est défini).
    const filePath = String.fromEnvironment('C411_DEFAULTS_FILE');
    if (filePath.isNotEmpty) {
      try {
        final fromFile = await _readFile(filePath);
        if (fromFile != null) {
          for (final entry in fromFile.entries) {
            if (entry.value.isNotEmpty) values[entry.key] = entry.value;
          }
        }
      } on Object catch (e, st) {
        // On ne fait pas échouer l'application : l'utilisateur verra les
        // Réglages vides et pourra les saisir à la main.
        developer.log('C411_DEFAULTS_FILE illisible : $e', error: e, stackTrace: st);
      }
    }

    // 2) Variables individuelles (`--dart-define=C411_<NOM>=...`), qui
    // prennent le pas sur le fichier.
    for (final name in allVariables) {
      const raw = String.fromEnvironment('PLACEHOLDER_NEVER_USED');
      if (raw.isEmpty) continue;
      final v = _envLookup(name);
      if (v != null && v.isNotEmpty) values[name] = v;
    }

    return BuildDefaults.fromMap(values);
  }

  /// Lit un fichier JSON et le décode en `Map<String, String>` (les valeurs
  /// non textuelles — `int`, `bool`, `List<String>` — sont sérialisées en
  /// leur représentation JSON).
  ///
  /// Les chemins en `assets/…` passent par `rootBundle.loadString` ; les
  /// autres sont lus sur le disque (utile en développement, ou sur
  /// Android/iOS avec un fichier posé manuellement).
  static Future<Map<String, String>?> _readFile(String path) async {
    final String content;
    if (path.startsWith('assets/')) {
      content = await rootBundle.loadString(path);
    } else {
      final file = File(path);
      if (!await file.exists()) {
        developer.log('C411_DEFAULTS_FILE introuvable : $path');
        return null;
      }
      content = await file.readAsString();
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map) return const <String, String>{};
    return {
      for (final entry in decoded.entries)
        if (entry.value != null) entry.key.toString(): entry.value.toString(),
    };
  }

  final Map<String, String> _values;

  /// Toutes les variables `--dart-define` reconnues (cf. tableau dans la
  /// documentation). Sert au test et à la doc.
  static const List<String> allVariables = [
    'C411_RPC_URL',
    'C411_RPC_USER',
    'C411_RPC_PASSWORD',
    'C411_SESSION_COOKIE',
    'C411_TMDB_KEY',
    'C411_JELLYFIN_URL',
    'C411_JELLYFIN_KEY',
    'C411_FTP_HOST',
    'C411_FTP_PORT',
    'C411_FTP_USER',
    'C411_FTP_PASSWORD',
    'C411_FTP_TLS',
    'C411_MEDIA_FOLDERS',
    'C411_C411_KEY',
    'C411_TR4KER_KEY',
    'C411_NOSTRADAMUS_KEY',
    'C411_ASTRATORRENT_KEY',
  ];

  /// Au moins une valeur a été trouvée.
  bool get hasAny => _values.isNotEmpty;

  Map<String, String> get values => _values;

  /// Construit l'`AppSettings` à partir des variables reconnues. Les champs
  /// non renseignés prennent les valeurs par défaut de `AppSettings`.
  AppSettings toAppSettings() {
    String? s(String name) {
      final v = _values[name];
      return (v == null || v.isEmpty) ? null : v;
    }

    bool? b(String name) {
      final v = s(name);
      if (v == null) return null;
      final low = v.toLowerCase();
      return low == 'true' || low == '1' || low == 'yes';
    }

    final foldersCsv = s('C411_MEDIA_FOLDERS');
    final folders = foldersCsv == null
        ? const <String>[]
        : (foldersCsv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)
            .toList());
    final apiKeys = <String, String>{};
    for (final tracker in const ['c411', 'tr4ker', 'nostradamus', 'astratorrent']) {
      final v = s('C411_${tracker.toUpperCase()}_KEY');
      if (v != null) apiKeys[tracker] = v;
    }
    return AppSettings(
      rpcUrl: s('C411_RPC_URL') ?? '',
      rpcUser: s('C411_RPC_USER') ?? '',
      rpcPassword: s('C411_RPC_PASSWORD') ?? '',
      apiKeys: apiKeys,
      sessionCookie: s('C411_SESSION_COOKIE') ?? '',
      tmdbKey: s('C411_TMDB_KEY') ?? '',
      jellyfinUrl: s('C411_JELLYFIN_URL') ?? '',
      jellyfinKey: s('C411_JELLYFIN_KEY') ?? '',
      ftpHost: s('C411_FTP_HOST') ?? '',
      ftpPort: int.tryParse(s('C411_FTP_PORT') ?? '') ?? 21,
      ftpUser: s('C411_FTP_USER') ?? '',
      ftpPassword: s('C411_FTP_PASSWORD') ?? '',
      ftpTls: b('C411_FTP_TLS') ?? true,
      mediaFolders: folders,
    );
  }
}

/// Provider Riverpod qui expose le `BuildDefaults` chargé au démarrage.
/// `main.dart` appelle `BuildDefaults.load()` et écrase ce provider dans le
/// `ProviderScope` ; les tests font de même.
final buildDefaultsProvider = Provider<BuildDefaults>((ref) =>
    throw UnimplementedError('Surchargé dans main() ou par les tests'));

/// `String.fromEnvironment` exige un littéral : on passe par une fonction
/// qui fait le switch (sans constexpr).
String? _envLookup(String name) {
  // ignore: deprecated_member_use
  return switch (name) {
    'C411_RPC_URL' => _constOrEmpty('C411_RPC_URL'),
    'C411_RPC_USER' => _constOrEmpty('C411_RPC_USER'),
    'C411_RPC_PASSWORD' => _constOrEmpty('C411_RPC_PASSWORD'),
    'C411_SESSION_COOKIE' => _constOrEmpty('C411_SESSION_COOKIE'),
    'C411_TMDB_KEY' => _constOrEmpty('C411_TMDB_KEY'),
    'C411_JELLYFIN_URL' => _constOrEmpty('C411_JELLYFIN_URL'),
    'C411_JELLYFIN_KEY' => _constOrEmpty('C411_JELLYFIN_KEY'),
    'C411_FTP_HOST' => _constOrEmpty('C411_FTP_HOST'),
    'C411_FTP_PORT' => _constOrEmpty('C411_FTP_PORT'),
    'C411_FTP_USER' => _constOrEmpty('C411_FTP_USER'),
    'C411_FTP_PASSWORD' => _constOrEmpty('C411_FTP_PASSWORD'),
    'C411_FTP_TLS' => _constOrEmpty('C411_FTP_TLS'),
    'C411_MEDIA_FOLDERS' => _constOrEmpty('C411_MEDIA_FOLDERS'),
    'C411_C411_KEY' => _constOrEmpty('C411_C411_KEY'),
    'C411_TR4KER_KEY' => _constOrEmpty('C411_TR4KER_KEY'),
    'C411_NOSTRADAMUS_KEY' => _constOrEmpty('C411_NOSTRADAMUS_KEY'),
    'C411_ASTRATORRENT_KEY' => _constOrEmpty('C411_ASTRATORRENT_KEY'),
    _ => null,
  };
}

String _constOrEmpty(String name) {
  final v = switch (name) {
    'C411_RPC_URL' => const String.fromEnvironment('C411_RPC_URL'),
    'C411_RPC_USER' => const String.fromEnvironment('C411_RPC_USER'),
    'C411_RPC_PASSWORD' => const String.fromEnvironment('C411_RPC_PASSWORD'),
    'C411_SESSION_COOKIE' =>
      const String.fromEnvironment('C411_SESSION_COOKIE'),
    'C411_TMDB_KEY' => const String.fromEnvironment('C411_TMDB_KEY'),
    'C411_JELLYFIN_URL' =>
      const String.fromEnvironment('C411_JELLYFIN_URL'),
    'C411_JELLYFIN_KEY' =>
      const String.fromEnvironment('C411_JELLYFIN_KEY'),
    'C411_FTP_HOST' => const String.fromEnvironment('C411_FTP_HOST'),
    'C411_FTP_PORT' => const String.fromEnvironment('C411_FTP_PORT'),
    'C411_FTP_USER' => const String.fromEnvironment('C411_FTP_USER'),
    'C411_FTP_PASSWORD' =>
      const String.fromEnvironment('C411_FTP_PASSWORD'),
    'C411_FTP_TLS' => const String.fromEnvironment('C411_FTP_TLS'),
    'C411_MEDIA_FOLDERS' =>
      const String.fromEnvironment('C411_MEDIA_FOLDERS'),
    'C411_C411_KEY' => const String.fromEnvironment('C411_C411_KEY'),
    'C411_TR4KER_KEY' => const String.fromEnvironment('C411_TR4KER_KEY'),
    'C411_NOSTRADAMUS_KEY' =>
      const String.fromEnvironment('C411_NOSTRADAMUS_KEY'),
    'C411_ASTRATORRENT_KEY' =>
      const String.fromEnvironment('C411_ASTRATORRENT_KEY'),
    _ => '',
  };
  return v;
}