/// Polices de l'interface, au choix dans les Réglages : Inter par défaut,
/// et une sélection de polices code et rétro. Toutes sont intégrées
/// (pubspec.yaml), sous licence OFL.
enum AppFont {
  inter('Inter', 'Inter', 'Lisible, par défaut'),
  jetBrainsMono('JetBrainsMono', 'JetBrains Mono', 'Code', scale: 0.92),
  firaCode('FiraCode', 'Fira Code', 'Code', scale: 0.92),
  ibmPlexMono('IBMPlexMono', 'IBM Plex Mono', 'Code', scale: 0.92),
  victorMono('VictorMono', 'Victor Mono', 'Code, étroite', scale: 0.98),
  martianMono('MartianMono', 'Martian Mono', 'Code, large', scale: 0.84),
  spaceMono('SpaceMono', 'Space Mono', 'Rétro-futuriste', scale: 0.9),
  shareTechMono('ShareTechMono', 'Share Tech Mono', 'Terminal', scale: 0.98),
  vt323('VT323', 'VT323', 'Terminal cathodique', scale: 1.25),
  pixelifySans('PixelifySans', 'Pixelify Sans', 'Pixel', scale: 0.98),
  pressStart2P('PressStart2P', 'Press Start 2P', 'Arcade 8 bits', scale: 0.62);

  const AppFont(this.family, this.label, this.style, {this.scale = 1});

  /// Nom de la famille dans pubspec.yaml (et de sa licence).
  final String family;
  final String label;

  /// Son genre, en quelques mots.
  final String style;

  /// Facteur de taille du texte : les polices à chasse fixe sont plus
  /// larges qu'Inter, VT323 plus petite.
  final double scale;

  static AppFont byName(String? name) => AppFont.values.asNameMap()[name] ?? AppFont.inter;

  /// Fichier de licence (assets/), pour l'écran des licences.
  String get license => this == inter ? 'assets/fonts/OFL.txt' : 'assets/fonts/licenses/$family.txt';
}
