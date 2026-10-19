import 'dart:io';

import 'package:c411_remote/build_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/build_personal.dart' as tool;

void main() {
  test('JSON vide → aucun flag', () {
    expect(tool.personalJsonToFlags(const {}), isEmpty);
  });

  test('JSON rempli : tous les champs scalaires', () {
    final flags = tool.personalJsonToFlags({
      'rpcUrl': 'http://seedbox:9091/transmission/rpc',
      'rpcUser': 'admin',
      'rpcPassword': 'secret',
      'sessionCookie': 'connect_sid=abc',
      'tmdbKey': 'tmdb',
      'jellyfinUrl': 'http://jellyfin',
      'jellyfinKey': 'jk',
      'ftpHost': 'app.local',
      'ftpPort': 2121,
      'ftpUser': 'ftpuser',
      'ftpPassword': 'ftppwd',
      'ftpTls': false,
    });
    expect(flags, contains('--dart-define=C411_RPC_URL=http://seedbox:9091/transmission/rpc'));
    expect(flags, contains('--dart-define=C411_RPC_USER=admin'));
    expect(flags, contains('--dart-define=C411_RPC_PASSWORD=secret'));
    expect(flags, contains('--dart-define=C411_SESSION_COOKIE=connect_sid=abc'));
    expect(flags, contains('--dart-define=C411_TMDB_KEY=tmdb'));
    expect(flags, contains('--dart-define=C411_JELLYFIN_URL=http://jellyfin'));
    expect(flags, contains('--dart-define=C411_JELLYFIN_KEY=jk'));
    expect(flags, contains('--dart-define=C411_FTP_HOST=app.local'));
    expect(flags, contains('--dart-define=C411_FTP_PORT=2121'));
    expect(flags, contains('--dart-define=C411_FTP_USER=ftpuser'));
    expect(flags, contains('--dart-define=C411_FTP_PASSWORD=ftppwd'));
    expect(flags, contains('--dart-define=C411_FTP_TLS=false'));
    expect(flags, hasLength(12));
  });

  test('mediaFolders : liste → CSV', () {
    final flags = tool.personalJsonToFlags({
      'mediaFolders': ['/torrents', '/data'],
    });
    expect(flags, contains('--dart-define=C411_MEDIA_FOLDERS=/torrents,/data'));
  });

  test('apiKeys : map → flags par tracker', () {
    final flags = tool.personalJsonToFlags({
      'apiKeys': {
        'c411': 'k1',
        'tr4ker': 'k2',
        'nostradamus': 'k3',
        'astratorrent': 'passkey',
      },
    });
    expect(flags, contains('--dart-define=C411_C411_KEY=k1'));
    expect(flags, contains('--dart-define=C411_TR4KER_KEY=k2'));
    expect(flags, contains('--dart-define=C411_NOSTRADAMUS_KEY=k3'));
    expect(flags, contains('--dart-define=C411_ASTRATORRENT_KEY=passkey'));
  });

  test('champs vides ou nuls : ignorés', () {
    final flags = tool.personalJsonToFlags({
      'rpcUrl': '',
      'rpcUser': null,
      'apiKeys': {'c411': ''},
    });
    expect(flags, isEmpty);
  });

  test('loadJson : fichier manquant → exception', () {
    expect(() => tool.loadJson('/nonexistent.json'),
        throwsA(isA<FormatException>()));
  });

  test('loadJson : JSON invalide → exception', () {
    final tmp = Directory.systemTemp.createTempSync();
    final f = File('${tmp.path}/bad.json');
    f.writeAsStringSync('{not json');
    addTearDown(() {
      f.deleteSync();
      tmp.deleteSync();
    });
    expect(() => tool.loadJson(f.path),
        throwsA(isA<FormatException>()));
  });

  test('loadJson : racine non-objet → exception', () {
    final tmp = Directory.systemTemp.createTempSync();
    final f = File('${tmp.path}/list.json');
    f.writeAsStringSync('[1, 2, 3]');
    addTearDown(() {
      f.deleteSync();
      tmp.deleteSync();
    });
    expect(() => tool.loadJson(f.path),
        throwsA(isA<FormatException>()));
  });

  test('round-trip : JSON → flags → AppSettings équivalent', () {
    final json = {
      'rpcUrl': 'http://seedbox',
      'rpcUser': 'u',
      'rpcPassword': 'p',
      'apiKeys': {'c411': 'k', 'tr4ker': 'k2'},
      'mediaFolders': ['/films', '/series'],
      'ftpTls': false,
      'ftpPort': 22,
    };
    final flags = tool.personalJsonToFlags(json);
    // Vérifie qu'on retrouve tous les flags attendus.
    expect(flags, contains('--dart-define=C411_RPC_URL=http://seedbox'));
    expect(flags, contains('--dart-define=C411_FTP_PORT=22'));
    expect(flags, contains('--dart-define=C411_FTP_TLS=false'));
    expect(flags, contains('--dart-define=C411_MEDIA_FOLDERS=/films,/series'));
    expect(flags, contains('--dart-define=C411_C411_KEY=k'));
    expect(flags, contains('--dart-define=C411_TR4KER_KEY=k2'));
  });

  test('BuildDefaults.allVariables : connues', () {
    expect(BuildDefaults.allVariables, contains('C411_RPC_URL'));
    expect(BuildDefaults.allVariables, contains('C411_C411_KEY'));
    expect(BuildDefaults.allVariables, contains('C411_ASTRATORRENT_KEY'));
  });
}