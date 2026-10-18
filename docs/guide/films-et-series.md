# Films & séries

[← Sommaire](../README.md)

L'onglet **Films & séries** part de **TMDB** : les titres du moment, ta liste
de souhaits, et pour chacun ce que tu peux en faire — le **lire** s'il est
déjà chez toi, le **télécharger** s'il est sur un tracker. Il demande une
[clé TMDB](configuration.md#tmdb).

Deux boutons en haut de la page :

| Bouton | Contenu |
|---|---|
| **Découvrir** | des rangées thématiques tournées vers les sorties françaises |
| **Ma liste** | tes souhaits, avec leur nombre |

La barre de recherche interroge TMDB (films et séries) ; une recherche en cours
s'affiche à la place des deux vues.

## Lire ou télécharger depuis une affiche

Chaque affiche porte, en bas à droite :

| Pastille | Signification | Au clic |
|---|---|---|
| **▶** vert | déjà chez toi (notre base, ou Jellyfin) | lecture, ou liste des épisodes |
| **⬇** bleu | disponible sur au moins un tracker | résultats de recherche sur les trackers |
| rien | pas encore trouvé, ou en cours de vérification | — |

La disponibilité est **vérifiée à l'affichage**, sans surcharger les trackers :

- au plus deux recherches par titre (titre français, puis original) ;
- arrêt dès qu'un tracker a le titre, les trackers les moins sollicités
  d'abord et C411 (quota de 120 requêtes / minute) en dernier ;
- les requêtes sont espacées, les films pas encore sortis ne sont pas
  vérifiés ;
- le résultat est **mémorisé 12 h**.

Les pastilles apparaissent donc au fil de l'eau, les premières secondes.

## Filtrer

Sous la recherche : **Tout / Sur le disque / À télécharger**. Le filtre
s'applique aux rangées, à Ma liste, à la recherche et aux pages « Tout voir ».

- **Sur le disque** ajoute en tête une rangée **Ta vidéothèque** avec tout ce
  que tu possèdes (voir [Sur le disque et lecture](sur-le-disque.md)), et
  l'état de la base avec son bouton **Actualiser**.
- **À télécharger** ne garde que les titres trouvés sur un tracker et absents
  du disque ; la vérification des titres affichés est lancée aussitôt.

## Découvrir

Rangées défilant horizontalement, inspirées de Seerr :

- Tendances de la semaine
- Au cinéma en France · Bientôt au cinéma en France
- Récemment sortis en VOD en France · Films français à venir
- Films populaires
- Séries tendance · Séries en cours de diffusion · Séries françaises
- Une rangée par **genre**

« Tout voir » ouvre la liste complète d'une rangée, chargée au fil du
défilement.

## Ma liste

Chaque souhait affiche son affiche, son type, sa date la plus utile et ce que
tu possèdes déjà :

- **Date** : pour un film, la sortie en salles en France si elle est à venir,
  sinon la VOD française, à défaut la date mondiale. Les dates françaises sont
  relues une fois par jour.
- **Pastilles** : *Sur le disque*, *Dans Jellyfin*, *Téléchargé*,
  *En cours 42 %* ;
- à droite, la pastille ▶ / ⬇ décrite plus haut.

## Fiche d'un titre

<p align="center">
  <img src="../images/fiche-titre.png" alt="Fiche d'un titre" width="820">
</p>

- Image de fond, affiche, titre original, durée, note, genres.
- Boutons : **Lire** / **Épisodes** (si tu l'as déjà), **Ajouter à la liste**,
  **Chercher sur les trackers**, **Bande-annonce**.
- Trois encadrés, côte à côte sur PC :
  - **Déjà chez toi** : fichiers de ta base (versions, tailles), élément
    Jellyfin, torrents dans Transmission (téléchargés ou en cours, avec leur
    progression) ;
  - **Sorties en France** (films) : cinéma, VOD, DVD / Blu-ray ;
  - **Sur les trackers** : pour chacun, le nombre de sorties, la meilleure
    qualité, HDR, Atmos, langues, seeders max, freeleech. Lancée d'office
    pour un titre sorti, à la demande pour un titre à venir.
- Accroche, synopsis, réalisation, scénario.
- Pour une série : **ses saisons et épisodes sur le disque**, directement dans
  la fiche.
- Distribution et recommandations, en rangées.

## Chercher sur les trackers

**Chercher sur les trackers** (ou un clic sur une ligne de « Sur les
trackers ») ouvre les résultats, **un onglet par tracker** avec le nombre de
résultats.

<p align="center">
  <img src="../images/recherche-grille.png" alt="Résultats en grille" width="820">
</p>

- La recherche essaie le titre français et le titre original, et écarte les
  sorties d'un autre titre ou d'une autre année.
- **Tri** (menu en haut) :

  | Tri | Effet |
  |---|---|
  | Pertinence | ordre du tracker |
  | Qualité | groupes 2160p, 1080p, 720p… avec intertitres |
  | Profil C411 | groupes par profil, avec leur description |
  | Taille, Seeders, Date | ordre simple |

- **Grille ou liste** : bouton en haut, choix mémorisé.

<p align="center">
  <img src="../images/recherche-liste.png" alt="Résultats en liste sur téléphone" width="320">
</p>
