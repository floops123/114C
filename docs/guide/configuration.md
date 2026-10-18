# Configuration

[← Sommaire](../README.md)

Tout se règle dans l'onglet **Réglages**. Seuls Transmission et un tracker sont
indispensables ; chaque autre section ajoute une fonction et peut rester vide.

| Section | Indispensable ? | Débloque |
|---|---|---|
| Transmission | oui | Transferts, envoi des sorties, cross-seed |
| Trackers | au moins un | Sorties, recherche des souhaits |
| Cookie de session C411 | non | Notifications, Salon, Mon compte |
| TMDB | non | Souhaits, Découvrir, fiches, affiches de la base |
| Serveur de fichiers (FTP) | non | Sur le disque, lecture directe |
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
| AstraTorrent | **passkey** | profil sur astratorrent.la |

Un onglet apparaît dans **Sorties** pour chaque tracker renseigné.

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

C'est ce qui alimente ta propre vidéothèque, [Sur le disque](sur-le-disque.md),
et permet de lire les fichiers directement.

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
sur le FTP.

## Jellyfin

Facultatif depuis l'arrivée de la base FTP, Jellyfin sert de secours pour les
titres que la base ne connaît pas.

- **Adresse du serveur** : `https://jellyfin.exemple.org` ou
  `http://192.168.1.10:8096`.
- **Clé d'API** : Jellyfin → *Tableau de bord* → *Clés API*.

## Apparence

Thème **clair**, **sombre** ou **selon le système**, en haut des Réglages.
