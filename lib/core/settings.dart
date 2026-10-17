import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSettings {
  const AppSettings({
    this.rpcUrl = '',
    this.rpcUser = '',
    this.rpcPassword = '',
    this.apiKey = '',
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        rpcUrl: json['rpcUrl'] as String? ?? '',
        rpcUser: json['rpcUser'] as String? ?? '',
        rpcPassword: json['rpcPassword'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
      );

  final String rpcUrl;
  final String rpcUser;
  final String rpcPassword;
  final String apiKey;

  bool get hasTransmission => rpcUrl.isNotEmpty;
  bool get hasTracker => apiKey.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'rpcUrl': rpcUrl,
        'rpcUser': rpcUser,
        'rpcPassword': rpcPassword,
        'apiKey': apiKey,
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
