# Nouveautés (veille des trackers)

[← Sommaire](../README.md)

L'application peut relever les trackers à intervalle régulier et te
prévenir quand de nouveaux torrents sortent. Les sorties repérées
s'accumulent dans la page **Nouveautés**, ouverte par le picto ✶ en haut
de l'onglet **Trackers** ; une pastille y compte celles que tu n'as pas
encore vues.

## Régler la veille

Les réglages sont en haut de la page Nouveautés et dans **Réglages →
Veille des nouveautés**. Ils s'appliquent tout de suite.

- **Vérifier les nouveaux torrents** : active ou coupe la veille.
- **Toutes les** : 5 min, 10 min, 15 min, 30 min, 1 h, 2 h ou 4 h. Chaque
  relevé coûte une requête par tracker surveillé (quota C411 : 120 par
  minute, largement suffisant).
- **Trackers surveillés** : par défaut tous les trackers configurés, y
  compris ceux que tu ajouteras plus tard. Décoche ceux qui ne
  t'intéressent pas.
- **Notification à l'arrivée** : une notification du système quand un
  relevé apporte des nouveautés (« 3 nouveaux torrents sur tr4ker »,
  avec les premiers noms). Sur Android 13 et plus, le système demande
  l'autorisation la première fois.

## Comment ça marche

- Chaque relevé lit la première page (50 sorties, les plus récentes) de
  chaque tracker surveillé. Une sortie jamais rencontrée entre dans la
  liste, en tête.
- **Premier relevé d'un tracker** : ses sorties remplissent la liste mais
  ne sont pas signalées comme nouvelles, pour éviter une avalanche de
  notifications.
- La liste garde les 300 dernières sorties. **Vider la liste** (menu ⋮)
  ne fait pas revenir les anciennes comme nouvelles.
- Ouvrir la page marque tout comme vu ; les nouveautés restent repérées
  (« NOUVEAU ») le temps de la visite.
- Chaque sortie porte une **vignette de couleur** selon son type (film,
  série, documentaire, animation, musique, livre, jeu vidéo, logiciel…) et
  sa **catégorie** telle que le tracker la range (« Jeux Vidéo › Windows »,
  « Movies/HD »). Des **filtres par type**, avec leur nombre de sorties,
  sont en tête de liste.
- ⬇ envoie la sortie à Transmission ; toucher la ligne ouvre son détail.
- Un tracker en échec est signalé en haut de la page ; les autres sont
  relevés normalement.

## Limites

La veille tourne **tant que l'application est ouverte** (au premier plan
ou réduite). Application fermée — ou mise en veille par Android après un
moment en arrière-plan — il n'y a pas de relevé : le suivant part dès la
réouverture si l'intervalle est écoulé.
