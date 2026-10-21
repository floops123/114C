import 'dart:io';

import 'package:c411_core/media_relay.dart';
import 'package:c411_web_music/config.dart';
import 'package:c411_web_music/musicbrainz.dart';
import 'package:c411_web_music/scanner.dart';
import 'package:c411_web_music/server.dart';
import 'package:c411_web_music/service.dart';

const _usage = '''
Diffuse la musique du serveur de C411 Remote dans un navigateur, avec les
fiches et pochettes de MusicBrainz.

  dart run bin/web_music.dart <réglages.json> [options]

<réglages.json> : le JSON de réglages de l'application (voir
personal.json.example) : accès FTP, Transmission, dossiers, et une section
« music » facultative.

Options (prioritaires sur la section « music ») :
  --folder <dossier>    dossier du FTP à parcourir, en plus des autres
  --state <fichier>     discothèque (défaut : ~/.local/share/c411_music/
                        library.json)
  --library <fichier>   préférences de l'application, pour la
                        correspondance des chemins Transmission → FTP
  --host <adresse>      adresse d'écoute (défaut : 127.0.0.1)
  --port <port>         port (défaut : 8412)
  --password <mot>      mot de passe (obligatoire hors de 127.0.0.1)
  --scan-every <min>    minutes entre deux parcours (défaut : 180 ; 0 :
                        au démarrage et sur demande)
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stdout.write(_usage);
    exit(args.isEmpty ? 64 : 0);
  }
  final overrides = <String, String>{};
  for (var i = 1; i < args.length; i += 2) {
    if (!args[i].startsWith('--') || i + 1 >= args.length) {
      stderr.writeln('Option inattendue : ${args[i]}\n\n$_usage');
      exit(64);
    }
    overrides[args[i].substring(2)] = args[i + 1];
  }

  final MusicConfig config;
  try {
    config = MusicConfig.load(args.first, overrides: overrides);
  } on Object catch (e) {
    stderr.writeln('Réglages illisibles (${args.first}) : $e');
    exit(66);
  }
  if (config.public && config.password.isEmpty) {
    stderr.writeln('Refusé : écoute sur ${config.host} sans mot de passe. '
        'Ajoute --password, ou « password » dans la section « music ».');
    exit(64);
  }
  if (!config.hasTransmission && config.folders.isEmpty) {
    stderr.writeln('Rien à parcourir : renseigne rpcUrl (Transmission) ou des '
        'dossiers (« folders » de la section « music », ou --folder).');
    exit(64);
  }

  final transcode = await _available('ffmpeg') && await _available('ffprobe');
  final service = MusicService(
    statePath: config.state,
    scanner: Scanner(config),
    musicBrainz: MusicBrainz(contact: config.contact),
    scanEvery: config.scanEvery,
  );
  final root = File.fromUri(Platform.script).parent.parent;
  final server = MusicServer(
    config,
    service: service,
    relay: MediaRelay(config.ftp),
    publicDir: '${root.path}/public',
    fontsDir: '${root.parent.path}/assets/fonts',
    canTranscode: transcode,
  );
  await server.start();
  service.start();

  stdout
    ..writeln('${service.catalog.albums.length} albums, lus dans ${config.state} ; '
        'parcours en cours (${[
      if (config.hasTransmission) 'torrents terminés',
      ...config.folders,
    ].join(', ')})')
    ..writeln(transcode
        ? 'ffmpeg trouvé : WMA, APE, ALAC… sont convertis à la volée.'
        : 'ffmpeg absent : lecture directe seulement (MP3, FLAC, AAC, Ogg, WAV).')
    ..writeln('Ouvre http://${config.host}:${config.port}/'
        '${config.password.isEmpty ? '' : '  (mot de passe demandé)'}');
}

Future<bool> _available(String command) async {
  try {
    final r = await Process.run(command, ['-version']);
    return r.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
