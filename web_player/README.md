# C411 TV — la vidéothèque dans le navigateur

Petit serveur qui diffuse la vidéothèque de **C411 Remote** à la manière d'un
Netflix : bandeau, rangées (Reprendre, Ajoutés récemment, Films, Séries,
Les mieux notés), fiches avec saisons et épisodes, lecteur avec reprise là
où on s'était arrêté.

Il ne refait aucun parcours : il lit **la base que l'application a déjà
construite** (fichiers du FTP, fiches TMDB) et lit les vidéos sur le **FTP**,
avec les identifiants du fichier de réglages JSON de l'application.

## Lancer

Prérequis : le SDK Dart (fourni avec Flutter), et **ffmpeg** pour les
fichiers que les navigateurs ne savent pas lire (MKV, H.265, DTS, AC3…).

```sh
cd web_player
dart pub get
dart run bin/web_player.dart ../personal.json
```

puis ouvrir <http://127.0.0.1:8411/>.

- `../personal.json` : le même fichier que pour la
  [compilation personnalisée](../docs/dev/build.md) (`ftpHost`, `ftpPort`,
  `ftpUser`, `ftpPassword`, `ftpTls`, et `tmdbKey` pour les images de fond).
- La vidéothèque est lue dans les préférences de l'application
  (`~/.local/share/fr.c411remote.c411_remote/shared_preferences.json` sous
  Linux), et relue quand elle change. Ailleurs : `--library <fichier>`.

### Section `web` (facultative) du fichier de réglages

```json
"web": {
  "host": "127.0.0.1",
  "port": 8411,
  "password": "",
  "library": "/chemin/vers/shared_preferences.json"
}
```

Les options `--host`, `--port`, `--password`, `--library` passent avant.

## Sécurité

Par défaut, le serveur n'écoute **qu'en local** (`127.0.0.1`). Pour
l'ouvrir au réseau ou au web (`--host 0.0.0.0`), un **mot de passe est
obligatoire** : le navigateur le demande (authentification HTTP, n'importe
quel nom d'utilisateur). Derrière un reverse proxy (Caddy, nginx), servez-le
en **HTTPS** : en HTTP simple, le mot de passe circule en clair.

Les chemins du FTP ne sont jamais envoyés au navigateur : chaque fichier a
un identifiant opaque.

## Lecture

`/api/play/<fichier>` interroge le fichier avec `ffprobe` :

- **lu tel quel** (`/media/…`, avance rapide native) : MP4 ou WebM en H.264
  8 bits, VP9 ou AV1, audio AAC, MP3 ou Opus ;
- **converti à la volée** (`/stream/…?t=<secondes>`) sinon, en MP4
  fragmenté : vidéo **copiée** si elle est déjà en H.264 8 bits (peu
  coûteux), sinon **réencodée** en H.264 (1080p au plus : le H.265 4K
  sollicite le processeur) ; audio en AAC stéréo, **piste française** par
  défaut, au choix dans le lecteur. L'avance rapide relance la conversion à
  la bonne position.

Raccourcis du lecteur : Espace (lecture/pause), ← / → (10 s), F (plein
écran), Échap (retour). Les positions de reprise sont gardées dans le
navigateur. Liens directs : `#films`, `#series`, `#t=<titre>`.

Seuls les titres reconnus par TMDB sont mis en avant ; les autres (fichiers
épars, vidéos de jeux…) restent accessibles par la recherche et « Tout
afficher » dans Films et Séries.

## Code

```
bin/web_player.dart   ligne de commande
lib/config.dart       réglages (JSON de l'application + section web)
lib/library.dart      catalogue : même regroupement que l'application
lib/transcode.dart    ffprobe, lecture directe ou conversion, arguments ffmpeg
lib/server.dart       HTTP : interface, API, /media, /stream, images TMDB
public/               interface (HTML, CSS, JS, sans étape de compilation)
```

Le client FTP, le relais HTTP et la lecture des noms de release viennent du
paquet partagé [`packages/c411_core`](../packages/c411_core), utilisé aussi
par l'application.

Tests : `dart test` (dont un essai de bout en bout avec le vrai ffmpeg sur
un MKV H.265 à deux pistes audio, ignoré si ffmpeg est absent).
