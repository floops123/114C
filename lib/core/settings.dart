import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../build_defaults.dart';

class AppSettings {
  const AppSettings({
    this.rpcUrl = '',
    this.rpcUser = '',
    this.rpcPassword = '',
    this.apiKeys = const {},
    this.sessionCookie = '',
    this.tmdbKey = '',
    this.jellyfinUrl = '',
    this.jellyfinKey = '',
    this.ftpHost = '',
    this.ftpPort = 21,
    this.ftpUser = '',
    this.ftpPassword = '',
    this.ftpTls = true,
    this.mediaFolders = const [],
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        rpcUrl: json['rpcUrl'] as String? ?? '',
        rpcUser: json['rpcUser'] as String? ?? '',
        rpcPassword: json['rpcPassword'] as String? ?? '',
        apiKeys: {
          // Ancien format : une seule clé, celle de C411.
          if (json['apiKey'] is String) 'c411': json['apiKey'] as String,
          ...?(json['apiKeys'] as Map?)?.cast<String, String>(),
        },
        sessionCookie: json['sessionCookie'] as String? ?? '',
        tmdbKey: json['tmdbKey'] as String? ?? '',
        jellyfinUrl: json['jellyfinUrl'] as String? ?? '',
        jellyfinKey: json['jellyfinKey'] as String? ?? '',
        ftpHost: json['ftpHost'] as String? ?? '',
        ftpPort: (json['ftpPort'] as num?)?.toInt() ?? 21,
        ftpUser: json['ftpUser'] as String? ?? '',
        ftpPassword: json['ftpPassword'] as String? ?? '',
        ftpTls: json['ftpTls'] as bool? ?? true,
        mediaFolders: (json['mediaFolders'] as List? ?? const []).cast<String>(),
      );

  final String rpcUrl;
  final String rpcUser;
  final String rpcPassword;

  /// Clé API par tracker, indexée par `Tracker.name`.
  final Map<String, String> apiKeys;

  /// Cookies de session du site C411 (en-tête Cookie copié du navigateur),
  /// exigés par le WebSocket des notifications.
  final String sessionCookie;

  /// Clé d'API ou jeton de lecture TMDB (liste de souhaits).
  final String tmdbKey;

  /// Serveur Jellyfin (lecture des films déjà présents) et sa clé d'API.
  final String jellyfinUrl;
  final String jellyfinKey;

  /// Accès FTP aux fichiers du serveur (Appbox : Pure-FTPd en TLS explicite),
  /// pour notre propre base de films et séries et leur lecture directe.
  final String ftpHost;
  final int ftpPort;
  final String ftpUser;
  final String ftpPassword;
  final bool ftpTls;

  /// Dossiers du FTP à parcourir, en plus des torrents terminés.
  final List<String> mediaFolders;

  bool get hasFtp => ftpHost.isNotEmpty && ftpUser.isNotEmpty;

  bool get hasTransmission => rpcUrl.isNotEmpty;
  bool get hasTracker => apiKeys.values.any((k) => k.isNotEmpty);

  Map<String, dynamic> toJson() => {
        'rpcUrl': rpcUrl,
        'rpcUser': rpcUser,
        'rpcPassword': rpcPassword,
        'apiKeys': apiKeys,
        'sessionCookie': sessionCookie,
        'tmdbKey': tmdbKey,
        'jellyfinUrl': jellyfinUrl,
        'jellyfinKey': jellyfinKey,
        'ftpHost': ftpHost,
        'ftpPort': ftpPort,
        'ftpUser': ftpUser,
        'ftpPassword': ftpPassword,
        'ftpTls': ftpTls,
        'mediaFolders': mediaFolders,
      };
}

/// Les identifiants sont rangés dans le trousseau du système
/// (libsecret sous Linux, Keychain sous iOS/macOS, Keystore sous Android).
class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _storage = FlutterSecureStorage();
  static const _key = 'settings';

  @override
  Future<AppSettings> build() async {
    final raw = await _storage.read(key: _key);
    if (raw != null) {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    // Premier lancement (trousseau vide) : si la variante a été compilée
    // avec des réglages préenregistrés (--dart-define, voir
    // `BuildDefaults`), on les écrit dans le trousseau et on les renvoie.
    // Sinon, l'application ouvre les Réglages vide, comme avant.
    const defaults = BuildDefaults();
    if (defaults.hasAny) {
      final settings = defaults.toAppSettings();
      await _storage.write(key: _key, value: jsonEncode(settings.toJson()));
      return settings;
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    await _storage.write(key: _key, value: jsonEncode(settings.toJson()));
    state = AsyncData(settings);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
