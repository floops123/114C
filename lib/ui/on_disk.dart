import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/jellyfin.dart';
import '../api/tracker.dart';
import '../state/media_library.dart';
import '../state/torrents.dart';
import 'disk_page.dart';
import 'player_page.dart';
import 'series_page.dart';
import 'theme.dart';

// Sorties déjà « sur le disque » : dans notre base (fichiers du FTP), dans
// la bibliothèque Jellyfin (index chargé une fois), ou torrent terminé dans
// Transmission (même infohash).

/// Ce qu'on peut lire pour une sortie.
class Playable {
  const Playable({required this.isSeries, required this.label, required this.description, required this.play});
  final bool isSeries;

  /// Pastille : « SUR LE DISQUE », « DANS JELLYFIN ».
  final String label;
  final String description;
  final void Function(BuildContext context) play;
}

/// Le titre de la sortie dans notre base, sinon dans Jellyfin, ou null.
Playable? playableFor(WidgetRef ref, Release r) {
  final local =
      ref.watch(mediaLibraryProvider.select((s) => s.library.forRelease(r)));
  if (local != null) {
    return Playable(
        isSeries: local.isSeries,
        label: 'SUR LE DISQUE',
        description: 'Sur le disque : dans ta base (${local.files.length} '
            'fichier${local.files.length > 1 ? 's' : ''})',
        play: (context) => playLocal(context, local));
  }
  final item = jellyfinFor(ref, r);
  if (item == null) return null;
  return Playable(
      isSeries: item.isSeries,
      label: 'DANS JELLYFIN',
      description: 'Sur le disque : dans ta bibliothèque Jellyfin',
      play: (context) => playOnJellyfin(context, item));
}

/// L'élément Jellyfin correspondant à la sortie, ou null.
JellyfinItem? jellyfinFor(WidgetRef ref, Release r) => ref.watch(
    jellyfinLibraryProvider.select((l) => l.value?.forRelease(r)));

/// Le torrent de la sortie est-il téléchargé dans Transmission ?
bool downloadedFor(WidgetRef ref, Release r) {
  final hash = r.infoHash;
  if (hash == null) return false;
  return ref.watch(torrentsProvider.select((s) => s.byId.values
      .any((t) => t.hash == hash && t.percentDone >= 1)));
}

/// Lit un film dans le lecteur intégré (choix de la version s'il y en a
/// plusieurs sur le disque) ; pour une série, ouvre d'abord la liste des
/// épisodes.
void playOnJellyfin(BuildContext context, JellyfinItem item) {
  if (item.isSeries) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EpisodesPage(series: item)));
    return;
  }
  final library =
      ProviderScope.containerOf(context).read(jellyfinLibraryProvider).value;
  playVersions(context, library?.versionsOf(item) ?? [item],
      [item.name, if (item.year != null) '(${item.year})'].join(' '));
}

/// Pastille ronde « Lire » (cartes, lignes).
class PlayBadge extends StatelessWidget {
  const PlayBadge({super.key, required this.item, this.size = 30});
  final Playable item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: item.isSeries ? 'Épisodes' : 'Lire',
      child: Material(
        color: c.success,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => item.play(context),
          child: SizedBox.square(
            dimension: size,
            child: Icon(Icons.play_arrow_rounded,
                size: size * 0.65, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
