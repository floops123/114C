// Comparaison de titres entre TMDB, trackers et Jellyfin : sans accents,
// sans ponctuation, sans casse.

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a', 'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i', 'î': 'i',
  'ï': 'i', 'ñ': 'n', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'œ': 'oe',
  'æ': 'ae', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Á': 'A', 'Ç': 'C', 'É': 'E',
  'È': 'E', 'Ê': 'E', 'Ë': 'E', 'Î': 'I', 'Ï': 'I', 'Ô': 'O', 'Ö': 'O',
  'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'Œ': 'OE', 'Æ': 'AE',
};

String foldAccents(String s) =>
    s.split('').map((ch) => _accents[ch] ?? ch).join();

/// Mots d'un titre, sans accents ni ponctuation : « Dune : Deuxième partie »
/// → Dune, Deuxieme, partie ; « Journal d'une femme » → Journal, d, une…
List<String> titleWords(String title) => foldAccents(title)
    .split(RegExp(r'[^A-Za-z0-9]+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// Clé de comparaison : « Dune : Deuxième partie » → « dune deuxieme partie ».
String titleKey(String s) => titleWords(s).join(' ').toLowerCase();
