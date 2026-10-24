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
  `ftpUser`, `ftpPassword`, `ftpTls` ; ou `filesProtocol: "webdav"` avec
  `webdavUrl`, `webdavUser`, `webdavPassword` ; ou `filesProtocol: "local"`
  avec `localRoot`, un dossier de la machine ; et `tmdbKey` pour les images
  de fond).
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

## Votes des membres

Chaque membre peut dire « j’aime » ou « je n’aime pas » sur les films et séries
(boutons 👍 / 👎 sur la fiche (bouton « Plus d’infos »)) ; recliquer sur son vote le retire, cliquer
sur l’autre le change. Les vignettes montrent le score (pour − contre), et
on s’en sert pour la rangée « Préférés des membres » sur l’accueil, tri « Préférés des membres » dans Films et Séries.

- **Anonymes** : le serveur ne garde pas le nom, seulement une empreinte
  HMAC-SHA256 avec une clé propre au serveur (`votes.json.key`, créée au
  premier lancement, lisible du seul propriétaire). On sait qu’un membre a
  déjà voté, sans pouvoir dire qui ; seuls les totaux sont affichés.
- **Qui vote** : le membre annoncé par le proxy dans `Remote-User` (Caddy,
  après la connexion Authelia de vache.cloud). Sans cet en-tête (accès direct
  au serveur), on voit les totaux sans pouvoir voter.
- Votes dans `~/.local/share/c411_player/votes.json`. Un film reconnu par TMDB après coup change d’identifiant et repart de zéro.
- API : `GET /api/votes`, `POST /api/vote/<id>` avec `{"value": 1 | -1 | 0}`
  (corps JSON obligatoire), code commun dans `packages/c411_core/lib/votes.dart`.

## Favoris

**Les favoris d’un membre, c’est ce qu’il a aimé** : un 👍 (sur la fiche)
ajoute l’élément en tête de ses favoris ; retirer son vote ou passer à 👎
l’en sort. On les retrouve dans la page **Favoris** (`#favoris`) et rangée « Mes favoris » sur l’accueil. La liste est **gardée sur le
serveur**, avec les votes : elle suit le membre sur tous ses appareils.

- Sur : films et séries.
- Dans le même fichier que les votes (`~/.local/share/c411_player/votes.json`) : `likes`, l’ordre des « j’aime »
  de chaque membre, sous son empreinte HMAC (jamais son nom). L’ancien format
  (votes seuls) est relu, ses « j’aime » deviennent des favoris.
- API : `GET /api/favorites` (plus récent d’abord) ; on les change par
  `POST /api/vote/<id>`.

## Sécurité

Par défaut, le serveur n'écoute **qu'en local** (`127.0.0.1`). Pour
l'ouvrir au réseau ou au web (`--host 0.0.0.0`), un **mot de passe est
obligatoire** : le navigateur le demande (authentification HTTP, n'importe
quel nom d'utilisateur). Derrière un reverse proxy (Caddy, nginx), servez-le
en **HTTPS** : en HTTP simple, le mot de passe circule en clair.

Les chemins du FTP ne sont jamais envoyés au navigateur : chaque fichier a
un identifiant opaque.

## Lecture

C'est **le navigateur qui décide**, car lui seul sait ce qu'il décode (le
lecteur de l'application, mpv, lit tout ; un navigateur, non).
`/api/play/<fichier>` décrit le fichier avec `ffprobe` (codecs précis,
pistes audio, piste par défaut), puis le navigateur teste ces codecs
(`canPlayType`) :

- **lecture directe** (`/media/…`, avance rapide native, **sans ffmpeg**)
  si la vidéo et la piste audio voulue se décodent et que cette piste est
  celle marquée par défaut — **MKV compris** (Chrome lit les MKV H.264) ;
- **ffmpeg, vidéo copiée** (`/stream/…?copy=1`) si la vidéo se décode mais
  pas l'audio, ou si la piste voulue n'est pas celle par défaut : seul
  l'audio est converti, quasiment sans calcul. Cas courant : l'**E-AC3 /
  AC3** (DD+, DD) et le **DTS**, que Chrome ne décode pas — un MKV H.264 +
  AC3 y serait lu **sans le son** ;
- **ffmpeg, vidéo réencodée** en H.264 (1080p au plus) si le navigateur ne
  décode pas la vidéo : typiquement le **H.265** sous Chrome Linux (Edge,
  Safari, Chrome avec décodage matériel le décodent : vidéo copiée).

L'audio converti est en AAC stéréo, **piste française** par défaut, au
choix dans le lecteur. Si une lecture directe échoue malgré tout (erreur,
image non décodée, rien au bout de 20 s), le lecteur bascule tout seul sur
ffmpeg, à la même position. En conversion, l'avance rapide relance ffmpeg à
la bonne position.

Vidéo copiée : la conversion part toujours d'une **image clé**
(`/api/keyframe/<fichier>?t=`, puis `-noaccurate_seek`), et le lecteur cale
son horloge dessus. Avec une recherche précise, ffmpeg faisait partir le son
pile à la position demandée et la vidéo à l'image clé précédente, avec un
trou au début de la piste audio que les navigateurs ignorent : le son était
en avance de plusieurs secondes après une reprise ou une avance rapide.

Raccourcis du lecteur : Espace (lecture/pause), ← / → (10 s), F (plein
écran), Échap (retour). Les positions de reprise sont gardées dans le
navigateur. Liens directs : `#films`, `#series`, `#t=<titre>`.

Comme dans l'application, un fichier ne compte que s'il fait au moins
**500 Mo (film)** ou **100 Mo (épisode)** : les vidéos de jeux et autres
petits fichiers sont ignorés. Seuls les titres reconnus par TMDB sont mis en avant ; les autres (fichiers
épars, vidéos de jeux…) restent accessibles par la recherche et « Tout
afficher » dans Films et Séries.

## Apparence

Aux couleurs de vache.cloud : bleu ciel en clair, ardoise en sombre (selon le
thème du système), accent rose, police à chasse fixe, bordures en pointillés,
favicon tête de vache et pied de page « made with ♥ ». Les couleurs sont des
variables en tête de `public/style.css` (les voiles posés sur les affiches
passent par `--bg-rgb` et `--surface-rgb`). Le lecteur vidéo reste sombre.
`public/` est lu à chaque requête : une retouche s'applique sans recompiler.

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
