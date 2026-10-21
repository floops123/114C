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

- **Nom** : chaîne libre passée à la requête `q` / `name` de chaque
  tracker. Vide = « tout ce qui sort en ce moment ». Attention au quota
  C411 (120 requêtes / minute) : un nom trop courant peut vite
  consommer la fenêtre.
- **Trackers** : multi-sélection des trackers configurés. Par défaut tout
  est coché ; désélectionne un ou deux trackers pour limiter la
  recherche (utile pour ne pas payer le quota d'un tracker lent). Si
  tous les chips sont désélectionnés, la recherche ne renvoie rien —
  clique sur « Tous les trackers » pour revenir à l'état par défaut.
- **Catégorie** : multi-sélection des sous-catégories proposées par les
  trackers configurés (« Film », « Série », « FLAC » pour C411,
  « Movies/HD » pour un indexeur Torznab, « Films » pour AstraTorrent…).
  La liste est chargée à l'ouverture de la page et rechargée quand tu
  changes de trackers dans les Réglages ; en attendant elle est vide. Une
  sortie passe si elle est rangée dans l'une des catégories cochées, sur
  son tracker. Le filtre est insensible à la casse.
- **Taille min / max** : « 1,5 Go », « 700 Mo », « 2 To ». Tu peux
  saisir la virgule pour les décimales, omettre l'unité (= octets).
  Les suffixes reconnus : o, ko/k, mo/m, go/g, to/t, po/p. Une saisie
  invalide est ignorée (le champ devient rouge, et le filtre garde
  l'ancienne valeur) — la recherche ne se casse pas.
- **Seeders min / max** : entier, 0 = « inactif toléré ». Vide = pas de
  borne.
- **Leechers min / max** : idem.

- **Ordre** : *Plus petits* (par défaut), *Plus de seeders* ou *Plus
  récents*. C'est l'ordre dans lequel les trackers sont parcourus et
  les résultats affichés.

## Comment la recherche avance

Aucun indexer ne sait filtrer sur la taille ou les seeders : les bornes
sont appliquées par l'application. Mais l'**ordre** est demandé au
tracker quand il sait le faire, et c'est ce qui rend la recherche de
petits torrents efficace :

- **C411** trie lui-même par taille croissante : la recherche commence
  par les plus petits, et s'arrête pour ce tracker dès qu'une page
  dépasse la taille max. Avec une **taille min**, l'application saute
  directement à la bonne page (quelques requêtes, par dichotomie) au
  lieu de parcourir des centaines de fichiers de quelques Ko.
- **AstraTorrent** trie de même, sur ses 1 000 dernières sorties.
- **tr4ker, Nostradamus, Draupnirr** (Torznab) ne savent donner que les
  plus récentes : leurs pages sont parcourues dans cet ordre et filtrées.
- La **catégorie** est transmise au tracker quand elle y désigne une
  seule catégorie ou sous-catégorie (par exemple « Film » sur C411 ou
  « Movies/HD » sur un indexeur Torznab). Sinon elle est filtrée par
  l'application.

Les pages s'enchaînent toutes seules jusqu'à environ 50 résultats
retenus (au plus 10 pages par tracker d'un coup) ; le compteur « sur N
examinés » montre ce qui a été parcouru. **Encore** (ou **Chercher plus
loin**, ou faire défiler jusqu'en bas) reprend là où on s'est arrêté ;
**Stopper** interrompt sans perdre ce qui a été trouvé.

**Filtrer l'existant** applique les champs modifiés aux résultats déjà
affichés, sans réinterroger les trackers.

## L'envoi

Chaque ligne a une case cochée par défaut, sauf les torrents **déjà dans
Transmission** (signalés « DANS TRANSMISSION »). **Tout cocher / Tout
décocher** en tête, et un bouton **Envoyer à Transmission (n · taille)**
qui envoie d'un coup toutes les lignes cochées et rappelle leur taille
totale. Avant l'envoi, une boîte de dialogue
récapitule le nombre de torrents qui vont partir. Les envois sont
séquentiels (un par un), et les échecs restent affichés sur leur ligne
(« ÉCHEC » rouge, motif en dessous). Transmission est rafraîchie en
bloc à la fin.

Un torrent déjà envoyé est barré dans la liste : la ligne reste là
pour info, mais la case est désactivée. Si tu changes les bornes et
relances la recherche, les anciens « ENVOYÉ » sont gardés tant que la
même sortie est rechargée.

## Sécurité et quotas

- Le bouton « Rechercher » consomme une page de chaque tracker à la
  fois, pas un appel global. Sur C411, c'est 120 requêtes par minute
  par clé : un import de 10 pages × 5 trackers = 50 requêtes, à étaler.
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