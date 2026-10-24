import 'dart:io';

import 'package:c411_core/media_relay.dart';
import 'package:c411_core/votes.dart';
import 'package:c411_web_music/config.dart';
import 'package:c411_web_music/discogs.dart';
import 'package:c411_web_music/musicbrainz.dart';
import 'package:c411_web_music/server.dart';
import 'package:c411_web_music/service.dart';

const _usage = '''
Diffuse la musique du serveur de C411 Remote dans un navigateur, avec les
fiches et pochettes de MusicBrainz.

  dart run bin/web_music.dart <réglages.json> [options]

<réglages.json> : le JSON de réglages de l'application (voir
personal.json.example) : accès FTP, et une section « music » facultative.
La musique est celle que l'application relève pendant le parcours de sa
vidéothèque (torrents terminés et dossiers à parcourir).

Options (prioritaires sur la section « music ») :
  --library <fichier>   base de l'application : ses préférences (défaut :
                        ~/.local/share/fr.c411remote.c411_remote/
                        shared_preferences.json)
  --state <fichier>     fiches MusicBrainz (défaut : ~/.local/share/
                        c411_music/library.json)
  --discogs-token <jeton>  Discogs en plus de MusicBrainz
  --host <adresse>      adresse d'écoute (défaut : 127.0.0.1)
  --port <port>         port (défaut : 8412)
  --password <mot>      mot de passe (obligatoire hors de 127.0.0.1)
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
  if (!File(config.library).existsSync()) {
    stderr.writeln('Base de l’application introuvable : ${config.library} '
        '(--library pour en indiquer une autre)');
    exit(66);
  }

  final transcode = await _available('ffmpeg') && await _available('ffprobe');
  final service = MusicService(
    appLibrary: config.library,
    statePath: config.state,
    musicBrainz: MusicBrainz(contact: config.contact),
    discogs: config.discogsToken.isEmpty ? null : Discogs(contact: config.contact, token: config.discogsToken),
  );
  final root = File.fromUri(Platform.script).parent.parent;
  final server = MusicServer(
    config,
    service: service,
    relay: MediaRelay(config.files),
    publicDir: '${root.path}/public',
    fontsDir: '${root.parent.path}/assets/fonts',
    canTranscode: transcode,
    votes: Votes('${File(config.state).parent.path}/votes.json'),
  );
  await server.start();
  service.start();

  final albums = service.catalog.albums.length;
  stdout
    ..writeln('$albums albums, lus dans ${config.library}'
        '${albums == 0 ? ' (lance un parcours de la vidéothèque dans l’application)' : ''}')
    ..writeln(transcode
        ? 'ffmpeg trouvé : WMA, APE, ALAC… sont convertis à la volée.'
        : 'ffmpeg absent : lecture directe seulement (MP3, FLAC, AAC, Ogg, WAV).')
    ..writeln('Fiches : MusicBrainz${config.discogsToken.isEmpty ? '' : ', puis Discogs (albums inconnus, pochettes et styles manquants)'}')
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
