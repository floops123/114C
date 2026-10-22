import 'dart:convert';

import 'package:c411_remote/api/tracker.dart';
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
      filesProtocol: 'webdav',
      webdavUrl: 'https://dav.x/',
      webdavUser: 'moi',
      webdavPassword: 's',
      mediaFolders: ['/a'],
    );
    final round = AppSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(s.toJson()))));
    expect(round.rpcUrl, 'http://x');
    expect(round.apiKeys['c411'], 'k');
    expect(round.ftpTls, isFalse);
    expect(round.mediaFolders, ['/a']);
    expect((round.useWebDav, round.webdavUrl, round.webdavUser, round.webdavPassword),
        (true, 'https://dav.x/', 'moi', 's'));
    expect(round.hasFiles, isTrue, reason: 'WebDAV suffit, sans FTP');
    // Sans filesProtocol (réglages écrits à la main) : déduit.
    expect(AppSettings.fromJson({'webdavUrl': 'https://d/'}).filesProtocol, 'webdav');
    expect(AppSettings.fromJson({'ftpHost': 'h', 'webdavUrl': 'https://d/'}).filesProtocol, 'ftp');
    expect(AppSettings.fromJson({'localRoot': '/mnt/x'}).filesProtocol, 'local');
    // Ancienne variante compilée : AstraTorrent rangé sous son nom complet.
    expect(AppSettings.fromJson({'apiKeys': {'astratorrent': 'pk'}}).apiKeys, {'astra': 'pk'});
  });

  test('allVariables : liste non vide et stables', () {
    expect(BuildDefaults.allVariables, contains('C411_RPC_URL'));
    expect(BuildDefaults.allVariables, contains('C411_FTP_HOST'));
    expect(BuildDefaults.allVariables, contains('C411_C411_KEY'));
    expect(BuildDefaults.allVariables, contains('C411_ASTRATORRENT_KEY'));
    // À chaque nouveau champ ajouté à AppSettings, il faut aussi ajouter
    // la variable correspondante ici ET dans `BuildDefaults.toAppSettings`.
    expect(BuildDefaults.allVariables, contains('C411_WEBDAV_URL'));
    expect(BuildDefaults.allVariables.length, 23);
    // Chaque tracker a sa variable (build_personal produit C411_<TRACKER>_KEY).
    for (final t in Tracker.values) {
      final name = t == Tracker.astra ? 'ASTRATORRENT' : t.name.toUpperCase();
      expect(BuildDefaults.allVariables, contains('C411_${name}_KEY'));
    }
  });
}