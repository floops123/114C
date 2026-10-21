# Import en masse

[← Sommaire](../README.md)

L'onglet **Trackers** a un picto **+** en haut à droite qui ouvre une
page dédiée à l'import en masse : tu donnes un nom (optionnel) et des
bornes, les trackers cherchent et l'application te montre tout ce qui
passe, tu coches, et l'envoi part en une fois à Transmission.

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
  trackers configurés (« Film », « Série », « FLAC »…). La liste est
  chargée à l'ouverture de la page (en tâche de fond) ; en attendant
  elle est vide. Le filtre est insensible à la casse.
- **Taille min / max** : « 1,5 Go », « 700 Mo », « 2 To ». Tu peux
  saisir la virgule pour les décimales, omettre l'unité (= octets).
  Les suffixes reconnus : o, ko/k, mo/m, go/g, to/t, po/p. Une saisie
  invalide est ignorée (le champ devient rouge, et le filtre garde
  l'ancienne valeur) — la recherche ne se casse pas.
- **Seeders min / max** : entier, 0 = « inactif toléré ». Vide = pas de
  borne.
- **Leechers min / max** : idem.

Les bornes **s'appliquent côté client** : aucun indexer ne sait filtrer
sur les seeders ou la taille, et l'avantage est qu'elles couvrent tous les
trackers à la fois. C'est pour ça qu'on plafonne à 10 pages par tracker
(500 sorties par tracker, donc 2 500 sur cinq trackers) — au-delà, on
vous le dit (« Encore » pour charger la suite).

## L'envoi

Chaque ligne a une case cochée par défaut. **Tout cocher / Tout décocher**
en tête, et un bouton **Envoyer à Transmission (n)** qui envoie d'un
coup toutes les lignes cochées. Avant l'envoi, une boîte de dialogue
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