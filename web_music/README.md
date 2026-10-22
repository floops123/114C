# C411 Music — la musique dans le navigateur

L'équivalent de [C411 TV](../web_player/README.md) pour la musique : un
petit serveur qui diffuse la musique de ton serveur avec un lecteur dans
le navigateur. On y trouve :

- un accueil avec un album à la une et des rangées (écoutés récemment,
  ajoutés récemment, par genre, artistes) ;
- les albums et les artistes, et une recherche ;
- des fiches d'albums avec leurs pistes, durées, label et genres ;
- un lecteur permanent : aléatoire, répétition, file d'attente, reprise
  là où on s'était arrêté.

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
  "contact": "https://exemple.org/moi"
}
```

| Clé | Rôle |
|---|---|
| `library` | la base de l'application (ses préférences) |
| `state` | les fiches MusicBrainz ; `~/.local/share/c411_music/library.json` par défaut, pochettes dans `covers/` à côté |
| `contact` | envoyé à MusicBrainz dans le User-Agent, qu'il exige ; l'adresse du dépôt par défaut |

Les options `--library`, `--state`, `--host`, `--port` et `--password`
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
  recherche est refaite au bout d'une semaine. « Chercher à nouveau sur
  MusicBrainz », sur sa fiche, la relance tout de suite.
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
