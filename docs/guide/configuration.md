# Configuration

[← Sommaire](../README.md)

Tout se règle dans l'onglet **Réglages**. Seuls Transmission et un tracker sont
indispensables ; chaque autre section ajoute une fonction et peut rester vide.

| Section | Indispensable ? | Débloque |
|---|---|---|
| Transmission | oui | Transferts, envoi des sorties, cross-seed |
| Trackers | au moins un | vue Trackers, téléchargements, disponibilité des titres |
| Cookie de session C411 | non | Notifications, Salon, Mon compte |
| TMDB | non | vue Films & séries, fiches, affiches des Trackers et de la base |
| Serveur de fichiers (FTP ou WebDAV) | non | ta vidéothèque, lecture directe |
| Jellyfin | non | lecture depuis Jellyfin (secours) |

Les boutons **Tester** vérifient chaque service ; **Tester et enregistrer**
teste tout avant d'enregistrer (et propose d'enregistrer quand même si un
serveur est éteint). L'interrupteur **Afficher les secrets** dévoile les
champs masqués.

> 🔒 Tous les identifiants sont rangés dans le trousseau du système, jamais
> dans un fichier en clair.

## Transmission

- **Adresse RPC** : par exemple `https://serveur:9091/transmission/rpc`.
  Sans chemin, `/transmission/rpc` est ajouté.
- **Utilisateur / mot de passe** : ceux de l'authentification RPC, si elle
  est activée.

Le bouton **Serveur Transmission** ouvre la configuration complète du daemon
(voir [Transferts](transferts.md#le-serveur)).

## Trackers

Un champ par tracker ; laisse vide ceux que tu n'utilises pas.

| Tracker | Identifiant | Où le trouver |
|---|---|---|
| C411 | clé API | profil sur c411.org |
| tr4ker | clé API | profil sur tr4ker.net |
| Nostradamus | clé API | profil sur nostradamus.foo |
| Draupnirr | clé API (passkey) | profil sur draupnirr.xyz |
| AstraTorrent | **passkey** | profil sur astratorrent.la |

Chaque tracker renseigné rejoint la vue **Trackers** et la vérification de
disponibilité des titres. Draupnirr ajoute en plus un onglet dédié
(entre **Transferts** et **C411**) qui affiche ton compte (ratio,
crédits, seedtime, H&R), les missions en cours et la liste des badges.

## Cookie de session C411

Les notifications en direct et le salon passent par le WebSocket du site, qui
n'accepte **que** le cookie de session (la clé API est refusée).

1. Connecte-toi sur c411.org dans ton navigateur.
2. Outils de développement (F12) → onglet *Réseau* → recharge la page →
   clique sur une requête vers c411.org.
3. Copie la valeur de l'en-tête `Cookie` et colle-la dans le champ.

Le cookie expire avec la session : il faudra le recoller de temps en temps
(l'application te le signale).

## TMDB

Crée un compte gratuit sur [themoviedb.org](https://www.themoviedb.org/), puis
*Paramètres → API*. Les deux formats sont acceptés :

- la **clé d'API** (v3, 32 caractères) ;
- le **jeton d'accès en lecture** (v4, commence par `eyJ`).

## Serveur de fichiers (FTP)

C'est ce qui alimente ta propre vidéothèque ([Sur le disque](sur-le-disque.md)),
et permet de lire les fichiers directement. Deux protocoles au choix, en tête
de la section : **FTP** ou **WebDAV**.

### WebDAV (le plus rapide)

Un partage WebDAV sur HTTPS : une connexion gardée ouverte, les dossiers lus
en parallèle pendant un parcours, et l'avance rapide sans reconnexion (une
simple requête `Range`).

| Champ | Exemple |
|---|---|
| Adresse du partage | `https://dav.<identifiant>.appbox.co/` |
| Identifiant / mot de passe | ceux du partage (authentification Basic) |

Le partage doit montrer **les mêmes dossiers que le FTP** (sa racine contient
par exemple `torrents/`). N'importe quel serveur WebDAV convient, par exemple
`rclone serve webdav /chemin --addr :8080 --user moi --pass …` derrière le
HTTPS de la seedbox, ou nginx, Caddy, Nextcloud.

### FTP

| Champ | Exemple (Appbox) |
|---|---|
| Hôte | `ftp.<identifiant>.appbox.co` |
| Port | `21` |
| Identifiant / mot de passe | ceux de l'application FTP |
| Chiffrement TLS | activé (FTP sur TLS explicite, « FTPES ») |
| Dossiers à parcourir | facultatif, un par ligne : `/Films`, `/Séries` |

Sur **Appbox**, installe d'abord l'application **Pure-FTPd** depuis le tableau
de bord ; ses identifiants s'affichent après l'installation.

Le bouton **Tester** se connecte et liste les **dossiers à la racine** : pratique
pour savoir quoi mettre dans « Dossiers à parcourir ». Il signale aussi les
dossiers indiqués qui sont vides ou introuvables.

Les torrents terminés de Transmission sont toujours pris en compte, même sans
dossier indiqué : l'application retrouve seule où leurs fichiers apparaissent
sur le FTP ou le partage WebDAV. Les dossiers à parcourir et le bouton
**Tester** valent pour les deux protocoles.

## Jellyfin

Facultatif depuis l'arrivée de la base FTP, Jellyfin sert de secours pour les
titres que la base ne connaît pas.

- **Adresse du serveur** : `https://jellyfin.exemple.org` ou
  `http://192.168.1.10:8096`.
- **Clé d'API** : Jellyfin → *Tableau de bord* → *Clés API*.

## Apparence

Thème **clair**, **sombre** ou **selon le système**, en haut des Réglages.
