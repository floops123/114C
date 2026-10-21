# Rendement Zen

[← Sommaire](../README.md)

Depuis l'onglet **C411**, le bouton **Rendement Zen** ouvre deux vues : ce
que rapporte chaque torrent que tu partages, et ce qu'il serait rentable
d'ajouter. Les règles sont celles de la classe **Swarm Keeper** (« payée sur
le seed »), telles que le site les publie.

## Les règles

Chaque nuit, pour la veille :

```
Zen par jour = Σ coefficient de poids × note × (1 + bonus) ÷ 7
```

arrondi au Zen près, chaque torrent compté au prorata de la part de la
journée où il a été partagé (rien en dessous de 30 minutes). Le site l'écrit
« Σ poids × indicateur de contribution » : l'**indicateur de contribution**
est la moyenne des notes **pondérée par le poids** (un gros torrent y compte
plus qu'un petit), ce qui revient au même. Chaque torrent rapporte donc
selon sa propre note : un torrent mal noté rapporte peu, mais ne retire rien
aux autres.

- **Note** = catégorie (1,00) + durée de seed + taille × seeders, 2,00 au
  plus :
  - **durée de seed** cumulée sur ce torrent : +0,10 dès 7 j, +0,25 dès
    30 j, +0,35 dès 90 j, +0,50 dès 180 j ;
  - **taille × seeders actifs** : jusqu'à +0,50 (10 à 50 Go avec 10 seeders
    au plus ; 50 Go et plus avec 50 au plus). Un petit torrent trop seedé
    n'apporte rien de plus que la catégorie.
- **Coefficient de poids** : 1 pour 4 Go ; (0,25 Go + taille) ÷ 4,25 Go en
  dessous ; il monte lentement au-delà (1,24 à 25 Go, 1,38 à 60 Go). Ici
  1 Go = 10⁹ octets.
- **Bonus** : la grille (jusqu'à +25 %, atteint dès 400 torrents seedés) et
  l'arbre de progression (+1 % pour 100 torrents notés au moins 1,50,
  jusqu'à +5 % pour 300 torrents à 2,00).

Conséquences : les torrents **peu seedés** rapportent, **10 à 50 Go** est
le meilleur rapport par torrent, les **petits** le meilleur par Go stocké,
et **garder** ses torrents fait monter leur note.

Le Zen vient aussi des **niveaux d'XP** : chaque niveau terminé verse de 1 à
27 Zen selon le niveau (la carte du compte affiche ce que paiera le niveau
en cours).

## Portefeuille

Pour chaque torrent C411 de Transmission (reconnu à son tracker) : taille,
seeders (donnés par le tracker), durée de seed, note, coefficient de poids
et Zen par jour, avec le **prochain palier** (« +0,10 dans 3 j ») et les
torrents **trop seedés**. En tête : le total estimé pour une journée
complète (et arrondi), à comparer au versement de la nuit et à
l'estimation du site, la note moyenne pondérée et le coefficient moyen (et
ceux du site), le bonus, l'avancement de l'arbre de progression, et les
paliers de la semaine.

Avec le cookie de session, la **note de chaque torrent vient du site**
(« note … (site) »), avec les Zen qu'il lui projette ce soir et la part de
la journée où il a été partagé ; sinon elle est calculée depuis
Transmission. Le reste est un calcul local : l'écart avec le site vient
surtout de la part de la journée réellement partagée.

## Opportunités

- **Sans rien télécharger de plus** : les sorties C411 dont tu as déjà les
  fichiers (**cross-seed**) et les **réanimations à prime** (soins
  palliatif : prime de 5 à 40 Zen partagée entre les 3 premiers
  réanimateurs, +50 % sur la part d'un Swarm Keeper, après 72 h de partage ;
  et le torrent est noté comme peu seedé). Les gains s'affichent une fois l'analyse lancée depuis
  ces pages.
- **À télécharger puis partager** : **Chercher** parcourt les sorties C411
  qui ont 1 à 50 seeders (les sorties sans seeder sont sautées) et estime
  chacune **en te comptant parmi les seeders**. Classement **par torrent**
  (si c'est le nombre de torrents qui te limite), **par Go** (si c'est
  le disque) ou **par note** (ta note moyenne est ton indicateur de
  contribution, et l'arbre de progression compte les torrents bien notés ;
  à note égale, le plus rentable d'abord). La sélection se fait d'elle-même dans tes limites : nombre de
  torrents, place disque, **budget de ratio** — la *marge de
  téléchargement* du site : upload (crédit de téléchargement compris) ÷ 0,8
  − download, ce que tu peux télécharger avant le blocage ; le freeleech ne
  compte pas — et au besoin **freeleech seulement**. Les tailles et la
  place disque sont en Go du site (base 1024). **Ajouter** envoie la sélection à
  Transmission.

L'import en masse propose aussi l'ordre **Plus rentables** et affiche
« ≈ x Zen/j » sur les sorties C411.
