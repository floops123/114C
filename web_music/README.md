# C411 Music — la musique dans le navigateur

L'équivalent de [C411 TV](../web_player/README.md) pour la musique : un
petit serveur qui diffuse la musique de ton serveur avec un lecteur dans
le navigateur. On y trouve :

- un accueil avec un album à la une et des rangées (écoutés récemment,
  ajoutés récemment, par genre, artistes) ;
- les albums et les artistes, et une recherche ;
- des fiches d'albums avec leurs pistes, durées, label et genres ;
- un lecteur permanent : aléatoire, répétition, file d'attente, reprise
  là où on s'était arrêté ;
- un bouton **Random** (barre du haut) : une playlist de 30 titres tirée au
  hasard dans toute la discothèque, ou dans le genre affiché (`#albums&genre=…`).
  Tirage pondéré : moins de chances pour les titres joués récemment (300
  derniers, mémorisés dans le navigateur) et les 10 derniers albums écoutés,
  un peu plus pour les albums ajoutés depuis moins d'un mois. Pas
  d'émissions, ni de pistes de moins d'une minute (intros, interludes) ou de
  plus de 15 min. Au plus 2 titres par album et 3 par artiste (relâché par
  paliers si la discothèque est petite), et jamais deux fois le même artiste
  d'affilée quand c'est possible.

Comme C411 TV, il ne parcourt rien lui-même. Il lit **la base de
l'application** : le parcours de sa vidéothèque (*Films & séries › Sur le
disque › Actualiser*, et l'ajout automatique des torrents terminés) relève
aussi les fichiers audio. Les sources sont les mêmes que pour les vidéos :
les torrents terminés de Transmission, puis les *Dossiers à parcourir* du
FTP. Le serveur relit la base quand elle change.

Il identifie ensuite chaque album sur
**[MusicBrainz](https://musicbrainz.org/)** : titre, artistes, date, label,
genres, pistes et durées. La pochette vient de la
**[Cover Art Archive](https://coverartarchive.org/)**.

Avec un jeton **[Discogs](https://www.discogs.com/)**, chaque album passe
aussi **une fois** par Discogs :
- **inconnu de MusicBrainz** : la fiche Discogs (pistes comprises, positions
  `A1`, `1-3`, `CD2-5` converties ; le nombre de pistes est vérifié) ;
- **reconnu sans pochette ou sans genres** : la pochette Discogs (après celle
  de la parution sur la Cover Art Archive, avant celle de son groupe de
  parutions) et ses **styles** (« Trip Hop », plus fins que les genres).
Une requête de recherche par album, plus une fiche s'il est inconnu ;
60 requêtes par minute permises, une par seconde au plus. Jeton refusé ou
service saturé : Discogs est sauté, l'identification continue.

## Lancer

Prérequis : le SDK Dart (fourni avec Flutter) et, facultatif, **ffmpeg** pour
les formats que les navigateurs ne lisent pas (WMA, APE, WavPack, AIFF,
ALAC…).

```sh
cd web_music
dart pub get
dart run bin/web_music.dart ../personal.json
```

puis ouvrir <http://127.0.0.1:8412/>.

`../personal.json` : le même fichier que pour la
[compilation personnalisée](../docs/dev/build.md). Il fournit l'accès au FTP
(`ftpHost`, `ftpPort`, `ftpUser`, `ftpPassword`, `ftpTls`), ou au partage
WebDAV (`filesProtocol: "webdav"`, `webdavUrl`, `webdavUser`,
`webdavPassword`), ou à un dossier de la machine (`filesProtocol: "local"`,
`localRoot`). La base de
l'application est lue dans ses préférences
(`~/.local/share/fr.c411remote.c411_remote/shared_preferences.json` sous
Linux), comme pour C411 TV ; ailleurs, `--library <fichier>`.

### Section `music` (facultative) du fichier de réglages

```json
"music": {
  "host": "127.0.0.1",
  "port": 8412,
  "password": "",
  "library": "/chemin/vers/shared_preferences.json",
  "state": "/chemin/vers/library.json",
  "contact": "https://exemple.org/moi",
  "discogsToken": ""
}
```

| Clé | Rôle |
|---|---|
| `library` | la base de l'application (ses préférences) |
| `state` | les fiches MusicBrainz ; `~/.local/share/c411_music/library.json` par défaut, pochettes dans `covers/` à côté |
| `contact` | envoyé à MusicBrainz dans le User-Agent, qu'il exige ; l'adresse du dépôt par défaut |
| `discogsToken` | jeton personnel Discogs (Réglages → Développeurs), facultatif |

Les options `--library`, `--state`, `--discogs-token`, `--host`, `--port` et `--password`
passent avant.

Le bouton ⓘ en haut à droite donne l'état : albums reconnus, heure du
dernier parcours de l'application. Pendant l'identification, il affiche
la progression (« MusicBrainz 12/40 »).

## Ce qui compte comme de la musique

C'est l'application qui trie, pendant son parcours. Comme pour les vidéos,
il faut écarter les faux positifs :

- **un torrent** n'est retenu que si l'audio fait au moins **la moitié de
  ses octets**. La bande-son d'un jeu ou d'un film n'en fait pas partie ;
- **un dossier** parcouru n'est retenu que s'il a **100 pistes au plus**, de
  **1,5 Mo en moyenne** au moins. Les dossiers de bruitages d'un jeu en ont
  des centaines, toutes petites ;
- une piste de moins de **300 Ko** est ignorée (jingles, extraits).

Un album, c'est un dossier. Les sous-dossiers `CD1`, `Disc 2`… sont réunis
en un seul album à plusieurs disques.

Le serveur trie ensuite chaque dossier (`AlbumKind` dans `lib/library.dart`) :

- **musique** : albums, artistes, genres, Random, recherche MusicBrainz et
  Discogs ;
- **livres audio** : un onglet à part, **Livres audio** (`#audiobooks`), avec
  une rangée « Continuer l'écoute ». Sur la fiche, **Reprendre** relance la
  piste et la position où on s'était arrêté (gardées dans le navigateur, toutes
  les 5 s). Pas de recherche MusicBrainz (une ancienne fiche trouvée à tort
  est ignorée), pas d'artiste ; titre et auteur sont lus dans le nom du
  dossier (`AudiobookName` : « Auteur - Titre », « Titre - Auteur »,
  « Sujet - Titre - Auteur », nom de release) ;
- **autres** : sons sans rapport (samples d'un logiciel, musiques d'un jeu),
  écartés de l'interface.

D'abord le **dossier de catégorie** que l'application pose dans Transmission
(le premier rencontré depuis la racine) : `Musique` → musique ; `Livres` →
livre audio ; `Logiciels`, `Jeux vidéo`, `Films`, `Séries`… → autres. Sans
catégorie : livre audio si un fichier est en `.m4b`, si le nom contient
« livre audio », « audiobook », « lu par » ou une référence Audible
(`[B0…]`), ou si la moitié des pistes au moins s'appellent « Chapitre … » ;
sinon musique.

## Reconnaissance et MusicBrainz

L'artiste, le titre et l'année viennent du nom du dossier. Formats compris :

- `Artiste - Album (2013) [FLAC]` ;
- `Artiste/2013 - Album` ;
- le nom de scène `Artiste-Album-WEB-2013-GRP`.

Le numéro et le titre de chaque piste viennent de son nom de fichier :
`03 - Titre`, `1-03 Titre`, `103 Titre`, `01-artiste-titre-grp`.

La recherche sur MusicBrainz départage les parutions par le nombre de
pistes, l'année et le statut officiel. Elle ne retient une parution que si
le titre correspond vraiment. Les pistes sont ensuite rattachées par disque
et numéro, sinon dans l'ordre, sinon par titre.

- **Rythme imposé** par MusicBrainz : une requête par seconde au plus, deux
  ou trois par album. La première identification de 500 albums prend donc une
  demi-heure environ, en arrière-plan ; l'interface se remplit au fil de
  l'eau.
- **Service saturé** : MusicBrainz répond souvent 503, même à ce rythme.
  On réessaie en attendant de plus en plus. S'il reste saturé, l'album est
  repris une minute plus tard, trois fois au plus.
- **Nouveaux albums** : ils sont cherchés dès que la base de l'application
  change. Le serveur la vérifie toutes les 30 secondes.
- **Album non trouvé** : il garde les titres de ses fichiers, et la
  recherche est refaite au bout d'une semaine. « Chercher à nouveau en
  ligne », sur sa fiche, la relance tout de suite (Discogs compris).
- **Pochettes** : lues une fois sur la Cover Art Archive, puis gardées sur
  le disque.

## Lecture

`/api/play/<piste>` donne le type du fichier. Le navigateur le lit **tel
quel** s'il sait le faire : MP3, FLAC, AAC/M4A, Ogg, Opus, WAV. L'avance
rapide est alors native. Sinon le fichier est **converti par ffmpeg** en AAC
(`/stream/<piste>?t=<secondes>`), et l'avance rapide relance la conversion
à la bonne position. Si une lecture directe échoue (de l'ALAC dans un
`.m4a`, par exemple), le lecteur bascule tout seul sur la conversion.

Commandes du lecteur et des touches du clavier :

| Action | Touche |
|---|---|
| Lecture / pause | Espace |
| Reculer / avancer de 10 s | ← / → |
| Piste précédente / suivante | P / N (ou Maj + ← / →) |
| Aléatoire | S |
| Répétition (tout, une piste) | R |
| Couper le son | M |
| File d'attente | Q |

Le lecteur s'affiche aussi dans les commandes multimédias du système
(Media Session). La file, la position et le volume sont gardés dans le
navigateur.

**Ajouter à la file d'attente** : le bouton ≡+ de chaque ligne de titre
(album, recherche, favoris) ajoute le titre à la fin de la file ; « File
d’attente » sur la page d’un album y ajoute tout l’album. Si rien n'est en
cours, la lecture démarre. Dans la file, ✕ retire une ligne (la piste en
cours laisse place à la suivante).

Dans la **file d'attente**, chaque ligne a un bouton qui ouvre l'album (ou
le livre audio) et y montre la piste, et deux votes compacts 👍 / 👎 sur son
album, retirés d'abord quand la file est trop étroite (moins de 330 px). « titre
en cours », en haut de la file, et un clic sur le titre dans le lecteur
mènent à la piste qui joue.

## Votes des membres

Chaque membre peut dire « j’aime » ou « je n’aime pas » sur les albums (et
les livres audio), et sur chaque titre
(boutons 👍 / 👎 sur la page de l’album) ; recliquer sur son vote le retire, cliquer
sur l’autre le change. Les vignettes montrent le score (pour − contre), et
on s’en sert pour la rangée « Préférés des membres » sur l’accueil, tri du même nom dans Albums ; le bouton **Random** favorise les albums aimés (jusqu’à ×2) et défavorise ceux qui ne le sont pas (×0,5).

- **Anonymes** : le serveur ne garde pas le nom, seulement une empreinte
  HMAC-SHA256 avec une clé propre au serveur (`votes.json.key`, créée au
  premier lancement, lisible du seul propriétaire). On sait qu’un membre a
  déjà voté, sans pouvoir dire qui ; seuls les totaux sont affichés.
- **Qui vote** : le membre annoncé par le proxy dans `Remote-User` (Caddy,
  après la connexion Authelia de vache.cloud). Sans cet en-tête (accès direct
  au serveur), on voit les totaux sans pouvoir voter.
- Votes dans `votes.json` à côté de `--state` (défaut : `~/.local/share/c411_music/votes.json`).
- API : `GET /api/votes`, `POST /api/vote/<id>` avec `{"value": 1 | -1 | 0}`
  (corps JSON obligatoire), code commun dans `packages/c411_core/lib/votes.dart`.

## Favoris

**Les favoris d’un membre, c’est ce qu’il a aimé** : un 👍 (sur la page de l’album ou du livre, sur chaque ligne de titre (album, recherche, favoris), dans la file d’attente et dans le lecteur)
ajoute l’élément en tête de ses favoris ; retirer son vote ou passer à 👎
l’en sort. On les retrouve dans la page **Favoris** (`#favoris` : albums, titres avec « Écouter les titres » et « Aléatoire », livres audio) et rangée « Mes favoris » sur l’accueil. La liste est **gardée sur le
serveur**, avec les votes : elle suit le membre sur tous ses appareils.

- Sur : albums, livres audio et **titres précis**.
- Dans le même fichier que les votes (`votes.json` à côté de `--state`) : `likes`, l’ordre des « j’aime »
  de chaque membre, sous son empreinte HMAC (jamais son nom). L’ancien format
  (votes seuls) est relu, ses « j’aime » deviennent des favoris.
- API : `GET /api/favorites` (plus récent d’abord) ; on les change par
  `POST /api/vote/<id>`.

## Sécurité

Comme C411 TV, le serveur n'écoute **qu'en local** par défaut. Pour
l'ouvrir au réseau (`--host 0.0.0.0`), un **mot de passe est obligatoire**
(authentification HTTP), et il faut le servir en **HTTPS** derrière un
reverse proxy. Les chemins du FTP ne sont jamais envoyés au navigateur :
chaque piste a un identifiant opaque.

## Code

```
bin/web_music.dart    ligne de commande
lib/config.dart       réglages (JSON de l'application + section music)
lib/musicbrainz.dart  client MusicBrainz (rythme, choix de la parution)
lib/discogs.dart      client Discogs (albums inconnus, pochettes, styles)
lib/library.dart      discothèque : musique de l'application, fiches,
                      albums, artistes
lib/service.dart      relecture de la base, identification au fil de l'eau
lib/server.dart       HTTP : interface, API, /media, /stream, pochettes
public/               interface (HTML, CSS, JS, sans étape de compilation)
```

La reconnaissance des noms et le tri de la musique (`music_name.dart`), le
client FTP et le relais HTTP viennent du paquet partagé
[`packages/c411_core`](../packages/c411_core). Le parcours est celui de
l'application (`lib/state/media_library.dart`), qui range la musique dans
sa base (`music`).

Tests : `dart test`. Ils couvrent les noms, les faux positifs, MusicBrainz
sur un faux serveur (saturation comprise), le rattachement des pistes, la
relecture de la base et l'API. Le parcours est testé côté application
(`test/media_library_test.dart`).
