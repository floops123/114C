import 'dart:convert';
import 'dart:io';

/// Client RPC Transmission minimal : juste la liste des torrents.
class TransmissionRpc {
  TransmissionRpc(this.url, {this.user = '', this.password = '', HttpClient? http})
      : _http = http ?? HttpClient();

  final String url;
  final String user;
  final String password;
  final HttpClient _http;
  String? _session;

  /// `torrent-get` avec ces [fields].
  Future<List<Map<String, dynamic>>> torrents(List<String> fields) async {
    final body = jsonEncode({
      'method': 'torrent-get',
      'arguments': {'fields': fields},
    });
    // Transmission répond 409 avec un nouveau jeton anti-CSRF : on rejoue une fois.
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = await _http.postUrl(Uri.parse(url));
      request.headers.contentType = ContentType.json;
      if (_session != null) request.headers.set('X-Transmission-Session-Id', _session!);
      if (user.isNotEmpty || password.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader,
            'Basic ${base64.encode(utf8.encode('$user:$password'))}');
      }
      request.write(body);
      final reply = await request.close();
      final text = await reply.transform(utf8.decoder).join();
      if (reply.statusCode == 409) {
        _session = reply.headers.value('X-Transmission-Session-Id');
        continue;
      }
      if (reply.statusCode == 401) {
        throw const HttpException('Transmission : identifiants refusés');
      }
      if (reply.statusCode != 200) {
        throw HttpException('Transmission : HTTP ${reply.statusCode}');
      }
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['result'] != 'success') {
        throw HttpException('Transmission : ${json['result']}');
      }
      return [
        for (final t in ((json['arguments'] as Map?)?['torrents'] as List? ?? const [])
            .whereType<Map>())
          t.cast<String, dynamic>(),
      ];
    }
    throw const HttpException('Transmission : jeton de session refusé');
  }

  void close() => _http.close(force: true);
}
