import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSettings {
  const AppSettings({
    this.rpcUrl = '',
    this.rpcUser = '',
    this.rpcPassword = '',
    this.apiKeys = const {},
    this.sessionCookie = '',
    this.tmdbKey = '',
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

  bool get hasTransmission => rpcUrl.isNotEmpty;
  bool get hasTracker => apiKeys.values.any((k) => k.isNotEmpty);

  Map<String, dynamic> toJson() => {
        'rpcUrl': rpcUrl,
        'rpcUser': rpcUser,
        'rpcPassword': rpcPassword,
        'apiKeys': apiKeys,
        'sessionCookie': sessionCookie,
        'tmdbKey': tmdbKey,
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
    if (raw == null) return const AppSettings();
    return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(AppSettings settings) async {
    await _storage.write(key: _key, value: jsonEncode(settings.toJson()));
    state = AsyncData(settings);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
