import 'dart:io';

import 'package:c411_core/media_relay.dart';
import 'package:c411_web_player/config.dart';
import 'package:c411_web_player/library.dart';
import 'package:c411_web_player/server.dart';
import 'package:c411_web_player/transcode.dart';

const _usage = '''
Diffuse la vidéothèque de C411 Remote dans un navigateur.

  dart run bin/web_player.dart <réglages.json> [options]

<réglages.json> : le JSON de réglages de l'application (voir
personal.json.example) : accès FTP, clé TMDB, et une section « web »
facultative.

Options (prioritaires sur la section « web ») :
  --library <fichier>   vidéothèque : préférences de l'application
                        (défaut : ~/.local/share/fr.c411remote.c411_remote/
                        shared_preferences.json)
  --host <adresse>      adresse d'écoute (défaut : 127.0.0.1)
  --port <port>         port (défaut : 8411)
  --password <mot>      mot de passe (obligatoire hors de 127.0.0.1)
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stdout.write(_usage);
    exit(args.isEmpty ? 64 : 0);
  }
  final overrides = <String, String>{};
  for (var i = 1; i < args.length - 1; i += 2) {
    if (!args[i].startsWith('--')) {
      stderr.writeln('Option inattendue : ${args[i]}\n\n$_usage');
      exit(64);
    }
    overrides[args[i].substring(2)] = args[i + 1];
  }

  final WebConfig config;
  try {
    config = WebConfig.load(args.first, overrides: overrides);
  } on Object catch (e) {
    stderr.writeln('Réglages illisibles (${args.first}) : $e');
    exit(66);
  }
  if (config.public && config.password.isEmpty) {
    stderr.writeln('Refusé : écoute sur ${config.host} sans mot de passe. '
        'Ajoute --password, ou « password » dans la section « web ».');
    exit(64);
  }
  if (!File(config.library).existsSync()) {
    stderr.writeln('Vidéothèque introuvable : ${config.library} '
        '(--library pour en indiquer une autre)');
    exit(66);
  }

  final transcode = await available('ffmpeg') && await available('ffprobe');
  final catalog = CatalogSource(config.library);
  final count = catalog.current.titles.length;
  final server = WebPlayerServer(
    config,
    catalog: catalog,
    relay: MediaRelay(config.files),
    publicDir: '${File.fromUri(Platform.script).parent.parent.path}/public',
    fontsDir: '${File.fromUri(Platform.script).parent.parent.parent.path}/assets/fonts',
    canTranscode: transcode,
  );
  await server.start();

  stdout
    ..writeln('$count titres, lus dans ${config.library}')
    ..writeln(transcode
        ? 'ffmpeg trouvé : les fichiers que le navigateur ne lit pas sont convertis à la volée.'
        : 'ffmpeg absent : lecture directe seulement (MKV, H.265, DTS… illisibles).')
    ..writeln('Ouvre http://${config.host}:${config.port}/'
        '${config.password.isEmpty ? '' : '  (mot de passe demandé)'}');
}
