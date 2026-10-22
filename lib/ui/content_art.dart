import 'package:flutter/material.dart';

import '../api/content_kind.dart';
import 'theme.dart';

export '../api/content_kind.dart';

/// Picto et couleurs d'un type de contenu, pour l'image affichée à défaut
/// d'affiche.
extension ContentKindStyle on ContentKind {
  IconData get icon => switch (this) {
        ContentKind.movie => Icons.movie_rounded,
        ContentKind.series => Icons.live_tv_rounded,
        ContentKind.documentary => Icons.public_rounded,
        ContentKind.animation => Icons.animation_rounded,
        ContentKind.music => Icons.album_rounded,
        ContentKind.book => Icons.menu_book_rounded,
        ContentKind.game => Icons.sports_esports_rounded,
        ContentKind.software => Icons.terminal_rounded,
        ContentKind.adult => Icons.no_adult_content_rounded,
        ContentKind.other => Icons.folder_zip_rounded,
      };

  /// Dégradé, dans les couleurs de la palette.
  List<Color> colors(AppColors c) => switch (this) {
        ContentKind.movie => [c.accent, c.download],
        ContentKind.series => [c.download, c.info],
        ContentKind.documentary => [c.success, c.download],
        ContentKind.animation => [c.warning, c.accent],
        ContentKind.music => [c.upload, c.warning],
        ContentKind.book => [c.toneBronze, c.warning],
        ContentKind.game => [c.info, c.accent],
        ContentKind.software => [c.muted, c.download],
        ContentKind.adult => [c.danger, c.upload],
        ContentKind.other => [c.muted, c.border],
      };
}

/// Image d'un type de contenu, à défaut d'affiche : dégradé opaque, grande
/// icône et nom du type (rien de translucide ni d'animé).
class ContentArt extends StatelessWidget {
  const ContentArt(this.kind, {super.key, this.radius = 8});
  final ContentKind kind;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final [a, b] = kind.colors(c);
    // Couleurs assombries vers le fond : lisible et sans éclat.
    final from = Color.lerp(a, c.bg, 0.45)!;
    final to = Color.lerp(b, c.bg, 0.7)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [from, to],
        ),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        return Stack(children: [
          Center(
            child: Icon(kind.icon,
                size: size * 0.42, color: Colors.white.withValues(alpha: 0.9)),
          ),
          if (size >= 90)
            Positioned(
              left: 0,
              right: 0,
              bottom: size * 0.12,
              child: Text(kind.label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: (size * 0.09).clamp(10, 16),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ),
        ]);
      }),
    );
  }
}

/// Picto d'une catégorie ou sous-catégorie de tracker, d'après son nom
/// (« Films & Vidéos », « Séries TV », « Ebook », « Jeux Vidéo »…). null :
/// « Tout » ; sinon un picto générique.
IconData categoryIcon(String? name) {
  if (name == null) return Icons.apps_rounded;
  final n = name.toLowerCase();
  bool any(List<String> words) => words.any(n.contains);
  if (any(['xxx', 'adulte', 'hentai', 'porn'])) return ContentKind.adult.icon;
  if (any(['anim'])) return ContentKind.animation.icon;
  if (any(['documentaire', 'docu'])) return ContentKind.documentary.icon;
  if (any(['série', 'serie', 'tv', 'émission', 'emission', 'saison'])) {
    return ContentKind.series.icon;
  }
  if (any(['sport'])) return Icons.sports_soccer_rounded;
  if (any(['concert', 'spectacle'])) return Icons.theater_comedy_rounded;
  if (any(['karaok', 'podcast', 'radio'])) return Icons.mic_rounded;
  if (any(['audio', 'musique', 'music', 'album', 'flac', 'mp3', 'sample'])) {
    return ContentKind.music.icon;
  }
  if (any(['ebook', 'livre', 'book', 'bd', 'manga', 'comic', 'presse', 'roman'])) {
    return ContentKind.book.icon;
  }
  if (any(['jeu', 'game', 'nintendo', 'playstation', 'sony', 'xbox', 'microsoft',
      'switch', 'console'])) {
    return ContentKind.game.icon;
  }
  if (any(['logiciel', 'application', 'apps', 'windows', 'linux', 'macos', 'mac os',
      'smartphone', 'tablette', 'android', 'ios'])) {
    return ContentKind.software.icon;
  }
  if (any(['clip', 'vidéo', 'video'])) {
    return n.contains('film') ? ContentKind.movie.icon : Icons.videocam_rounded;
  }
  if (any(['film', 'movie', 'métrage', 'metrage', 'cinéma', 'cinema'])) {
    return ContentKind.movie.icon;
  }
  if (any(['formation', 'tuto', 'cours'])) return Icons.school_rounded;
  if (any(['gps', 'carte'])) return Icons.map_rounded;
  return Icons.label_rounded;
}
