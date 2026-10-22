# Transferts

[← Sommaire](../README.md)

L'onglet **Transferts** pilote ton serveur Transmission, en direct.

## La liste

- **Résumé en haut** : vitesse de réception, vitesse d'envoi, nombre de
  torrents actifs.
- **Rafraîchissement toutes les 2 s** ; seuls les torrents modifiés sont
  redemandés au serveur.
- **Actualisation auto** : décochée, Transmission n'est plus relu toutes les
  2 s (utile avec des milliers de torrents ou une connexion lente) ; le
  bouton ⟳ à côté relit la liste, qui se met aussi à jour après chaque
  action.
- **Afficher** : 50, 100, 200 (par défaut), 500, 1000 torrents ou Tout — les
  premiers selon le tri et les filtres. Le pied de liste indique combien
  sont masqués, avec **Tout afficher**. Les deux réglages sont mémorisés.
- **Filtres** (avec leur nombre) : tous, actifs, en cours, en partage,
  terminés, en file, arrêtés, bloqués, en erreur — et filtre par
  **étiquette**.
- **Recherche** par nom.
- **12 tris**, croissant ou décroissant, mémorisés : ajout, nom, état, file,
  progression, temps restant, vitesse de réception, vitesse d'envoi, pairs,
  ratio, volume envoyé, taille.

Chaque carte montre le nom, l'état (en couleur), la progression, les vitesses,
le ratio et le temps restant.

## Agir sur les torrents

- **Un torrent** : menu ⋮ ou clic droit.
- **Plusieurs** : appui long pour entrer en sélection, puis *Tout
  sélectionner*, *Démarrer*, *Arrêter*…
- **Tout démarrer / tout arrêter** depuis le menu de la page.

Actions disponibles : démarrer, démarrer maintenant (hors file), arrêter,
vérifier, réannoncer, monter / descendre dans la file, déplacer les fichiers,
étiquettes, priorité, copier le lien magnet, supprimer (avec ou sans les
données).

## Ajouter un torrent

Bouton **+** :

- **fichiers `.torrent`** de l'appareil (plusieurs à la fois ; chacun est
  vérifié avant l'envoi : nom, taille, fichier invalide signalé) ;
- **lien magnet** ou **URL** ;
- options : dossier, étiquettes, priorité, démarrer en pause.

Depuis un tracker, c'est le bouton ⬇ d'une version dans la vue
[Trackers](trackers.md#télécharger).

## Le détail d'un torrent

Cinq onglets :

| Onglet | Contenu |
|---|---|
| Infos | progression, carte des pièces, transfert, origine des pairs (tracker, DHT, PEX…), dates, créateur, hash, courbe de vitesse sur 15 min |
| Fichiers | sélection, priorité par fichier, renommage, jauge de progression par fichier |
| Pairs | client, progression, vitesses, chiffrement, µTP, connexion entrante |
| Trackers | annonces, scrapes, paliers, modification de la liste |
| Options | priorité, limites de vitesse, groupe de bande passante, ratio et inactivité propres, nombre de pairs |

## Statistiques

Icône 📈 de la page :

- vitesses actuelles, volumes envoyés et reçus (session et total), ratio
  global ;
- courbe des vitesses sur 5, 15 ou 30 min, avec réticule, moyenne et pic ;
- classement des torrents par volume envoyé ou reçu, ratio ou vitesse.

Transmission ne garde aucun historique : les courbes sont enregistrées par
l'application pendant qu'elle est ouverte, à partir du rafraîchissement
habituel (aucune requête en plus).

## Le serveur

**Réglages → Serveur Transmission** donne accès à toute la configuration du
daemon (`session-set`) :

- dossiers, fichiers incomplets ;
- limites de vitesse, mode tortue et sa planification (heures, jours) ;
- files d'attente, ratio et inactivité ;
- port, chiffrement, protocoles, DHT / PEX / LPD, blocklist ;
- trackers par défaut, scripts, protection anti-force brute.

Seules les options que ton serveur connaît sont affichées (Transmission 3.x à
4.1), une recherche permet de les retrouver, et seules les modifications sont
envoyées.

Outils : test du port, mise à jour de la blocklist, espace disque, statistiques
cumulées, **groupes de bande passante**, arrêt du daemon.

## Les autres pages du menu ⋮

- [Cross-seed](cross-seed.md#cross-seed) : partager tes torrents terminés sur
  les autres trackers.
- [Sans seeder](cross-seed.md#sans-seeder) : relancer les sorties mortes.
