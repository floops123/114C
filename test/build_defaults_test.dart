import 'dart:convert';

import 'package:c411_remote/build_defaults.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aucune source : BuildDefaults vide', () async {
    final d = await BuildDefaults.load();
    expect(d.hasAny, isFalse);
    expect(d.values, isEmpty);
    // Tous les champs à leur valeur par défaut.
    final s = d.toAppSettings();
    expect(s.rpcUrl, isEmpty);
    expect(s.apiKeys, isEmpty);
    expect(s.mediaFolders, isEmpty);
    expect(s.ftpTls, isTrue);
    expect(s.ftpPort, 21);
  });

  test('depuis une Map (simule le contenu d\'un JSON)', () {
    // On vérifie surtout que `toAppSettings` produit un objet cohérent à
    // partir d'un JSON parsé. `BuildDefaults.fromMap` est réservé aux
    // tests ; en production, on passe par `load()`.
    final json = {
      'rpcUrl': 'http://build',
      'rpcUser': 'u',
      'rpcPassword': 'p',
      'apiKeys': {'c411': 'k1', 'tr4ker': 'k2'},
      'sessionCookie': 'connect_sid=abc',
      'tmdbKey': 'tmdb',
      'jellyfinUrl': 'http://jellyfin',
      'jellyfinKey': 'jk',
      'ftpHost': 'app.local',
      'ftpPort': 2121,
      'ftpUser': 'ftpuser',
      'ftpPassword': 'ftppwd',
      'ftpTls': false,
      'mediaFolders': ['/films', '/series'],
    };
    final settings = AppSettings.fromJson(Map<String, dynamic>.from(json));
    expect(settings.rpcUrl, 'http://build');
    expect(settings.rpcPassword, 'p');
    expect(settings.apiKeys['c411'], 'k1');
    expect(settings.apiKeys['tr4ker'], 'k2');
    expect(settings.ftpPort, 2121);
    expect(settings.ftpTls, isFalse);
    expect(settings.mediaFolders, ['/films', '/series']);
  });

  test('les variables reconnues sont listées', () {
    expect(BuildDefaults.allVariables, contains('C411_RPC_URL'));
    expect(BuildDefaults.allVariables, contains('C411_FTP_HOST'));
    expect(BuildDefaults.allVariables, contains('C411_C411_KEY'));
    expect(BuildDefaults.allVariables, contains('C411_ASTRATORRENT_KEY'));
    // JSON circulaire (sérialisation/désérialisation cohérente).
    final sample = AppSettings(
      rpcUrl: 'http://x',
      apiKeys: const {'c411': 'k'},
      ftpTls: false,
      mediaFolders: const ['/a'],
    );
    final round = AppSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(sample.toJson()))));
    expect(round.rpcUrl, 'http://x');
    expect(round.apiKeys['c411'], 'k');
    expect(round.ftpTls, isFalse);
    expect(round.mediaFolders, ['/a']);
  });
}