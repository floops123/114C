# Import en masse

[← Sommaire](../README.md)

L'onglet **Trackers** a un picto **+** en haut à droite qui ouvre une
page dédiée à l'import en masse : tu donnes un nom (optionnel) et des
bornes, les trackers cherchent et l'application te montre tout ce qui
passe, tu coches, et l'envoi part en une fois à Transmission.

Son usage premier : **lister les petits torrents**. Choisis une taille
max (raccourcis ≤ 50 Mo, ≤ 200 Mo, ≤ 500 Mo, ≤ 1 Go, ≤ 4 Go sous les
champs de taille), laisse l'ordre sur **Plus petits**, et lance la
recherche.

## Les filtres

- **Nom** : chaîne libre passée à la requête `q` / `name` du tracker.
  Vide = « tout ce qui sort en ce moment ».
- **Tracker** : **un seul à la fois**, parmi ceux configurés (le premier
  par défaut). Chaque tracker a ses propres catégories, avec ses propres
  identifiants : changer de tracker remplace la liste des catégories et
  vide celles cochées, ainsi que les résultats.
- **Catégorie** : les catégories du tracker choisi, telles qu'il les
  décrit (« Films & Vidéos » puis « Film », « Série »… pour C411,
  « Movies » puis « Movies/HD »… pour un indexeur Torznab, « Films »,
  « Séries »… pour AstraTorrent). Chaque ligne commence par la catégorie
  entière, suivie de ses sous-catégories. Aucune cochée = toutes. Les
  catégories cochées sont **transmises au tracker** : c'est lui qui
  filtre, avec ses identifiants.
- **Taille min / max** : « 1,5 Go », « 700 Mo », « 2 To ». Tu peux
  saisir la virgule pour les décimales, omettre l'unité (= octets).
  Les suffixes reconnus : o, ko/k, mo/m, go/g, to/t, po/p. Une saisie
  invalide est ignorée (le champ devient rouge, et le filtre garde
  l'ancienne valeur) — la recherche ne se casse pas.
- **Seeders min / max** : entier, 0 = « inactif toléré ». Vide = pas de
  borne.
- **Leechers min / max** : idem.

- **Ordre** : *Plus petits* (par défaut), *Plus de seeders* ou *Plus
  récents*. C'est l'ordre dans lequel le tracker est parcouru et les
  résultats affichés.

## Comment la recherche avance

Aucun indexer ne sait filtrer sur la taille ou les seeders : les bornes
sont appliquées par l'application. Mais l'**ordre** est demandé au
tracker quand il sait le faire, et c'est ce qui rend la recherche de
petits torrents efficace :

- **C411** trie lui-même par taille croissante : la recherche commence
  par les plus petits, et s'arrête dès qu'une page dépasse la taille
  max. Avec une **taille min**, l'application saute
  directement à la bonne page (quelques requêtes, par dichotomie) au
  lieu de parcourir des centaines de fichiers de quelques Ko.
- **AstraTorrent** trie de même, sur ses 1 000 dernières sorties.
- **tr4ker, Nostradamus, Draupnirr** (Torznab) ne savent donner que les
  plus récentes : leurs pages sont parcourues dans cet ordre et filtrées.
- Avec **plusieurs catégories cochées**, chacune fait l'objet de sa
  propre recherche (même ordre, même arrêt à la taille max), et les
  résultats sont réunis.

Les pages s'enchaînent toutes seules jusqu'à environ 50 résultats
retenus (au plus 10 pages d'un coup) ; le compteur « sur N
examinés » montre ce qui a été parcouru. **Encore** (ou **Chercher plus
loin**, ou faire défiler jusqu'en bas) reprend là où on s'est arrêté ;
**Stopper** interrompt sans perdre ce qui a été trouvé.

**Filtrer l'existant** applique les champs modifiés aux résultats déjà
affichés, sans réinterroger le tracker.

## L'envoi

Chaque ligne a une case cochée par défaut, sauf les torrents **déjà dans
Transmission** (signalés « DANS TRANSMISSION »). **Tout cocher / Tout
décocher** en tête, et un bouton **Envoyer à Transmission (n · taille)**
qui envoie d'un coup toutes les lignes cochées et rappelle leur taille
totale. Avant l'envoi, une boîte de dialogue
récapitule le nombre de torrents qui vont partir. Les envois sont
séquentiels (un par un) ; le bouton affiche où on en est (« Envoi 3 / 20… »).
Sur **C411**, si le cookie de session est renseigné dans les Réglages, les
`.torrent` sont pris sur le site avec ce cookie, sans attente entre deux
(la boîte de confirmation le précise) ; sans cookie, ils passent par la clé
API, espacés de 3 s. Sur les autres trackers, 2 s entre deux `.torrent`. Les échecs restent affichés sur leur ligne
(« ÉCHEC » rouge, motif en dessous). Transmission est rafraîchie en
bloc à la fin.

Un torrent déjà envoyé est barré dans la liste : la ligne reste là
pour info, mais la case est désactivée. Si tu changes les bornes et
relances la recherche, les anciens « ENVOYÉ » sont gardés tant que la
même sortie est rechargée.

## Sécurité et quotas

- Chaque tour consomme une page par catégorie cochée. Sur C411, c'est
  120 requêtes par minute par clé : 10 pages × 3 catégories = 30
  requêtes, sans compter les quelques requêtes de la dichotomie vers la
  taille min.
- Pas de connexion FTP : tout passe par les API trackers et par
  Transmission. Le serveur de fichiers n'est pas touché.
- Si Transmission n'est pas configurée, le bouton d'envoi le rappelle
  dans un message d'erreur.

## Pourquoi pas dans l'onglet Trackers

Les filtres de l'onglet Trackers (taille, seeders, leechers, catégorie)
n'existent pas aujourd'hui : on n'y a qu'un tri et un champ de
recherche. L'import en masse est volontairement séparé, pour ne pas
surcharger la vue principale et pour pouvoir travailler sur plusieurs
critères sans toucher à ce que tu regardais.