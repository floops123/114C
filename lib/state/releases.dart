import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/c411.dart';
import '../api/content_kind.dart';
import '../api/tracker.dart';
import '../api/transmission.dart';
import 'torrents.dart';

/// Récupère le .torrent sur le tracker de la sortie et l'envoie à Transmission.
Future<void> sendToTransmission(
  BuildContext context,
  WidgetRef ref,
  Release release, {
  AddOptions options = const AddOptions(),
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  final api = ref.read(trackersProvider)[release.tracker];
  final transmission = ref.read(transmissionProvider);
  // Lu avant les `await` : le bouton peut être démonté pendant l'envoi
  // (navigation, liste reconstruite), et `ref` n'est alors plus utilisable.
  final torrents = ref.read(torrentsProvider.notifier);
  if (api == null || transmission == null) {
    say('Configure ${release.tracker.label} et Transmission dans les réglages');
    return;
  }
  try {
    final link = release.downloadUrl;
    final withKind = options.withLabels(ContentKind.of(release).labels);
    final added = link != null && link.startsWith('magnet:')
        ? await transmission.addTorrent(filename: link, options: withKind)
        : await transmission.addTorrent(
            metainfo: await api.downloadTorrent(release), options: withKind);
    say(added
        ? 'Ajouté à Transmission : ${release.name}'
        : 'Déjà présent dans Transmission');
    await torrents.refresh(full: true);
  } on TrackerException catch (e) {
    say(e.message);
  } on TransmissionException catch (e) {
    say(e.message);
  }
}

/// Le .torrent d'une sortie. C411 : par le site avec le cookie de session
/// s'il est renseigné (`/api/torrents/<infohash>/download`, sans attente
/// entre deux), sinon par la clé API ; les autres trackers par leur propre
/// méthode.
Future<Uint8List> fetchTorrentFile(
        TrackerApi api, C411SiteApi? site, Release release) =>
    api.tracker == Tracker.c411 && site != null && release.infoHash != null
        ? site.downloadTorrent(release)
        : api.downloadTorrent(release);
