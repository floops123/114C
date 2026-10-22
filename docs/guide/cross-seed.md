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

Deux autres boutons cherchent les palliatifs **sans passer par un autre
tracker**, là où leurs fichiers sont peut-être déjà. Ce qui correspond est
ajouté tout de suite.

- **Dans Transmission** : compare chaque palliative aux torrents terminés
  de Transmission. Si l'un a exactement les mêmes fichiers (chemins et
  tailles), le `.torrent` C411 est ajouté en **cross-seed** dans le même
  dossier (étiquette « cross-seed »). Rien n'est téléchargé.
- **Sur mon ordinateur** (version de bureau) : choisis un dossier ;
  l'application y cherche les fichiers de chaque palliative.
  - **Comparaison** : même taille, mêmes chemins sous un dossier (son nom
    peut différer), puis les empreintes du premier et du dernier morceau,
    comme le ferait le client. Un fichier de même taille mais différent est
    donc écarté.
  - **Transmission sur le serveur** (cas d'une seedbox) : les fichiers
    partent par **FTP** dans le dossier de téléchargement de Transmission,
    aux chemins du torrent. Le `.torrent` C411 est ensuite ajouté :
    Transmission vérifie les données et repart en partage. La ligne affiche
    la progression de l'envoi.
  - **Transmission sur cet ordinateur** (adresse `localhost` ou
    `127.0.0.1`) : rien n'est envoyé. Le torrent est ajouté dans le dossier
    où sont les fichiers, renommé s'ils ont un autre nom, vérifié puis
    relancé.

Dans les deux cas, le `.torrent` C411 n'est téléchargé que pour les
palliatives dont la taille correspond à un fichier, un dossier ou un torrent
déjà là. Les autres passent en *Aucune correspondance* sans requête.

L'envoi par FTP demande l'accès FTP dans les Réglages et la correspondance
des chemins Transmission → FTP. Celle-ci est établie par un premier parcours
de la vidéothèque (*Films & séries › Sur le disque › Actualiser*).

## Reseed (version de bureau)

Des fichiers déjà sur ton appareil (un ancien disque, une sauvegarde, un
partage réseau) peuvent repartir en partage sans rien retélécharger. Menu ⋮
de **Transferts › Reseed…**.

1. **Choisis un dossier.** Chaque fichier et chaque dossier qu'il contient
   est cherché ; coche *Aussi le contenu des sous-dossiers* pour un dossier
   qui regroupe des sorties (« Films », « Séries »).
2. **Choisis le tracker** où chercher.
3. **Indique ce dossier vu par Transmission** :
   - Transmission sur cet appareil : le même chemin, rempli tout seul ;
   - Transmission ailleurs : son chemin à lui, par exemple le dossier d'un
     NAS ou d'un partage monté des deux côtés. Il doit voir ces fichiers.
4. **Rechercher.** Une sortie correspond si elle a le même nom (sans
   extension), la même taille, les mêmes fichiers (chemins et tailles), et
   les mêmes empreintes pour le premier et le dernier morceau. Si un
   fichier a la même taille mais d'autres données, la ligne affiche
   *Fichiers différents*.
5. **Ajouter à Transmission** les correspondances cochées. Chaque torrent :
   - est ajouté **en pause** dans le dossier qui contient le fichier ou le
     dossier (étiquette « reseed »), et renommé si ton fichier porte un
     autre nom que dans le torrent ;
   - est **vérifié** par Transmission, avec la progression affichée ;
   - **repart en partage seulement si les données sont complètes à 100 %**.
     Sinon, il reste en pause avec le pourcentage trouvé, souvent signe
     d'un mauvais chemin : rien n'est retéléchargé.
