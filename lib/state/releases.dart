import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final added = link != null && link.startsWith('magnet:')
        ? await transmission.addTorrent(filename: link, options: options)
        : await transmission.addTorrent(
            metainfo: await api.downloadTorrent(release), options: options);
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
