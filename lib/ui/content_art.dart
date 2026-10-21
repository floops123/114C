import 'package:flutter/material.dart';

import '../api/tracker.dart';
import '../core/release_name.dart';
import 'theme.dart';

/// Type de contenu d'une sortie, pour l'image affichée à défaut d'affiche.
enum ContentKind {
  movie('Film', Icons.movie_rounded),
  series('Série', Icons.live_tv_rounded),
  documentary('Documentaire', Icons.public_rounded),
  animation('Animation', Icons.animation_rounded),
  music('Musique', Icons.album_rounded),
  book('Livre', Icons.menu_book_rounded),
  game('Jeu vidéo', Icons.sports_esports_rounded),
  software('Logiciel', Icons.terminal_rounded),
  adult('Adulte', Icons.no_adult_content_rounded),
  other('Contenu', Icons.folder_zip_rounded);

  const ContentKind(this.label, this.icon);
  final String label;
  final IconData icon;

  static bool _any(String s, List<String> words) => words.any(s.contains);

  /// D'après la fiche du tracker (C411), la sous-catégorie, puis le nom.
  static ContentKind of(Release r) {
    // Sous-catégorie et catégories du tracker (pour Torznab, celles du
    // `caps` : « Movies/HD », « TV/HD », « Books/EBook »…).
    final sub = [r.subcategory, ...r.categories].join(' ').toLowerCase();
    final name = r.name.toLowerCase();
    bool word(String pattern) => RegExp('\\b($pattern)\\b').hasMatch(sub);
    if (_any(sub, ['xxx', 'adulte', 'hentai', 'porn'])) return adult;
    if (sub.contains('documentaire') || RegExp(r'[.\s]doc[.\s]').hasMatch(name)) {
      return documentary;
    }
    switch (r.mediaKind) {
      case 'music':
        return music;
      case 'game':
        return game;
      case 'tv':
        return _any(sub, ['anim']) ? animation : series;
      case 'movie':
        return _any(sub, ['anim']) ? animation : movie;
    }
    if (_any(sub, ['anim'])) return animation;
    if (_any(sub, ['série', 'serie', 'saison', 'épisode', 'episode', 'émission']) ||
        word('tv')) {
      return series;
    }
    if (_any(sub, ['livre', 'ebook', 'bd', 'manga', 'comic', 'presse', 'roman']) ||
        word('books?|magazines?')) {
      return book;
    }
    // Après les livres : « Ebook › Audio » est un livre audio.
    if (_any(sub, ['musique', 'album', 'flac', 'mp3', 'audio', 'karaok', 'podcast']) ||
        word('music')) {
      return music;
    }
    if (_any(sub, ['jeu', 'jv', 'nintendo', 'playstation', 'xbox', 'switch', 'sony']) ||
        word('games?|console')) {
      return game;
    }
    if (_any(sub, ['logiciel', 'application', 'apps', 'macos', 'linux', 'windows']) ||
        word('pc|mobile|software')) {
      return software;
    }
    if (_any(sub, ['film', 'métrage', 'metrage', 'spectacle', 'concert']) ||
        word('movies?')) {
      return movie;
    }
    // Rien dans la catégorie : indices dans le nom.
    if (ReleaseName.parse(r.name).kind == 'Série') return series;
    if (RegExp(r'\b(epub|pdf|cbz|cbr|mobi|azw3)\b').hasMatch(name)) return book;
    if (RegExp(r'\b(flac|mp3|aac|alac)\b').hasMatch(name) &&
        !RegExp(r'\b(1080p|2160p|720p)\b').hasMatch(name)) {
      return music;
    }
    if (RegExp(r'elamigos|fitgirl|\bgog\b|codex|skidrow').hasMatch(name)) return game;
    if (r.resolution != null || ReleaseName.parse(r.name).resolution != null) {
      return movie;
    }
    return other;
  }

  /// Dégradé, dans les couleurs de la palette.
  List<Color> colors(AppColors c) => switch (this) {
        movie => [c.accent, c.download],
        series => [c.download, c.info],
        documentary => [c.success, c.download],
        animation => [c.warning, c.accent],
        music => [c.upload, c.warning],
        book => [c.toneBronze, c.warning],
        game => [c.info, c.accent],
        software => [c.muted, c.download],
        adult => [c.danger, c.upload],
        other => [c.muted, c.border],
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
