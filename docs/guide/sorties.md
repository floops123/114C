# Sorties

[← Sommaire](../README.md)

L'onglet **Sorties** montre les dernières sorties de chaque tracker configuré.

## Choisir un tracker

En haut de la page, un bouton par tracker (C411, tr4ker, Nostradamus,
AstraTorrent). Le dernier choisi est mémorisé.

## Parcourir

- **Grille ou liste** : bouton en haut à droite (le choix vaut aussi pour les
  résultats de recherche des souhaits).
  - En grille sur PC, des tuiles avec affiche et infos ; sur téléphone, trois
    colonnes d'affiches.
  - En liste, une carte par sortie : titre, nom complet de la release,
    étiquettes, puis taille · seeders · leechers · date.
- **Défilement infini** : la page suivante se charge toute seule.
- **Recherche par nom**, **catégories** et **sous-catégories** (avec un picto
  par type de contenu).
- **Tri** : date, seeders, leechers, téléchargements, taille, nom,
  commentaires — croissant ou décroissant, mémorisé. C411 trie côté serveur ;
  pour les trackers Torznab, qui ne savent pas trier, le tri s'applique aux
  résultats déjà chargés.

Sans affiche, une image illustre le type de contenu (film, série, musique,
livre, jeu, logiciel…).

## Lire une ligne

| Étiquette | Signification |
|---|---|
| **SUR LE DISQUE** (vert) | le titre est déjà dans ta base ou dans Transmission |
| **HC Pure**, **HC Opti**, **Optim**, **Compat** | profil de qualité C411 (voir ci-dessous) |
| `2160p`, `Remux`, `WEB-DL`… | résolution et source |
| `HDR`, `DV` | HDR10, HDR10+, Dolby Vision |
| `MULTI/VFF`… | langues |
| `FL`, **FREELEECH** | le téléchargement ne compte pas dans ton ratio |
| **EXCLU** | exclusivité du tracker |

Les seeders sont en vert, ou en **rouge** quand il n'y en a aucun.

### Profils de qualité C411

| Profil | Pour qui |
|---|---|
| **Home Cinéma Pure** | source brute, zéro perte (REMUX, BDMV, ISO) |
| **Home Cinéma Optimisé** | encodage haute qualité (H.265, AV1), DV / HDR10+, audio sans perte si possible |
| **Optimisation** | fichiers légers en H.265, audio compressé, 5.1 maximum |
| **Compatibilité** | lecture universelle : 1080p H.264, stéréo, SDR |

Le profil est déduit des infos techniques du tracker, ou à défaut du nom de la
release.

## Télécharger

Le bouton **⬇** envoie la sortie à Transmission : l'application récupère le
`.torrent` (qui contient ta passkey) et l'ajoute. Un **appui long** (ou clic
droit) ouvre les options : dossier, étiquettes, priorité, démarrer en pause.

Quand le titre est déjà sur le disque, un bouton **▶** permet de le lire
aussitôt (ou d'ouvrir ses épisodes pour une série).

## Fiche d'une sortie

Un clic sur une sortie ouvre sa fiche : affiche, synopsis, casting, détails
techniques, état « sur le disque » et boutons Lire / Télécharger.

## Souris et clavier (PC)

- Défilement à la molette **adouci**, et glisser-déposer à la souris pour
  faire défiler les listes et les rangées.
- Sur les rangées horizontales, la molette fait défiler de gauche à droite.
