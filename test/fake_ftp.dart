import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Petit serveur FTP pour les tests : fichiers en mémoire, mode passif
/// (`EPSV`), TLS explicite facultatif (certificat de test autosigné).
class FakeFtpServer {
  FakeFtpServer._(this._server, this.files, this.tls);

  final ServerSocket _server;

  /// Chemin absolu → contenu. Les dossiers se déduisent des chemins.
  final Map<String, List<int>> files;
  final bool tls;

  /// Commandes reçues, toutes connexions confondues.
  final commands = <String>[];

  /// `MLSD` refusé : le client doit se rabattre sur `LIST`.
  bool noMlsd = false;

  int get port => _server.port;

  static SecurityContext get context => SecurityContext()
    ..useCertificateChain('test/fixtures/ftp_test_cert.pem')
    ..usePrivateKey('test/fixtures/ftp_test_key.pem');

  static Future<FakeFtpServer> start(Map<String, List<int>> files,
      {bool tls = false}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeFtpServer._(server, files, tls);
    server.listen((s) => _Session(fake, s).run());
    return fake;
  }

  Future<void> close() => _server.close();

  Set<String> dirs() => {
        for (final path in files.keys)
          for (var i = path.indexOf('/', 1); i > 0; i = path.indexOf('/', i + 1))
            path.substring(0, i),
      };
}

class _Session {
  _Session(this.server, this.socket);
  final FakeFtpServer server;
  Socket socket;
  ServerSocket? passive;
  var offset = 0;
  var protected = false;

  void reply(String text) => socket.write('$text\r\n');

  Future<Socket> data() async {
    final s = await passive!.first;
    await passive!.close();
    passive = null;
    return protected ? SecureSocket.secureServer(s, FakeFtpServer.context) : s;
  }

  Future<void> run() async {
    reply('220-Bienvenue');
    reply('220 Serveur de test');
    try {
      while (true) {
        final lines = StreamIterator(socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()));
        var secure = false;
        while (await lines.moveNext()) {
          final line = lines.current;
          server.commands.add(line);
          final space = line.indexOf(' ');
          final verb = (space < 0 ? line : line.substring(0, space)).toUpperCase();
          final arg = space < 0 ? '' : line.substring(space + 1);
          if (verb == 'AUTH' && server.tls) {
            reply('234 TLS');
            await socket.flush();
            secure = true;
            break;
          }
          if (!await handle(verb, arg)) return;
          await socket.flush();
        }
        if (!secure) return;
        socket = await SecureSocket.secureServer(socket, FakeFtpServer.context);
      }
    } on Object {
      // Client parti.
    } finally {
      socket.destroy();
    }
  }

  /// Une commande ; false pour terminer la session.
  Future<bool> handle(String verb, String arg) async {
    final files = server.files;
    switch (verb) {
      case 'USER':
        reply('331 Mot de passe ?');
      case 'PASS':
        reply(arg == 'secret' ? '230 OK' : '530 Refusé');
      case 'PBSZ':
        reply('200 PBSZ=0');
      case 'PROT':
        protected = arg == 'P';
        reply('200 Protection $arg');
      case 'TYPE':
        reply('200 Binaire');
      case 'OPTS':
        reply('200 UTF-8');
      case 'EPSV':
        passive = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        reply('229 Passif (|||${passive!.port}|)');
      case 'SIZE':
        final f = files[arg];
        reply(f == null ? '550 Absent' : '213 ${f.length}');
      case 'REST':
        offset = int.parse(arg);
        reply('350 Reprise à $arg');
      case 'MLSD' || 'LIST':
        if (verb == 'MLSD' && server.noMlsd) {
          reply('500 Inconnu');
          return true;
        }
        final path = arg.replaceFirst(RegExp(r'^-a\s*'), '');
        final dir = path == '/' ? '' : path;
        bool child(String p) =>
            p.startsWith('$dir/') && !p.substring(dir.length + 1).contains('/');
        final names = <String, int?>{
          for (final d in server.dirs())
            if (child(d)) d.substring(dir.length + 1): null,
          for (final MapEntry(:key, :value) in files.entries)
            if (child(key)) key.substring(dir.length + 1): value.length,
        };
        reply('150 Liste');
        await socket.flush();
        final s = await data();
        for (final MapEntry(key: name, value: size) in names.entries) {
          s.write(verb == 'MLSD'
              ? 'type=${size == null ? 'dir' : 'file'};size=${size ?? 4096};modify=20261017120000; $name\r\n'
              : '${size == null ? 'd' : '-'}rw-r--r-- 1 u g ${size ?? 4096} Oct 17 12:00 $name\r\n');
        }
        await s.flush();
        await s.close();
        reply('226 Fini');
      case 'RETR':
        final f = files[arg];
        if (f == null) {
          reply('550 Absent');
          return true;
        }
        reply('150 Envoi');
        await socket.flush();
        final s = await data();
        try {
          s.add(f.sublist(offset));
          await s.flush();
          await s.close();
          reply('226 Fini');
        } on Object {
          reply('426 Interrompu');
        }
        offset = 0;
      case 'QUIT':
        reply('221 Au revoir');
        await socket.flush();
        return false;
      default:
        reply('502 Non pris en charge');
    }
    return true;
  }
}
