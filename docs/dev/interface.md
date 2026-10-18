# Interface et performances

[← Sommaire](../README.md)

## Le thème

Inspiré de c411.org, avec des nuances bleu-vert. Toutes les couleurs vivent
dans `AppColors` (`lib/ui/theme.dart`) et s'obtiennent par `context.colors` :
aucune couleur en dur dans les écrans.

| Rôle | Sombre | Clair | Usage |
|---|---|---|---|
| `bg` | `#07141A` | `#F2F7F4` | fond des pages |
| `surface` | `#0E1D23` | `#FFFFFF` | cartes |
| `surfaceAlt` | `#16292E` | `#E3EEE8` | champs, intertitres |
| `border` | `#213840` | `#D3E2DA` | bords fins |
| `text` / `muted` | `#F1F8F6` / `#97AFAB` | `#0B1A14` / `#4F6A5E` | textes |
| `accent` | `#00D492` | `#00855B` | vert C411, actions principales (texte `onAccent` sombre par-dessus) |
| `success` | `#3AAE8A` | `#1E8466` | « sur le disque », lecture, terminé |
| `info` | `#3BB4D4` | `#0E86A3` | séries, HDR, informations |
| `warning` / `danger` | `#FFB900` / `#F85245` | `#B27800` / `#D63A2E` | alertes, erreurs, zéro seeder |
| `download` / `upload` | `#3987E5` / `#D95926` | `#2A78D6` / `#EB6834` | réception / envoi (graphiques), recherche sur les trackers |

La paire `download` / `upload` (bleu / orange) est choisie pour rester
distincte en cas de daltonisme et lisible sur les deux fonds.

Principes visuels :

- **Rien de translucide ni d'animé** : les effets de verre et les animations
  ont été retirés, ils coûtaient trop cher au rendu. Les nuances viennent de
  mélanges opaques (`Color.lerp(couleur, c.surface, 0.8)`).
- Police **Inter** intégrée (graisses 400 à 800), pas de `google_fonts` :
  aucun téléchargement au démarrage, rendu identique hors ligne.
- Pas d'ombre ni d'onde Material : cartes plates à bord fin.

## Composants partagés

| Composant | Fichier | Rôle |
|---|---|---|
| `Panel`, `Section` | `theme.dart`, `widgets.dart` | carte opaque (Material, pour les effets d'encre) |
| `PageHeader` | `widgets.dart` | titre de page, sous-titre, actions (icônes de 26 px) |
| `FeatureButton` | `widgets.dart` | gros bouton dégradé (Découvrir, trackers) |
| `ChipRow` | `widgets.dart` | rangée de pastilles avec picto |
| `SortMenu` | `widgets.dart` | menu de tri avec icônes et sens |
| `Tag`, `Poster`, `EmptyState`, `ErrorBanner` | `widgets.dart` | étiquette, affiche avec repli, états vides et erreurs |
| `ContentArt`, `categoryIcon` | `content_art.dart` | image d'un type de contenu, picto d'une catégorie |
| `ReleaseCard`, `ReleaseTile`, `ReleaseRow`, `releaseGrid` | `releases_page.dart` | une sortie en carte, tuile PC, ligne ; la grille commune |
| `_InfoCard`, `_InfoRow` | `wishlist_page.dart` | encadrés de la fiche d'un titre |

## Mise en page

- **Rail latéral** à partir de 720 px, barre en bas en dessous.
- Sur PC, les encadrés côte à côte prennent la hauteur du plus grand
  (`IntrinsicHeight`) ; sur téléphone ils s'empilent.
- Les boutons de mode (Découvrir / Ma liste / Sur le disque) passent sur deux
  lignes sous 520 px ; les libellés se tronquent plutôt que de déborder.

## Souris

- `SmoothWheelBinding` (`smooth_wheel.dart`) adoucit la molette : un cran
  devient un court défilement fluide, au lieu d'un saut.
- `AppScrollBehavior` autorise le glisser à la souris sur les listes.
- `HorizontalScroller` convertit la molette verticale en défilement
  horizontal sur les rangées.

## Rester fluide

- **Listes virtualisées à hauteur fixe** : `SliverFixedExtentList` avec une
  hauteur calculée d'après la taille de police du système
  (`ReleaseRow.extent`, `_TorrentRow.extent`). Une ligne ne déborde jamais,
  même avec un texte agrandi sur Android (test `row_layout_test.dart`).
- **Tuiles PC** : hauteur calculée d'après la largeur de colonne et la taille
  du texte (`ReleaseTile.height`).
- **Transferts** : seuls la liste et le bloc des vitesses suivent les
  rafraîchissements de 2 s ; les lignes d'un torrent inchangé sont
  réutilisées (même objet `Torrent`). Mesuré : 1 163 éléments reconstruits
  par rafraîchissement avant, 154 après.
- **Affiches** à la taille affichée (`w154` / `w185` en liste, `w342` en
  grille), décodées à cette taille (`memCacheWidth`), en cache.
- **Pas d'info-bulle dans les lignes** : coûteux par élément, et sur mobile
  elle capterait l'appui long.
- **Index précalculés** : la base « Sur le disque » indexe infohash, noms de
  fichiers et titres, pour que chaque tuile des Sorties sache instantanément
  si le titre est déjà là.
- **Vidéo** : l'image est produite à la taille de l'écran (pas de 4K pour un
  écran 1080p) ; sous Linux, le module vidéo corrigé garde le rendu sur le GPU.
