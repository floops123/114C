# Rendement Zen

[← Sommaire](../README.md)

Depuis l'onglet **C411**, le bouton **Rendement Zen** ouvre deux vues : ce
que rapporte chaque torrent que tu partages, et ce qu'il serait rentable
d'ajouter. Les règles sont celles de la classe **Swarm Keeper** (« payée sur
le seed »), telles que le site les publie.

## Les règles

Chaque nuit, pour la veille :

```
Zen par jour = Σ coefficients de poids × note moyenne × (1 + bonus) ÷ 7
```

arrondi au Zen près, chaque torrent compté au prorata de la part de la
journée où il a été partagé (30 minutes au moins). La **note moyenne** est
l'indicateur de contribution : elle multiplie le poids de **tous** tes
torrents. Un torrent noté sous ta moyenne la fait baisser pour les autres,
et peut coûter plus qu'il ne rapporte (un petit torrent à 1,20 dans un
portefeuille à 1,50 de moyenne, par exemple) ; un torrent bien noté la fait
monter.

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
le meilleur rapport par torrent, et **garder** ses torrents fait monter
leur note. Les **petits** torrents (moins de 1 Go : +0,20 au plus) tirent la
note moyenne vers le bas : ils ne paient que si ta moyenne est basse.

Le Zen vient aussi des **niveaux d'XP** : chaque niveau terminé verse de 1 à
27 Zen selon le niveau (la carte du compte affiche ce que paiera le niveau
en cours).

## Portefeuille

Pour chaque torrent C411 de Transmission (reconnu à son tracker) : taille,
seeders (donnés par le tracker), durée de seed, note, coefficient de poids
et **contribution** : ce que le versement perdrait sans lui, effet sur la
note moyenne compris (pour un torrent à l'arrêt, ce qu'il rapporterait
relancé). Sont signalés le **prochain palier** (« +0,10 dans 3 j »), les
torrents **trop seedés** et ceux qui **baissent la note moyenne** (leur
contribution est négative ; leur note monte avec la durée de seed). En
tête : le total estimé pour une journée complète, à comparer au versement de la nuit et à l'estimation du site, la
note et le coefficient moyens (et ceux du site), le bonus, l'avancement de
l'arbre de progression, et les paliers de la semaine.

C'est un calcul local : l'écart avec le site vient surtout de la part de la
journée réellement partagée et du nombre de seeders, que le site et le
tracker ne comptent pas forcément au même moment.

## Opportunités

- **Sans rien télécharger de plus** : les sorties C411 dont tu as déjà les
  fichiers (**cross-seed**) et les **réanimations à prime** (soins
  palliatif : prime de 5 à 40 Zen partagée entre les 3 premiers
  réanimateurs, +50 % sur la part d'un Swarm Keeper, après 72 h de partage ;
  et le torrent est noté comme peu seedé). Les gains s'affichent une fois l'analyse lancée depuis
  ces pages.
- **À télécharger puis partager** : **Chercher** parcourt les sorties C411
  qui ont 1 à 50 seeders (les sorties sans seeder sont sautées) et estime
  chacune **en te comptant parmi les seeders** et **en l'ajoutant à ton
  portefeuille** (celui du dernier versement du site) : le gain affiché
  tient compte de l'effet sur ta note moyenne, et une sortie qui la ferait
  trop baisser est signalée et n'est pas cochée. Classement **par torrent**
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
