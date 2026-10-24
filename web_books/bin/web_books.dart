import 'dart:io';

import 'package:c411_core/media_relay.dart';
import 'package:c411_core/votes.dart';
import 'package:c411_web_books/config.dart';
import 'package:c411_web_books/content.dart';
import 'package:c411_web_books/online.dart';
import 'package:c411_web_books/server.dart';
import 'package:c411_web_books/service.dart';

const _usage = '''
Diffuse les livres, BD, mangas et magazines du serveur de C411 Remote dans
un navigateur, avec une liseuse.

  dart run bin/web_books.dart <réglages.json> [options]

<réglages.json> : le JSON de réglages de l'application (voir
personal.json.example) : accès FTP, et une section « books » facultative.
Les livres sont ceux que l'application relève pendant le parcours de sa
vidéothèque (torrents terminés et dossiers à parcourir).

Options (prioritaires sur la section « books ») :
  --library <fichier>   base de l'application : ses préférences (défaut :
                        ~/.local/share/fr.c411remote.c411_remote/
                        shared_preferences.json)
  --state <fichier>     ce que le serveur sait des livres (défaut :
                        ~/.local/share/c411_books/books.json) ; couvertures
                        et copies locales dans le même dossier
  --google-books-key <clé>  Google Books en plus d'Open Library
  --hardcover-key <jeton>   Hardcover en plus d'Open Library
  --cache-gb <Go>       place des copies locales (PDF, CBR ; défaut : 2)
  --host <adresse>      adresse d'écoute (défaut : 127.0.0.1)
  --port <port>         port (défaut : 8413)
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

  final BooksConfig config;
  try {
    config = BooksConfig.load(args.first, overrides: overrides);
  } on Object catch (e) {
    stderr.writeln('Réglages illisibles (${args.first}) : $e');
    exit(66);
  }
  if (config.public && config.password.isEmpty) {
    stderr.writeln('Refusé : écoute sur ${config.host} sans mot de passe. '
        'Ajoute --password, ou « password » dans la section « books ».');
    exit(64);
  }
  if (!File(config.library).existsSync()) {
    stderr.writeln('Base de l’application introuvable : ${config.library} '
        '(--library pour en indiquer une autre)');
    exit(66);
  }

  final tools = await Tools.detect();
  final relay = MediaRelay(config.files);
  final service = BooksService(
    appLibrary: config.library,
    statePath: config.state,
    content: Content(
      urlFor: relay.urlFor,
      cacheDir: config.cacheDir,
      tools: tools,
      cacheBytes: config.cacheBytes,
    ),
    online: OnlineBooks(
      contact: config.contact,
      googleKey: config.googleBooksKey,
      hardcoverKey: config.hardcoverKey,
      hardcoverQuotaFile: '${config.cacheDir}/hardcover-quota.json',
    ),
  );
  final root = File.fromUri(Platform.script).parent.parent;
  final server = BooksServer(
    config,
    service: service,
    publicDir: '${root.path}/public',
    fontsDir: '${root.parent.path}/assets/fonts',
    votes: Votes('${File(config.state).parent.path}/votes.json'),
  );
  await server.start();
  service.start();

  final count = service.catalog.books.length;
  stdout
    ..writeln('$count livres, lus dans ${config.library}'
        '${count == 0 ? ' (lance un parcours de la vidéothèque dans l’application)' : ''}')
    ..writeln('Fiches : ${[
      if (config.googleBooksKey.isNotEmpty) 'Google Books',
      if (config.hardcoverKey.isNotEmpty) 'Hardcover',
      'Open Library',
      'BnF',
    ].join(' puis ')}, complétées par Wikidata et Wikipédia')
    ..writeln([
      tools.pdftoppm ? 'pdftoppm : couvertures des PDF' : 'pdftoppm absent : PDF sans couverture',
      tools.sevenZip ? '7z : BD en CBR/CB7' : '7z absent : CBR et CB7 illisibles',
      tools.ffmpeg ? 'ffmpeg : couvertures réduites' : 'ffmpeg absent : couvertures en taille réelle',
    ].join(' ; '))
    ..writeln('Ouvre http://${config.host}:${config.port}/'
        '${config.password.isEmpty ? '' : '  (mot de passe demandé)'}');
}
