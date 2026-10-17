import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Accès aux fichiers du serveur (Appbox : application Pure-FTPd, FTP avec
/// TLS explicite, `ftp.<identifiant>.appbox.co`).
class FtpConfig {
  const FtpConfig({
    required this.host,
    this.port = 21,
    required this.user,
    required this.password,
    this.tls = true,
  });

  final String host;
  final int port;
  final String user;
  final String password;

  /// TLS explicite (`AUTH TLS`, puis `PROT P` pour les données).
  final bool tls;

  bool get isEmpty => host.isEmpty || user.isEmpty;
}

class FtpException implements Exception {
  const FtpException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Élément d'un dossier (`MLSD`, sinon `LIST`).
class FtpEntry {
  const FtpEntry(this.name, {required this.isDir, this.size = 0});
  final String name;
  final bool isDir;
  final int size;
}

/// Réponse FTP : code et texte (lignes jointes).
typedef FtpReply = ({int code, String text});

/// Client FTP minimal : une connexion de contrôle, des connexions de données
/// passives (`EPSV`, sinon `PASV`), en TLS si demandé. Juste ce qu'il faut
/// pour lister des dossiers et lire un fichier à partir d'une position.
class FtpClient {
  FtpClient(this.config);
  final FtpConfig config;

  Socket? _control;
  final _lines = <String>[];
  final _waiting = <Completer<void>>[];
  String _partial = '';
  bool _closed = false;

  static const _timeout = Duration(seconds: 15);

  Future<void> connect() async {
    try {
      final socket = await Socket.connect(config.host, config.port,
          timeout: _timeout);
      _attach(socket);
      await _expect([220]);
      if (config.tls) {
        await _command('AUTH TLS', [234]);
        // On n'écoute plus la socket en clair : elle passe sous TLS.
        _subscription?.pause();
        final secure = await SecureSocket.secure(socket,
            host: config.host, onBadCertificate: (_) => true);
        _attach(secure);
      }
      final user = await _command('USER ${config.user}', [230, 331]);
      if (user.code == 331) await _command('PASS ${config.password}', [230]);
      if (config.tls) {
        await _command('PBSZ 0', [200]);
        await _command('PROT P', [200]);
      }
      await _command('TYPE I', [200]);
      // Facultatif : certains serveurs répondent 500, sans gravité.
      await _send('OPTS UTF8 ON');
      await _reply();
    } on SocketException catch (e) {
      throw FtpException('Serveur FTP injoignable : ${e.message}');
    } on HandshakeException catch (e) {
      throw FtpException('TLS refusé par le serveur FTP : ${e.message}');
    } on TimeoutException {
      throw const FtpException('Le serveur FTP ne répond pas');
    }
  }

  StreamSubscription<List<int>>? _subscription;

  void _attach(Socket socket) {
    _control = socket;
    _subscription = socket.listen((data) {
      _partial += utf8.decode(data, allowMalformed: true);
      while (true) {
        final i = _partial.indexOf('\n');
        if (i < 0) break;
        _lines.add(_partial.substring(0, i).replaceAll('\r', ''));
        _partial = _partial.substring(i + 1);
      }
      _wake();
    }, onDone: () {
      _closed = true;
      _wake();
    }, onError: (_) {
      _closed = true;
      _wake();
    });
  }

  void _wake() {
    for (final c in _waiting) {
      if (!c.isCompleted) c.complete();
    }
    _waiting.clear();
  }

  Future<String> _line() async {
    while (_lines.isEmpty) {
      if (_closed) throw const FtpException('Connexion FTP fermée');
      final c = Completer<void>();
      _waiting.add(c);
      await c.future.timeout(_timeout,
          onTimeout: () => throw const FtpException('Le serveur FTP ne répond pas'));
    }
    return _lines.removeAt(0);
  }

  /// Réponse complète, lignes multiples comprises (`123-…` jusqu'à `123 …`).
  Future<FtpReply> _reply() async {
    final first = await _line();
    final code = int.tryParse(first.length >= 3 ? first.substring(0, 3) : '') ?? 0;
    final text = StringBuffer(first.length > 4 ? first.substring(4) : '');
    if (first.length > 3 && first[3] == '-') {
      while (true) {
        final line = await _line();
        if (line.startsWith('$code ')) {
          text.write('\n${line.substring(4)}');
          break;
        }
        text.write('\n$line');
      }
    }
    return (code: code, text: text.toString());
  }

  Future<void> _send(String command) async {
    final socket = _control;
    if (socket == null) throw const FtpException('Pas connecté au FTP');
    socket.write('$command\r\n');
    await socket.flush();
  }

  Future<FtpReply> _expect(List<int> codes) async {
    final r = await _reply();
    if (!codes.contains(r.code)) {
      throw FtpException(r.code == 530
          ? 'Identifiants FTP refusés'
          : 'Réponse FTP inattendue : ${r.code} ${r.text}');
    }
    return r;
  }

  Future<FtpReply> _command(String command, List<int> codes) async {
    await _send(command);
    return _expect(codes);
  }

  /// Connexion de données passive : `EPSV`, sinon `PASV`.
  Future<Socket> _data() async {
    int? port;
    await _send('EPSV');
    var r = await _reply();
    if (r.code == 229) {
      port = int.tryParse(RegExp(r'\|\|\|(\d+)\|').firstMatch(r.text)?[1] ?? '');
    }
    if (port == null) {
      await _send('PASV');
      r = await _reply();
      final m = RegExp(r'(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)').firstMatch(r.text);
      if (r.code != 227 || m == null) {
        throw FtpException('Mode passif refusé : ${r.code} ${r.text}');
      }
      // L'adresse annoncée est souvent interne : on garde celle du serveur.
      port = int.parse(m[5]!) * 256 + int.parse(m[6]!);
    }
    return Socket.connect(config.host, port, timeout: _timeout);
  }

  Future<Socket> _secureData(Socket socket) => config.tls
      ? SecureSocket.secure(socket,
          host: config.host, onBadCertificate: (_) => true)
      : Future.value(socket);

  /// Contenu d'un dossier.
  Future<List<FtpEntry>> list(String path) async {
    final raw = await _socketData(socket: await _data(), command: 'MLSD ${_path(path)}');
    if (raw != null) return _parseMlsd(raw);
    final list = await _socketData(socket: await _data(), command: 'LIST -a ${_path(path)}');
    return _parseList(list ?? '');
  }

  /// Envoie [command] et lit tout ce qui arrive sur la connexion de données ;
  /// null si la commande est refusée (ex. `MLSD` non pris en charge).
  Future<String?> _socketData({required Socket socket, required String command}) async {
    await _send(command);
    final r = await _reply();
    if (r.code != 125 && r.code != 150) {
      socket.destroy();
      return null;
    }
    final data = await _secureData(socket);
    final bytes = <int>[];
    await for (final chunk in data) {
      bytes.addAll(chunk);
    }
    await _expect([226, 250]);
    return utf8.decode(bytes, allowMalformed: true);
  }

  static List<FtpEntry> _parseMlsd(String raw) => [
        for (final line in const LineSplitter().convert(raw))
          if (line.contains('; '))
            () {
              final i = line.indexOf('; ');
              final facts = {
                for (final f in line.substring(0, i).split(';'))
                  if (f.contains('='))
                    f.substring(0, f.indexOf('=')).toLowerCase():
                        f.substring(f.indexOf('=') + 1),
              };
              final type = facts['type']?.toLowerCase() ?? '';
              return (type, FtpEntry(line.substring(i + 2),
                  isDir: type == 'dir',
                  size: int.tryParse(facts['size'] ?? '') ?? 0));
            }(),
      ]
          .where((e) => e.$1 == 'dir' || e.$1 == 'file')
          .map((e) => e.$2)
          .toList();

  /// `LIST` façon Unix : `drwxr-xr-x 1 u g 4096 Oct 17 12:00 Nom`.
  static List<FtpEntry> _parseList(String raw) {
    final re = RegExp(r'^([d\-l])\S*\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\S+\s+\S+\s+(.+)$');
    return [
      for (final line in const LineSplitter().convert(raw))
        if (re.firstMatch(line) case final m?)
          if (m[3] != '.' && m[3] != '..')
            FtpEntry(m[3]!, isDir: m[1] == 'd', size: int.parse(m[2]!)),
    ];
  }

  /// Taille d'un fichier, ou null s'il n'existe pas.
  Future<int?> size(String path) async {
    await _send('SIZE ${_path(path)}');
    final r = await _reply();
    return r.code == 213 ? int.tryParse(r.text.trim()) : null;
  }

  /// Lit [path] à partir de [offset] (`REST`). Le flux s'arrête quand on
  /// l'annule ; la connexion n'est alors plus réutilisable (on la ferme).
  Future<Stream<List<int>>> read(String path, {int offset = 0}) async {
    final socket = await _data();
    if (offset > 0) await _command('REST $offset', [350]);
    await _send('RETR ${_path(path)}');
    final r = await _reply();
    if (r.code != 125 && r.code != 150) {
      socket.destroy();
      throw FtpException('Lecture refusée : ${r.code} ${r.text}');
    }
    return _secureData(socket);
  }

  String _path(String p) => p.isEmpty ? '/' : p;

  Future<void> close() async {
    try {
      await _send('QUIT');
    } on Object {
      // Déjà fermée.
    }
    await _subscription?.cancel();
    _control?.destroy();
    _control = null;
  }
}
