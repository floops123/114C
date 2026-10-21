# C411 Books — la bibliothèque dans le navigateur

Le pendant de [C411 TV](../web_player/README.md) et de
[C411 Music](../web_music/README.md) pour la lecture. Ce petit serveur
diffuse tes **livres, BD, mangas et magazines**, avec une liseuse dans le
navigateur :

- **un accueil** : à la une, *Continuer la lecture*, ajoutés récemment, puis
  une rangée par genre ;
- **les séries** (BD, mangas, magazines par titre) et une recherche ;
- **une fiche par livre** : couverture, auteurs, série et tome, résumé,
  sujets, *Lire* et *Télécharger* ;
- **trois liseuses**, qui reprennent là où on s'était arrêté :
  - **EPUB** : pages, thèmes sombre, sépia et clair, taille du texte, table
    des matières ;
  - **PDF** : page simple ou double ;
  - **BD** (CBZ, CBR, CB7) : page simple ou double, ajustement à la hauteur
    ou à la largeur, sens de lecture des mangas.

Comme C411 TV et C411 Music, il ne parcourt rien lui-même. Il lit **la base
de l'application** : le parcours de sa vidéothèque (*Films & séries › Sur
le disque › Actualiser*, et l'ajout automatique des torrents terminés)
relève aussi les livres numériques. Le serveur relit la base quand elle
change.

## D'où viennent les informations

Il n'y a pas d'équivalent de TMDB ou MusicBrainz pour tout ce qui se lit :
les sources sont combinées, de la plus sûre à la moins sûre.

1. **Le fichier lui-même**, lu sans le télécharger en entier (quelques
   requêtes `Range` sur l'archive ZIP) :
   - un **EPUB** donne son titre, ses auteurs, son résumé, son éditeur, sa
     date, sa langue, ses sujets, son ISBN, sa série (Calibre ou EPUB 3) et
     sa couverture ;
   - une **BD en CBZ** donne ses pages (la première sert de couverture) et
     souvent un `ComicInfo.xml` : série, numéro, titre, scénariste,
     dessinateur, résumé, éditeur, sens de lecture.
2. **[Open Library](https://openlibrary.org/)**, sans clé, pour les livres :
   - la fiche de l'œuvre : résumé, sujets, couverture de l'**édition
     française** quand il y en a une ;
   - par l'ISBN s'il est connu, sinon par le titre et l'auteur, puis par une
     recherche libre (titre et auteur inversés, nom « de scène »).
3. **[Google Books](https://developers.google.com/books)**, si tu fournis une
   clé (gratuite) : souvent de meilleurs résumés en français. Sans clé,
   Google Books partage un quota mondial vite épuisé, donc il n'est pas
   utilisé.
4. **Le nom du fichier**, en dernier recours. Formats reconnus :
   - livres : `Auteur - Titre (année)`, `Nom, Prénom - Titre`, ou le nom de
     scène `Auteur.Titre.2012.FRENCH.EPUB` ;
   - BD : `Série - T01 - Titre`, `Série T03`, `Série 012`, `Série #7` ;
   - magazines : `Titre N°2650 - 6 Juin 2025`, `Titre - Juillet 2025`,
     `Titre du 04.06.2025`.

Les BD et les mangas ne sont pas cherchés en ligne : les bases qui les
connaissent (ComicVine, Metron) demandent un compte, et la BD
franco-belge n'en a pas d'ouverte. Les magazines non plus, aucune base ne
les recense.

Le genre (livre, BD, manga, magazine) vient du format et des dossiers :
- `.cbz`, `.cbr` : une BD (un manga sous un dossier « Mangas ») ;
- un numéro ou une date dans le nom, ou un dossier « Presse » ou
  « Magazines » : un magazine.

### Couvertures

Gardées sur le disque une fois obtenues :
- **EPUB** : celle du fichier ;
- **CBZ** : la première page ;
- **livres sans couverture** : celle d'Open Library ou de Google Books ;
- **PDF** : la première page, par `pdftoppm` (poppler) ;
- **CBR, CB7** : la première page, par `7z`.

Pour un PDF ou un CBR, il faut le fichier entier : ces couvertures sont
faites à la demande, une par une, quand elles s'affichent. ffmpeg, s'il est
là, réduit les couvertures à 600 pixels de large.

## Lancer

Prérequis : le SDK Dart. Facultatifs :
- `pdftoppm` (paquet poppler-utils) pour les couvertures des PDF ;
- `7z` (7zip ou p7zip) pour les BD en CBR et CB7 ;
- ffmpeg pour réduire les couvertures.

```sh
cd web_books
dart pub get
dart run bin/web_books.dart ../personal.json
```

puis ouvrir <http://127.0.0.1:8413/>.

### Section `books` (facultative) du fichier de réglages

```json
"books": {
  "host": "127.0.0.1",
  "port": 8413,
  "password": "",
  "library": "/chemin/vers/shared_preferences.json",
  "state": "/chemin/vers/books.json",
  "googleBooksKey": "",
  "cacheGb": 2,
  "contact": "https://exemple.org/moi"
}
```

| Clé | Rôle |
|---|---|
| `library` | la base de l'application (ses préférences) ; `~/.local/share/fr.c411remote.c411_remote/shared_preferences.json` par défaut |
| `state` | ce que le serveur sait des livres ; `~/.local/share/c411_books/books.json` par défaut, couvertures (`covers/`) et copies locales (`files/`) à côté |
| `googleBooksKey` | clé Google Books, facultative |
| `cacheGb` | place des copies locales (PDF et CBR lus en entier), 2 Go par défaut ; les moins récemment lues partent |
| `contact` | envoyé à Open Library dans le User-Agent ; l'adresse du dépôt par défaut |

Les options `--library`, `--state`, `--google-books-key`, `--cache-gb`,
`--host`, `--port` et `--password` passent avant.

## Lecture

- **EPUB** : lu par [epub.js](https://github.com/futurepress/epub.js).
- **PDF** : lu par [PDF.js](https://mozilla.github.io/pdf.js/), par plages
  de 1 Mo. Un magazine de 80 Mo s'ouvre sans être téléchargé en entier.
- **BD** : servies page par page. Une page de CBZ se lit à distance dans
  l'archive ; un CBR ou un CB7 est d'abord copié en local, puis ouvert par
  7z.
- **MOBI, AZW3, FB2, DjVu** : à télécharger, à lire dans une liseuse
  (Calibre, KOReader…).

Les liseuses EPUB et PDF ainsi que JSZip sont intégrées
(`public/vendor/`, licences dans `LICENSES.txt`) : rien n'est chargé depuis
Internet.

La position de lecture, les réglages des liseuses et la liste *Continuer la
lecture* sont gardés dans le navigateur.

Raccourcis de la liseuse :

| Action | Touche |
|---|---|
| Page suivante / précédente | → / ←, Espace, Page suivante / Page précédente |
| Fermer | Échap |
| Double page | D |
| Ajuster à la hauteur ou à la largeur | F |
| Sens de lecture des mangas | R |

On peut aussi cliquer sur le tiers gauche ou droit de la page.

## Sécurité

Comme C411 TV et C411 Music, le serveur n'écoute **qu'en local** par défaut.
Pour l'ouvrir au réseau (`--host 0.0.0.0`), un **mot de passe est
obligatoire** (authentification HTTP), et il faut le servir en **HTTPS**
derrière un reverse proxy. Les chemins du FTP ne sont jamais envoyés au
navigateur : chaque livre a un identifiant opaque.

## Code

```
bin/web_books.dart    ligne de commande
lib/config.dart       réglages (JSON de l'application + section books)
lib/remote_zip.dart   archive ZIP lue par plages (EPUB, CBZ)
lib/inspect.dart      métadonnées : OPF des EPUB, ComicInfo.xml, pages
lib/online.dart       Open Library, Google Books (rythme, choix de la fiche)
lib/content.dart      copies locales, pages (ZIP, 7z), couvertures
lib/library.dart      livres, ce qu'on en sait, séries
lib/service.dart      relecture de la base, lecture des fichiers, fiches
lib/server.dart       HTTP : interface, API, pages, fichiers
public/               interface (HTML, CSS, JS, sans étape de compilation)
```

La reconnaissance des noms et le tri des livres (`book_name.dart`), le
client FTP et le relais HTTP viennent du paquet partagé
[`packages/c411_core`](../packages/c411_core). Le parcours est celui de
l'application (`lib/state/media_library.dart`), qui range les livres dans sa
base (`books`).

Tests : `dart test`. Ils couvrent :
- les noms et le tri des torrents ;
- la lecture partielle des ZIP ;
- les métadonnées des EPUB et des BD ;
- Open Library sur un faux serveur ;
- les fiches et les séries ;
- l'API, avec un faux relais : couvertures, pages, plages, téléchargement.
