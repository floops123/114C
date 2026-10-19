# Dépannage

[← Sommaire](../README.md)

## Connexion

**« Jeton de session refusé » / Transmission injoignable**
Vérifie l'adresse (avec `/transmission/rpc` ou sans chemin), l'utilisateur et
le mot de passe, et que la liste blanche RPC du serveur autorise ton adresse.
Le bouton **Tester** des Réglages donne le message exact du serveur.

**Un tracker répond « clé refusée »**
Recopie la clé depuis ton profil, sans espace. Pour AstraTorrent, c'est la
**passkey** qui est demandée, pas une clé d'API.

**Les notifications et le salon restent vides**
Le cookie de session a probablement expiré : reconnecte-toi sur le site et
recolle l'en-tête `Cookie` (voir [Configuration](configuration.md#cookie-de-session-c411)).

## Sur le disque

**Le test FTP échoue**

| Message | Piste |
|---|---|
| *Serveur FTP injoignable* | hôte ou port erroné ; sur Appbox, l'application Pure-FTPd est-elle installée et démarrée ? |
| *Identifiants FTP refusés* | identifiant ou mot de passe de l'application FTP (pas ceux du tableau de bord) |
| *TLS refusé par le serveur FTP* | désactive *Chiffrement TLS* si ton serveur ne le propose pas |
| *Le serveur FTP ne répond pas* | pare-feu, ou mode passif bloqué |

**« Fichiers des torrents introuvables sur le FTP »**
L'application n'a pas trouvé où le FTP montre les dossiers de Transmission.
Indique le dossier des téléchargements dans *Dossiers à parcourir* (par
exemple `/torrents/completed`) : il sera parcouru directement.

**Un titre est mal reconnu**
La reconnaissance se fie aux noms de fichiers et de dossiers. Un nom très
abrégé (`grp-xyz-1080p.mkv`) dans un dossier lui-même mal nommé ne peut pas
être deviné ; renommer le dossier avec le titre et l'année suffit, puis
**Actualiser**.

**La liste des dossiers s'affiche mais la lecture échoue**
Certains serveurs FTPS exigent que la connexion de transfert reprenne la
session TLS de la connexion principale, ce que l'application ne fait pas.
Le message d'erreur du lecteur l'indiquera ; essaie sans TLS si ton réseau le
permet.

## Lecture

**La vidéo saccade (Linux)**
Ouvre les **statistiques** (ⓘ) du lecteur : *Décodage matériel* doit indiquer
`vaapi` ou `nvdec`, et *Images perdues* rester proche de zéro. Vérifie que
`libmpv-dev` est installé et que l'application a été recompilée après une mise
à jour de Flutter.

**Le démarrage ou l'avance rapide prend une seconde**
Normal avec le FTP : chaque saut ouvre une nouvelle connexion au serveur.

## Jellyfin

**Une série est « déjà chez toi » mais aucun épisode n'apparaît**
Avec une bibliothèque mixte (films et séries mélangés), Jellyfin n'a pas de
fiche « Série » : l'application cherche alors le dossier de la série (au nom
de la série ou de la release) et lit saison et épisode dans le nom des
fichiers. Si rien n'apparaît, renseigne le [FTP](configuration.md#serveur-de-fichiers-ftp) :
la série viendra directement de tes fichiers, sans Jellyfin.

## Soins palliatif

**« Configure le cookie de session C411 dans les Réglages »**
L'onglet *Soins palliatif* lit la liste palliative sur l'API du site
(`/api/torrents?palliative=only`), qui exige d'être connecté — la clé API
n'y suffit pas. Renseigne le cookie de session comme pour les notifications
([Configuration](configuration.md#cookie-de-session-c411)) puis reviens sur
l'onglet.

**« Cookie de session C411 refusé »**
La session a expiré : reconnecte-toi sur le site et recolle l'en-tête
`Cookie` dans les Réglages.

**L'onglet liste les palliatifs mais aucun n'est trouvé ailleurs**
Vérifie qu'au moins un tracker **autre que C411** est coché dans *Chercher
les copies sur*, et que sa clé API est valide. Si une palliative est
introuvable partout, c'est normal : elle n'existe peut-être plus que sur
C411.

## Divers

**Les réglages ont disparu après une mise à jour du système**
Ils vivent dans le trousseau (libsecret sous Linux). Si le trousseau a été
réinitialisé, il faut les ressaisir.

**L'application est lente sur un vieux téléphone**
Préfère l'affichage **liste** dans les résultats de recherche : les affiches
en grille coûtent plus cher à afficher.
