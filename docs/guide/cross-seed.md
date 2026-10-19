# Cross-seed et sans seeder

[← Sommaire](../README.md)

Deux outils pour **partager plus sans retélécharger**, dans le menu ⋮ de
l'onglet Transferts.

## Cross-seed

Le principe : une même release est souvent publiée sur plusieurs trackers. Si
tu l'as déjà, il suffit d'ajouter le `.torrent` de l'autre tracker **dans le
même dossier** : Transmission vérifie les données, les trouve complètes, et
partage aussitôt. Ton ratio grimpe sur deux trackers pour le prix d'un
téléchargement.

### Comment l'application cherche

1. Pour chaque torrent **terminé**, elle reconnaît son tracker d'origine
   d'après les URL d'annonce.
2. Elle cherche la release par son nom sur les autres trackers.
3. Elle garde les candidats **de même taille à l'octet près**.
4. Elle télécharge le `.torrent` du candidat et compare **fichier par
   fichier** (chemins et tailles).
5. Les torrents déjà présents dans Transmission sont reconnus par leur
   infohash et ignorés.

AstraTorrent a son propre scanner : l'application lui envoie tes torrents
terminés par lots (nom, taille, infohash) et il renvoie ses correspondances.

### Choisir les sens

En haut de la page, deux groupes de pastilles :

- **Torrents venant de** : les trackers d'origine à analyser (plus une
  pastille pour les torrents d'autres trackers ou publics) ;
- **À partager sur** : les trackers où chercher.

Par exemple, *venant de C411* et *à partager sur tr4ker* seulement. Un
tracker ajouté plus tard est inclus d'office.

### Ajouter

**Ajouter** (une correspondance) ou **Tout ajouter** : le torrent est ajouté
dans le dossier des données existantes, avec l'étiquette `cross-seed`.

### Courtoisie envers les trackers

- une requête à la fois, avec une pause de 1,1 s (quota C411 :
  120 requêtes / minute) ;
- les résultats *introuvable*, *fichiers différents* et *déjà partagé* sont
  mémorisés **7 jours** — *Tout réanalyser* les ignore.

## Sans seeder

Le principe inverse : des sorties d'un tracker n'ont **plus aucun seeder**,
mais la même release vit encore ailleurs. On la télécharge depuis le tracker
où elle est seedée, puis on ajoute le `.torrent` du tracker d'origine sur les
mêmes données : la sortie morte retrouve un seeder (toi).

1. Choisis le tracker d'origine (C411 par défaut) et une **catégorie**.
2. L'application liste ses sorties sans seeder et cherche chacune (même nom,
   même taille) sur les trackers choisis.
3. Pour chaque sortie retrouvée, la copie **la plus seedée** est proposée :
   **Télécharger**, ou **Tout télécharger**.
4. Une fois le téléchargement terminé, le `.torrent` du tracker d'origine est
   ajouté automatiquement dans le même dossier, sans rien faire de ton côté.

La progression de chaque relance est suivie dans la page ; l'analyse peut
être arrêtée à tout moment.

### Soins palliatif (onglet C411)

C411 maintient sa propre liste des sorties sans seeder depuis un certain
temps (sorties « palliatives » : à sauver avant qu'elles ne disparaissent).
L'onglet **Soins palliatif** de la même page les reprend et applique le
même flux : recherche de la copie (nom + taille) sur les autres trackers,
téléchargement de la plus seedée, puis réinjection du `.torrent` C411
une fois terminé.

Le cookie de session C411 (Réglage *Cookies de session*) est requis pour
lire cette liste : c'est lui qui autorise l'endpoint `/api/torrents` avec
le filtre `palliative=only`. La catégorie n'est pas filtrée — la liste
vient du site, classée par *bounty* décroissant.

1. Configure le cookie si ce n'est pas déjà fait (l'onglet affiche alors un
   message d'erreur).
2. Choisis les trackers où trouver les palliatifs, et un nombre pour limiter
   la liste (sinon, la première page entière — les suivantes sont chargées
   à la demande).
3. Pour chaque palliative, les copies trouvées sont listées sous le titre
   (une ligne par tracker, avec le nombre de seeders) ; la copie la plus
   seedée est téléchargeable par **Télécharger**.
