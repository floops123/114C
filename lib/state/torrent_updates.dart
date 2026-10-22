import 'package:flutter/foundation.dart';

import '../api/c411.dart';
import '../api/tracker.dart';
import '../api/transmission.dart';
import 'notifications.dart';

// Torrent modifié sur C411 (fichiers changés, .torrent refait) : le format
// exact de la notification n'a pas encore été vu. On accepte tout type qui
// parle d'un torrent mis à jour, et toutes les empreintes qu'elle contient
// (`infoHash`, `oldInfoHash`, `newInfoHash`… et le lien `/torrents/<hash>`).

final _hashRe = RegExp(r'^[0-9a-fA-F]{40}$');

/// Notification d'un torrent modifié sur le site.
bool isTorrentUpdate(AppNotification n) => isTorrentUpdateType(n.type);

bool isTorrentUpdateType(String type) {
  final t = type.toLowerCase();
  return t.contains('torrent') &&
      RegExp(r'updat|modif|edit|replac|chang').hasMatch(t);
}

/// Empreintes citées par une notification, la plus récente d'abord
/// (`newInfoHash`, puis `infoHash` et le lien, puis l'ancienne).
List<String> notificationHashes(AppNotification n) {
  final data = n.raw;
  final entries = data is Map
      ? [
          for (final e in data.entries)
            if (e.key is String &&
                (e.key as String).toLowerCase().contains('hash') &&
                e.value is String &&
                _hashRe.hasMatch(e.value as String))
              (e.key as String, (e.value as String).toLowerCase()),
        ]
      : <(String, String)>[];
  int rank(String key) {
    final k = key.toLowerCase();
    if (k.contains('new')) return 0;
    if (k.contains('old') || k.contains('prev') || k.contains('former')) return 2;
    return 1;
  }

  // Le lien mène au torrent actuel : avant l'ancienne empreinte.
  final link = RegExp(r'/torrents/([0-9a-fA-F]{40})').firstMatch(n.link ?? '');
  if (link != null) entries.add(('link', link.group(1)!.toLowerCase()));
  entries.sort((a, b) => rank(a.$1).compareTo(rank(b.$1)));
  return {for (final (_, h) in entries) h}.toList();
}

enum UpdateOutcome { updated, unchanged, absent }

/// Remplace dans Transmission un torrent modifié sur le site : le nouveau
/// .torrent s'ajoute en pause dans le dossier de l'ancien, avec ses
/// étiquettes ; l'ancien est retiré sans ses données, puis le nouveau est
/// vérifié (seules les parties changées se retéléchargent) et relancé s'il
/// tournait. Même empreinte qu'avant : rien à faire.
Future<(UpdateOutcome, String?)> updateModifiedTorrent(
    TransmissionClient client, C411SiteApi site, AppNotification n) async {
  final hashes = notificationHashes(n);
  if (hashes.isEmpty) return (UpdateOutcome.absent, null);
  final found = await client.torrentGet(
      ['id', 'hashString', 'name', 'labels', 'downloadDir', 'status'],
      ids: hashes);
  final old = found.torrents.firstOrNull;
  final oldId = (old?['id'] as num?)?.toInt();
  if (old == null || oldId == null) return (UpdateOutcome.absent, null);
  final oldHash = (old['hashString'] as String).toLowerCase();
  final name = old['name'] as String? ?? oldHash;

  // Le .torrent à jour : par la plus récente des empreintes connues.
  Uint8List? metainfo;
  TrackerException? failure;
  for (final h in hashes) {
    try {
      metainfo = await site.downloadTorrent(Release(
          tracker: Tracker.c411, id: h, name: name, infoHash: h, createdAt: DateTime(2000)));
      break;
    } on TrackerException catch (e) {
      failure = e;
    }
  }
  if (metainfo == null) throw failure!;

  final labels = (old['labels'] as List? ?? const []).whereType<String>().toList();
  final added = await client.addTorrentWithHash(
    metainfo: metainfo,
    options: AddOptions(
        downloadDir: old['downloadDir'] as String?, paused: true, labels: labels),
  );
  if (!added.added || added.hash == null || added.hash == oldHash) {
    return (UpdateOutcome.unchanged, name);
  }
  final fresh = await client.torrentGet(['id'], ids: [added.hash!]);
  final newId = (fresh.torrents.firstOrNull?['id'] as num?)?.toInt();
  if (newId == null) return (UpdateOutcome.unchanged, name);
  if (labels.isNotEmpty) await client.torrentSet([newId], {'labels': labels});
  await client.remove([oldId]);
  await client.action('torrent-verify', [newId]);
  // 0 : arrêté. Un torrent en pause le reste.
  if (old['status'] != 0) await client.action('torrent-start', [newId]);
  return (UpdateOutcome.updated, name);
}
