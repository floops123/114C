import '../core/release_name.dart';
import 'tracker.dart';

/// Type de contenu d'une sortie, commun à tous les trackers : chacun range
/// ses sorties dans ses propres catégories (C411 « Films & Vidéos › Film »,
/// Torznab « Movies/HD », AstraTorrent « films »…), ramenées ici à une seule
/// liste. Sert aux filtres du catalogue, à l'image affichée à défaut
/// d'affiche et à l'étiquette posée dans Transmission.
enum ContentKind {
  movie('Film', 'Films'),
  series('Série', 'Séries'),
  documentary('Documentaire', 'Documentaires'),
  animation('Animation', 'Animation'),
  music('Musique', 'Musique'),
  book('Livre', 'Livres'),
  game('Jeu vidéo', 'Jeux vidéo'),
  software('Logiciel', 'Logiciels'),
  adult('Adulte', 'Adulte'),
  other('Contenu', 'Autres');

  const ContentKind(this.label, this.plural);
  final String label;

  /// Nom de la catégorie dans les filtres et dans les étiquettes de
  /// Transmission.
  final String plural;

  static bool _any(String s, List<String> words) => words.any(s.contains);

  /// D'après la fiche du tracker (C411), la sous-catégorie, puis le nom.
  static ContentKind of(Release r) => _classify(
        // Sous-catégorie et catégories du tracker (pour Torznab, celles du
        // `caps` : « Movies/HD », « TV/HD », « Books/EBook »…).
        sub: [r.subcategory, ...r.categories].join(' ').toLowerCase(),
        name: r.name,
        mediaKind: r.mediaKind,
        resolution: r.resolution,
      );

  /// D'après le nom seul : torrent ajouté sans passer par un tracker
  /// (fichier .torrent, lien magnet).
  static ContentKind ofName(String name) => _classify(sub: '', name: name);

  static ContentKind _classify(
      {required String sub, required String name, String? mediaKind, String? resolution}) {
    final lower = name.toLowerCase();
    bool word(String pattern) => RegExp('\\b($pattern)\\b').hasMatch(sub);
    if (_any(sub, ['xxx', 'adulte', 'hentai', 'porn'])) return adult;
    // « Série Documentaire » (C411, Nostradamus), « TV/Documentary » (Torznab).
    if (_any(sub, ['documentaire', 'documentary']) ||
        RegExp(r'[.\s]doc[.\s]').hasMatch(lower)) {
      return documentary;
    }
    switch (mediaKind) {
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
    if (_any(sub, ['livre', 'ebook', 'audiobook', 'bd', 'manga', 'comic', 'presse', 'roman']) ||
        word('books?|magazines?')) {
      return book;
    }
    // Après les livres : « Ebook › Audio » (C411) et « Audio/Audiobook »
    // (Torznab) sont des livres audio.
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
    if (ReleaseName.parse(name).kind == 'Série') return series;
    if (RegExp(r'\b(epub|pdf|cbz|cbr|mobi|azw3)\b').hasMatch(lower)) return book;
    if (RegExp(r'\b(flac|mp3|aac|alac)\b').hasMatch(lower) &&
        !RegExp(r'\b(1080p|2160p|720p)\b').hasMatch(lower)) {
      return music;
    }
    if (RegExp(r'elamigos|fitgirl|\bgog\b|codex|skidrow').hasMatch(lower)) return game;
    if (resolution != null || ReleaseName.parse(name).resolution != null) {
      return movie;
    }
    return other;
  }

  /// Étiquette de Transmission : la catégorie au pluriel (« Films »,
  /// « Séries »…), la même quel que soit le tracker. Aucune pour un contenu
  /// non reconnu.
  List<String> get labels => this == other ? const [] : [plural];
}
