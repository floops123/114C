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

/// Ajoute plusieurs sorties à Transmission, une par une, puis résume le tout
/// en un seul message. Renvoie le nombre de torrents ajoutés.
Future<int> sendManyToTransmission(
  BuildContext context,
  WidgetRef ref,
  List<Release> releases, {
  AddOptions options = const AddOptions(),
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  final trackers = ref.read(trackersProvider);
  final transmission = ref.read(transmissionProvider);
  final torrents = ref.read(torrentsProvider.notifier);
  if (transmission == null) {
    say('Configure Transmission dans les réglages');
    return 0;
  }
  var added = 0;
  var present = 0;
  final failed = <String>[];
  for (final release in releases) {
    final api = trackers[release.tracker];
    if (api == null) {
      failed.add('${release.name} : ${release.tracker.label} non configuré');
      continue;
    }
    try {
      final link = release.downloadUrl;
      final withKind = options.withLabels(ContentKind.of(release).labels);
      final ok = link != null && link.startsWith('magnet:')
          ? await transmission.addTorrent(filename: link, options: withKind)
          : await transmission.addTorrent(
              metainfo: await api.downloadTorrent(release), options: withKind);
      ok ? added++ : present++;
    } on TrackerException catch (e) {
      failed.add('${release.name} : ${e.message}');
    } on TransmissionException catch (e) {
      failed.add('${release.name} : ${e.message}');
    }
  }
  say([
    [
      '$added ajouté${added > 1 ? 's' : ''} à Transmission',
      if (present > 0) '$present déjà présent${present > 1 ? 's' : ''}',
      if (failed.isNotEmpty) '${failed.length} en échec',
    ].join(' · '),
    ...failed.take(3),
  ].join('\n'));
  if (added > 0) await torrents.refresh(full: true);
  return added;
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
