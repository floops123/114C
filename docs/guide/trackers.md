# Trackers

[← Sommaire](../README.md)

L'onglet **Trackers** réunit les dernières sorties de **tous** les trackers
configurés (C411, tr4ker, Nostradamus, Draupnirr, AstraTorrent), toutes
catégories confondues. Films et séries sont **regroupés par titre** et
illustrés par TMDB.

## Une affiche par titre

Les sorties d'un même titre sont réunies, quel que soit le tracker. Une sortie
C411 apporte son titre français **et** son titre original : les sorties des
autres trackers, nommées d'après l'un ou l'autre
(`Dune.Part.Two.2024.1080p…`), rejoignent la même affiche. Chaque groupe est
ensuite rattaché à sa fiche TMDB (affiche, titre français), mémorisée sur
l'appareil.

Chaque affiche indique :

- **Film** ou **Série**, et la meilleure résolution disponible ;
- l'année et le nombre de versions ;
- les trackers qui l'ont et le plus grand nombre de seeders ;
- en bas à droite, **▶** si le titre est déjà chez toi (notre base ou
  Jellyfin), sinon **⬇** pour choisir une version à télécharger.

Un clic sur l'affiche ouvre la [fiche complète](films-et-series.md#fiche-dun-titre)
du titre (ou ses versions s'il n'a pas de fiche TMDB).

Le reste (musique, livres, jeux, logiciels…) apparaît sortie par sortie, avec
l'affiche du tracker ou l'image de sa catégorie.

## Les versions

**⬇** ouvre la liste des versions, **rangées par tracker**, les meilleures
d'abord (profil C411, puis seeders). Chaque ligne montre le nom de la release,
ses étiquettes et ses chiffres, avec son bouton **⬇** (vers Transmission) —
et **▶** si cette version est déjà sur le disque.

| Étiquette | Signification |
|---|---|
| **SUR LE DISQUE** (vert) | déjà dans ta base, dans Jellyfin ou dans Transmission |
| **HC Pure**, **HC Opti**, **Optim**, **Compat** | profil de qualité C411 (ci-dessous) |
| `2160p`, `Remux`, `WEB-DL`… | résolution et source |
| `HDR`, `DV` | HDR10, HDR10+, Dolby Vision |
| `MULTI/VFF`… | langues |
| **FREELEECH** | le téléchargement ne compte pas dans ton ratio |
| **EXCLU** | exclusivité du tracker |

### Profils de qualité C411

| Profil | Pour qui |
|---|---|
| **Home Cinéma Pure** | source brute, zéro perte (REMUX, BDMV, ISO) |
| **Home Cinéma Optimisé** | encodage haute qualité (H.265, AV1), DV / HDR10+, audio sans perte si possible |
| **Optimisation** | fichiers légers en H.265, audio compressé, 5.1 maximum |
| **Compatibilité** | lecture universelle : 1080p H.264, stéréo, SDR |

### Télécharger

Le bouton **⬇** d'une version envoie la sortie à Transmission : l'application
récupère le `.torrent` (qui contient ta passkey) et l'ajoute. Un **appui long**
(ou clic droit) ouvre les options : dossier, étiquettes, priorité, démarrer en
pause.

## Trier, chercher, filtrer

- **Tri** (en haut à droite) : *Nouveautés* ou *Les plus seedées*.
- **Recherche** : interroge tous les trackers à la fois, résultats regroupés
  de la même façon.
- **Grille ou liste** (bouton en haut, choix mémorisé) : en liste, chaque
  titre est une carte façon Transferts — affiche, titre, trackers, puis
  qualité · versions · seeders · ancienneté, et le bouton ▶ ou ⬇.
- **Par tracker** : *Tous les trackers* ou un seul, avec le nombre de titres
  de chacun. Avec un seul tracker, versions, qualité et seeders ne portent
  que sur lui.
- **Catégories** : *Tout*, *Films*, *Séries*, *Animation*, *Documentaires*,
  *Musique*, *Livres*, *Jeux vidéo*, *Logiciels*… avec leur nombre ; seules
  celles présentes s'affichent. Elles sont communes à tous les trackers
  (d'après la fiche du tracker, sa sous-catégorie, puis le nom). Sur la même
  rangée, **Sur le disque** ou **À télécharger** (un second appui désactive
  le filtre). Avec *Sur le disque*, l'état de ta base s'affiche avec son bouton
  **Actualiser**.
- **Import en masse** (bouton **+** en haut à droite) : voir
  [Import en masse](import-en-masse.md).
- **Défilement infini** : la page suivante de chaque tracker se charge toute
  seule ; tirer vers le bas actualise.

Si un tracker ne répond pas, un bandeau le signale ; les autres restent
affichés.

## Souris (PC)

Défilement à la molette adouci, et glisser à la souris pour faire défiler.
Sur une rangée horizontale, **Maj + molette** la fait défiler de côté ; la
molette seule fait défiler la page.
