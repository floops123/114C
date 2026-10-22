import 'dart:convert';
import 'dart:typed_data';

import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/ui/torrent_actions.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _torrent(String name, int length) {
  // .torrent minimal à un fichier, en bencode.
  final info = 'd6:lengthi${length}e4:name${utf8.encode(name).length}:$name'
      '12:piece lengthi16384e6:pieces20:${'x' * 20}e';
  return Uint8List.fromList(utf8.encode('d4:info${info}e'));
}

class _Client extends TransmissionClient {
  _Client() : super(url: 'http://x');
  final received = <(Uint8List, AddOptions)>[];

  @override
  Future<bool> addTorrent(
      {Uint8List? metainfo, String? filename, AddOptions options = const AddOptions()}) async {
    received.add((metainfo!, options));
    final name = utf8.decode(metainfo, allowMalformed: true);
    if (name.contains('refuse')) throw const TransmissionException('Transmission : invalid or corrupt torrent file');
    return !name.contains('deja');
  }
}

void main() {
  test('envoi de fichiers .torrent : ajoutés, déjà présents, invalides, refusés',
      () async {
    final client = _Client();
    const options = AddOptions(downloadDir: '/data/films', labels: ['pc']);
    final report = await addTorrentFiles(client, [
      ('film.torrent', _torrent('Film.mkv', 100)),
      ('deja.torrent', _torrent('deja.mkv', 100)),
      ('photo.jpg', Uint8List.fromList([0xFF, 0xD8, 0xFF])),
      ('refuse.torrent', _torrent('refuse.mkv', 1)),
    ], options);

    expect((report.added, report.duplicates), (1, 1));
    expect(report.invalid, ['photo.jpg']);
    expect(report.failed.single, startsWith('refuse.torrent : '));
    expect(report.summary, '1 ajouté(s) · 1 déjà présent(s) · 1 invalide(s) · 1 refusé(s)');
    // Le fichier invalide n'est jamais envoyé ; les options suivent.
    expect(client.received, hasLength(3));
    expect(client.received.every((r) => r.$2.downloadDir == '/data/films'), isTrue);
  });

  test('envoi de fichiers .torrent : catégorie devinée du nom, en plus des étiquettes choisies',
      () async {
    final client = _Client();
    await addTorrentFiles(client, [
      ('a.torrent', _torrent('Serie.S01E01.1080p.WEB-GRP.mkv', 100)),
      ('b.torrent', _torrent('Auteur.Roman.FRENCH.EPUB-GRP.epub', 100)),
      ('c.torrent', _torrent('archive.bin', 100)),
    ], const AddOptions(labels: ['pc']));
    expect([for (final (_, o) in client.received) o.labels], [
      ['pc', 'Séries'],
      ['pc', 'Livres'],
      ['pc'],
    ]);
  });
}
