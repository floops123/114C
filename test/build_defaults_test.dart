import 'dart:convert';

import 'package:c411_remote/build_defaults.dart';
import 'package:c411_remote/core/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aucune variable : BuildDefaults vide', () {
    const d = BuildDefaults();
    expect(d.hasAny, isFalse);
    final s = d.toAppSettings();
    expect(s.rpcUrl, isEmpty);
    expect(s.apiKeys, isEmpty);
    expect(s.mediaFolders, isEmpty);
    expect(s.ftpTls, isTrue);
    expect(s.ftpPort, 21);
  });

  test('round-trip JSON : AppSettings.toJson → fromJson', () {
    final s = const AppSettings(
      rpcUrl: 'http://x',
      apiKeys: {'c411': 'k'},
      ftpTls: false,
      mediaFolders: ['/a'],
    );
    final round = AppSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(s.toJson()))));
    expect(round.rpcUrl, 'http://x');
    expect(round.apiKeys['c411'], 'k');
    expect(round.ftpTls, isFalse);
    expect(round.mediaFolders, ['/a']);
  });

  test('allVariables : liste non vide et stables', () {
    expect(BuildDefaults.allVariables, contains('C411_RPC_URL'));
    expect(BuildDefaults.allVariables, contains('C411_FTP_HOST'));
    expect(BuildDefaults.allVariables, contains('C411_C411_KEY'));
    expect(BuildDefaults.allVariables, contains('C411_ASTRATORRENT_KEY'));
    // À chaque nouveau champ ajouté à AppSettings, il faut aussi ajouter
    // la variable correspondante ici ET dans `BuildDefaults.toAppSettings`.
    expect(BuildDefaults.allVariables.length, 17);
  });
}