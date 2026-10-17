import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/jellyfin.dart';
import '../api/tracker.dart';
import '../state/torrents.dart';
import 'player_page.dart';
import 'theme.dart';

// Sorties déjà « sur le disque » : dans la bibliothèque Jellyfin (index chargé
// une fois), ou torrent terminé dans Transmission (même infohash).

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

/// Lit un film dans le lecteur intégré ; pour une série, ouvre d'abord la
/// liste des épisodes.
void playOnJellyfin(BuildContext context, JellyfinItem item) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => item.isSeries
            ? EpisodesPage(series: item)
            : PlayerPage(
                item: item,
                title: [item.name, if (item.year != null) '(${item.year})']
                    .join(' '))));

/// Pastille ronde « Lire sur Jellyfin » (cartes, lignes).
class PlayBadge extends StatelessWidget {
  const PlayBadge({super.key, required this.item, this.size = 30});
  final JellyfinItem item;
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
          onTap: () => playOnJellyfin(context, item),
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
