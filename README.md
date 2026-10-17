# C411 Remote

Client multiplateforme pour piloter un daemon **Transmission** distant et parcourir
les dernières sorties des trackers **C411** et **tr4ker**, avec envoi direct d'une
sortie vers Transmission en un clic.

L'application est 100 % cliente : elle parle directement à l'API RPC de
Transmission et aux API des trackers, sans serveur intermédiaire.

## Fonctionnalités

**Sorties (C411, tr4ker)**
- Un onglet par tracker configuré (le dernier choisi est mémorisé).
- Liste paginée au défilement des dernières sorties (affiche, badges résolution /
  source / langue / freeleech / exclu, taille, seeders, ancienneté).
- Recherche par nom, filtres catégorie et sous-catégorie.
- Tri par date, seeders, leechers, téléchargements, taille, nom ou
  commentaires, croissant ou décroissant, mémorisé. Fait par le serveur pour
  C411 (`sortBy` + `sortOrder`) ; pour les trackers Torznab, qui ne trient
  pas, appliqué aux résultats déjà chargés.
- Fiche détaillée : synopsis, casting, infos techniques.
- Bouton « Télécharger » : récupère le `.torrent` et l'ajoute à Transmission.
  Les sorties déjà présentes dans Transmission sont marquées d'une ✓.

**Transferts (Transmission)**
- Liste rafraîchie toutes les 2 s (`torrent-get` au format « table »,
  `recently-active`), vitesses globales, filtres (actifs, en cours, partage,
  terminés, en file, arrêtés, bloqués, erreurs), filtre par étiquette.
- 12 tris (ajout, nom, état, file, progression, temps restant, vitesses,
  pairs, ratio, volume envoyé, taille), croissant ou décroissant, mémorisés.
- Sélection multiple (appui long) et actions groupées ; tout démarrer / arrêter.
- Actions : démarrer, démarrer maintenant (hors file), arrêter, vérifier,
  réannoncer, déplacer dans la file, déplacer les fichiers
  (`torrent-set-location`), étiquettes, priorité, copier le magnet, supprimer
  (avec ou sans les données).
- Ajout de fichiers `.torrent` depuis l'appareil (sélecteur natif via
  `file_selector`, plusieurs à la fois, contenu vérifié avant l'envoi :
  nom, taille, fichier invalide signalé), par lien magnet ou URL, et envoi
  depuis un tracker ; options : dossier, étiquettes, priorité, en pause.
- Détail en 5 onglets :
  - Infos : progression, carte des pièces, transfert, origine des pairs
    (tracker, DHT, PEX…), dates, créateur, hash ;
  - Fichiers : sélection, priorité par fichier, renommage (`torrent-rename-path`) ;
  - Pairs : client, progression, vitesses, chiffrement, µTP, entrant ;
  - Trackers : annonces et scrapes, paliers, édition de la liste (`trackerList`) ;
  - Options : priorité, limites de vitesse, groupe de bande passante, ratio et
    inactivité propres au torrent, nombre de pairs.

**Cross-seed** (menu ⋮ de l'écran Transferts)
- Pour chaque torrent terminé de Transmission, cherche la même release sur
  les autres trackers configurés (C411 → tr4ker, tr4ker → C411, autre tracker
  → les deux) : recherche par nom, candidats de même taille à l'octet près,
  puis comparaison fichier par fichier du `.torrent` candidat (lecteur
  bencode intégré). Les torrents déjà présents dans Transmission sont
  reconnus par leur infohash.
- Une correspondance s'ajoute (« Ajouter » / « Tout ajouter ») dans le dossier
  des données existantes, avec l'étiquette `cross-seed` : Transmission vérifie
  les données et partage sans rien retélécharger.
- Une requête à la fois avec une pause de 1,1 s (quota C411 : 120 / min) ;
  les résultats « introuvable », « fichiers différents » et « déjà partagé »
  sont mémorisés 7 jours (« Tout réanalyser » pour les ignorer).
- Le tracker d'origine est reconnu dans les URL d'annonce (`c411`, `tr4ker`).

**Statistiques** (icône 📈 de l'écran Transferts)
- Chiffres clés : vitesses actuelles, volumes envoyés / reçus (session et
  total), ratio global.
- Courbe des vitesses de réception et d'envoi sur 5, 15 ou 30 min, avec
  réticule et info-bulle, moyenne et pic.
- Classement des torrents par volume envoyé ou reçu, ratio ou vitesse.
- Dans le détail d'un torrent : sa courbe de vitesse sur 15 min, et une jauge
  de progression par fichier.
- Transmission ne conserve aucun historique : les vitesses sont enregistrées
  par l'application pendant qu'elle est ouverte (un point toutes les 2 s, à
  partir du rafraîchissement existant, sans requête supplémentaire). Il
  n'existe pas de statistique d'envoi par fichier dans Transmission.

**Notifications (C411)**
- Connexion au WebSocket du site (`wss://c411.org/ws/`, Socket.IO / Engine.IO
  v4) dès que les cookies de session sont renseignés ; reconnexion
  automatique (2 s → 2 min).
- Onglet Notifications (pastille du nombre de non-lues, bandeau à
  l'arrivée) :
  - Notifications : celles du site (`/api/notifications`), icône par type,
    non lues signalées, groupées par jour, « Afficher plus anciennes »
    (pages suivantes du site), tirer pour rafraîchir. Relues toutes les
    2 min et à chaque événement WebSocket inconnu ; bandeau à l'arrivée d'une
    nouvelle. Clic : torrent ouvert dans l'app s'il est dans Transmission,
    salon ouvert pour un lien `/messages?channel=…`, sinon page du site.
    Les 500 dernières sont gardées en cache (consultables hors ligne). Le
    badge compte les non lues pas encore vues dans l'app ; l'état « lu » du
    site n'est pas modifié. Compteurs de non-lus (messages privés, salons,
    demandes, staff) avec bandeau quand l'un augmente, et encadré « Mon
    compte » en direct (envoyé, reçu, crédit, ratio) ;
  - Salon : choix parmi les salons du site (Général par défaut), description
    et message épinglé, 50 derniers messages chargés puis suite en direct
    (pseudo, avatar, badge, réponse citée, réactions mises à jour en direct
    — les nôtres mises en évidence, membres au survol —, « modifié », images
    jointes), personnes en ligne, « … écrit ». Mise en forme : séparateurs de
    jour, messages consécutifs d'un même auteur regroupés, **gras**,
    *italique*, ~~barré~~, `code`, liens cliquables, mentions `@pseudo`
    (messages qui nous mentionnent surlignés), nos messages signalés par un
    liseré, étiquettes Modo / Admin, texte sélectionnable.
  - Envoi de messages (Entrée envoie, Maj+Entrée = nouvelle ligne) : affiché
    aussitôt, confirmé par le serveur, « Réessayer » en cas de refus ; saisie
    remplacée par « Lecture seule » dans les salons où l'on ne peut pas écrire
    (Annonces), rappel du mode lent le cas échéant.

**Réglages**
- Adresse RPC, identifiants Transmission et clé API C411, stockés dans le
  trousseau du système (`flutter_secure_storage`).
- Test des connexions, automatiquement avant chaque enregistrement.
- Configuration complète du serveur Transmission (`session-set`), d'après
  `docs/Editing-Configuration-Files.md` : dossiers et fichiers incomplets,
  limites de vitesse, mode tortue et sa planification (heures, jours), files
  d'attente, ratio et inactivité, port, chiffrement, protocoles, DHT / PEX /
  LPD, blocklist, trackers par défaut, scripts, anti-force brute. Seules les
  options renvoyées par le serveur sont affichées (compatibilité 3.x → 4.1),
  recherche parmi les réglages, seules les modifications sont envoyées.
- Outils serveur : test du port, mise à jour de la blocklist, espace disque
  (libre / total), nombre de torrents, statistiques de session et cumulées,
  groupes de bande passante (`group-get` / `group-set`), arrêt du daemon
  (`session-close`).
- Thème clair, sombre ou suivant le système.

## Plateformes

| Plateforme | État |
|---|---|
| Linux | testé |
| Android | APK compilé (API 24 → 36), mise en page téléphone vérifiée |
| iOS, Windows, macOS | projet généré, non testé |
| Web | **non supporté** : ni Transmission ni C411 n'envoient d'en-têtes CORS |

## Démarrer

Prérequis Linux (Debian / Ubuntu / Mint) :

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  libsecret-1-dev libjsoncpp-dev
```

Puis :

```sh
flutter pub get
flutter run -d linux        # développement (r = hot reload)
flutter build linux         # build release dans build/linux/x64/release/bundle
flutter test                # tests unitaires
flutter analyze             # analyse statique
```

### Android

SDK installé sans Android Studio (outils en ligne de commande) :

```sh
export ANDROID_HOME="$HOME/Android/Sdk"
# Une fois : outils en ligne de commande dans $ANDROID_HOME/cmdline-tools/latest, puis
sdkmanager --install "platform-tools" "platforms/android-36" \
  "build-tools/36.1.0" "ndk/28.2.13676358"
flutter config --android-sdk "$ANDROID_HOME"

flutter build apk --release --split-per-abi   # build/app/outputs/flutter-apk/
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
flutter run -d <id du téléphone>              # développement (débogage USB)
```

Réglages propres à Android (`android/app/src/main/AndroidManifest.xml`) :
permission Internet, trafic HTTP autorisé (adresse RPC Transmission souvent en
`http://` — préférer `https://`), ouverture des liens (`<queries>`), sauvegarde
Google désactivée (`allowBackup=false`, `data_extraction_rules.xml`) car les
secrets sont chiffrés par une clé propre à l'appareil. L'APK de version est
signé avec la clé de débogage : suffisant pour une installation personnelle,
une clé dédiée serait nécessaire pour le Play Store.

Au premier lancement, l'application ouvre les Réglages : renseigner l'adresse RPC
(ex. `https://serveur:9091/transmission/rpc` ; sans chemin, `/transmission/rpc`
est ajouté) et la clé API C411.

## Architecture

```
lib/
├── main.dart                  Chargement des préférences, ProviderScope
├── core/
│   ├── format.dart            Formatage (octets, vitesses, durées, dates) en français
│   ├── preferences.dart       Préférences d'interface (thème, grille/liste, tracker)
│   ├── release_name.dart      Titre, année, résolution… extraits d'un nom de release
│   ├── bencode.dart           Lecture des fichiers .torrent (bencode)
│   └── settings.dart          Réglages + persistance dans le trousseau
├── api/
│   ├── tracker.dart           Modèle commun (Release…), interface TrackerApi, liste des trackers
│   ├── c411.dart              Client API JSON de C411
│   ├── c411_socket.dart       Client WebSocket (Socket.IO minimal) des notifications
│   ├── c411_chat.dart         API de discussion (salons, historique) et modèle des messages
│   ├── torznab.dart           Client Torznab générique (tr4ker)
│   └── transmission.dart      Client RPC Transmission + modèle Torrent
├── state/                     Logique (Riverpod)
│   ├── releases.dart          Pagination/filtres des sorties, envoi vers Transmission
│   ├── cross_seed.dart        Analyse et ajout des cross-seeds
│   ├── notifications.dart     Connexion WebSocket et liste des notifications
│   ├── speed_history.dart     Historique des vitesses (enregistré par l'app)
│   └── torrents.dart          Polling Transmission, détail, statistiques
└── ui/                        Écrans
    ├── home_shell.dart        Navigation (barre en bas / rail latéral ≥ 720 px)
    ├── releases_page.dart, release_detail_page.dart
    ├── downloads_page.dart, torrent_detail_page.dart
    ├── settings_page.dart, server_settings_page.dart
    ├── send_button.dart       Bouton « Télécharger » (état d'envoi, options)
    ├── torrent_actions.dart   Menu et dialogues d'actions sur les torrents
    ├── bandwidth_groups_page.dart  Groupes de bande passante
    ├── cross_seed_page.dart   Cross-seed (analyse, résultats, ajout)
    ├── charts.dart            Graphiques (courbe des vitesses, barres, jauge)
    ├── stats_page.dart        Statistiques
    ├── notifications_page.dart  Notifications
    ├── rich_text.dart         Mise en forme des messages (gras, liens, mentions…)
    ├── theme.dart             Palette (AppColors) et thème clair / sombre
    └── widgets.dart           Composants partagés (Tag, Poster, Section…)
```

Stack : Flutter, `flutter_riverpod` (état), `dio` (HTTP),
`flutter_secure_storage` (secrets), `cached_network_image` (affiches),
`shared_preferences` (préférences d'interface). Police Inter intégrée
(`assets/fonts/`, licence OFL).

### Style

Thème inspiré de c411.org (couleurs relevées sur le site) : fond vert très
sombre `#061712`, cartes `#101E19` à bord fin `#21352C`, accent vert C411
`#00D492` avec texte sombre par-dessus (le blanc y serait illisible), texte
`#F4FFF8` / secondaire `#9DB9AC`. Salon : bulles `#013226`, citations
`#01402F` à liseré vert, pseudos colorés selon le rang (`nameTone` : bronze,
argent, or). Variante claire dans le même esprit. Widgets Flutter sans
l'apparence Material : pas d'ombre ni d'effet d'onde, police Inter. Toutes les
couleurs sont définies dans `AppColors` (`lib/ui/theme.dart`) et accessibles via
`context.colors`.

Graphiques : réception et envoi utilisent une paire de couleurs dédiée
(`download` / `upload`, bleu / orange), validée pour le daltonisme et le
contraste sur les fonds clair et sombre, distincte des couleurs d'état. Les
textes restent dans les couleurs de texte ; seuls les traits et les repères
portent la couleur de la série.

La police Inter (graisses 400 à 800) est intégrée à l'application plutôt que
chargée par `google_fonts` : pas de téléchargement au démarrage, rendu
identique hors ligne. (`google_fonts` 9 échouait à charger la police selon le
mode de lancement — « Unable to load asset: AssetManifest.bin ».)

### Choix pour rester léger

- **Listes virtualisées** (`ListView.builder` + hauteur de ligne fixe) : seules
  les lignes visibles sont construites. La hauteur des lignes est calculée
  d'après la taille de police du système (`ReleaseRow.extent`,
  `_TorrentRow.extent`) et les textes ont un interligne explicite : une ligne
  ne déborde jamais, même avec une grande police Android (test
  `row_layout_test.dart`).
- **Transferts** : seuls la liste et le bloc des vitesses suivent les
  rafraîchissements (toutes les 2 s) ; en-tête, puces et recherche ne se
  reconstruisent pas. Les lignes dont le torrent n'a pas changé sont
  réutilisées telles quelles (même objet `Torrent` d'un rafraîchissement à
  l'autre). Mesuré : 1 163 éléments reconstruits par rafraîchissement avant,
  154 après (20 torrents modifiés sur 424).
- **Affiches** : vignette TMDB à la taille affichée (`tmdbSized` : `w154` /
  `w185` en liste, `w342` en grille au lieu de `w500`), décodée à cette taille
  (`memCacheWidth`), mise en cache, coins arrondis dessinés avec l'image (pas
  de découpe séparée).
- **Onglets masqués** : Riverpod 3 met en pause les écrans hors de vue (ils ne
  se reconstruisent pas en arrière-plan).
- **Pas d'info-bulle dans les lignes de liste** : coût par élément, et sur
  mobile elle capterait l'appui long (options d'ajout du bouton ⬇).
- **Transmission** : `torrent-get` ne demande que les champs affichés ; les
  rafraîchissements utilisent `ids: "recently-active"` (seuls les torrents
  modifiés reviennent, `removed` signale les suppressions). Une liste complète
  est rechargée toutes les 15 itérations et après chaque action. Les champs
  lourds (fichiers, pairs, trackers) ne sont chargés que sur l'écran de détail.

## Notes sur les API

### Ajouter un tracker

Les trackers sont listés dans l'enum `Tracker` (`lib/api/tracker.dart`). Pour un
tracker Torznab, il suffit d'y ajouter une ligne (nom + URL de l'endpoint) et de
la brancher sur `TorznabApi` dans `Tracker.client`. La page Réglages et le
sélecteur de l'onglet Sorties s'adaptent automatiquement.

### tr4ker (Torznab)

- Endpoint : `https://tr4ker.net/api/` (`/api` redirige vers `/api/`).
  `/api/torznab` est déprécié ; `/api/torznab/all` inclut les torrents sans
  seeder (cross-seed), non utilisé ici.
- Authentification : en-tête `X-Api-Key: <clé>` (doc tr4ker) ; la clé est aussi
  passée en paramètre `apikey` (convention Torznab). Exigée même pour `t=caps`
  (sinon HTTP 401).
- Torznab ne donne ni affiche TMDB ni infos techniques : titre, année,
  résolution, source, codec et langues sont déduits du nom de la release
  (`ReleaseName`). Freeleech = `downloadvolumefactor` à 0. Pas de tri serveur.
- Les erreurs Torznab arrivent en HTTP 200 sous la forme
  `<error code="100" description="…"/>`.

### C411 : WebSocket des notifications

- `wss://c411.org/ws/?EIO=4&transport=websocket` : Socket.IO, transport
  WebSocket uniquement (le polling répond « Transport unknown »).
- L'en-tête `Origin: https://c411.org` est obligatoire (sinon fermeture
  immédiate, code 1006).
- Authentification **par cookie de session du site uniquement** : la clé API
  est refusée (header Bearer, `auth` Socket.IO ou paramètre d'URL). Sans
  cookie : `44{"message":"Authentication required","data":{"code":"no_cookies"}}` ;
  cookie inconnu : `no_session_cookie`. L'application envoie l'en-tête Cookie
  copié depuis le navigateur ; il faut le recoller à l'expiration de la session.
- Échanges : `0{…pingInterval…}` → `40` → `40{sid}` (accepté) ou `44{…}`
  (refusé) ; `2` → `3` (ping/pong) ; `42["événement", données]`.
- Événements observés : `unread:update` (compteurs `privateMessages`,
  `channelMessages`, `pendingRequests`, `staffMessages`, `total`),
  `channel:message` (message de salon, parfois envoyé deux fois : dédoublonné
  par `id`), `channel:typing`, `channel:viewers`, `stats:update` (`uploaded`,
  `downloaded`, `upload_credit` et `user_id` du compte), `channel:reaction`
  (`messageId`, liste complète des réactions avec `userIds` / `usernames`,
  émoticônes du site sous forme `:nom:`). Les événements inconnus sont
  affichés tels quels comme notifications.
- Salons : le client émet `42["channel:join",{"channelId":N}]` (et
  `channel:leave` pour l'ancien) ; le serveur ne diffuse les messages d'un
  salon qu'aux clients qui l'ont rejoint. L'application rejoint à nouveau son
  salon après chaque reconnexion.
- Le contenu des messages est encodé en HTML (`c&#x27;est`) : décodé avant
  affichage.
- Notifications : `GET /api/notifications?offset=N&perPage=M` →
  `data[]` (`id`, `type`, `title`, `message`, `link`, `data`, `isRead`,
  `createdAt`) et `meta` (`hasMore`, `unreadCount`). Types observés :
  `vtr_initialized`, `token_attribution`, `ic_level_up`, `channel_reply`.
- API de discussion (même cookie de session ; 401 sinon) :
  `GET /api/messages/channels` (salons par espace : nom, description,
  couleur, `isDefault`, `canWrite`…) et
  `GET /api/messages/channels/{id}?limit=N` (derniers messages du plus ancien
  au plus récent, salon avec `pinnedMessage`). L'historique est rechargé à
  chaque changement de salon et après chaque reconnexion, puis fusionné avec
  le direct par `id`. Avatars et images `/uploads/…` sont publics.
- Envoi : événement avec accusé de réception
  `42<n>["channel:send",{"channelId":1,"content":"…","tempId":"temp-<ms>-<9 car.>"}]`
  → `43<n>[{"success":true,"messageId":…,"tempId":…,"status":"sent"}]`. Le
  message est aussi diffusé en `channel:message` avec le même `tempId`, ce qui
  permet de remplacer la version affichée d'avance.

### C411 : API HTTP

Deux API coexistent, avec **deux modes d'authentification différents** :

| Usage | Endpoint | Auth |
|---|---|---|
| Liste des sorties (JSON riche : TMDB, tech…) | `GET /api/torrents` | `Authorization: Bearer <clé>` |
| Catégories | `GET /api/categories` | Bearer |
| Téléchargement du `.torrent` | `GET /api?t=get&id=<infoHash>&apikey=<clé>` | paramètre `apikey` (le Bearer y est refusé) |

Paramètres de `/api/torrents` constatés : `page`, `perPage`, `cat` (catégorie),
`subcat` (sous-catégorie), `name` (recherche), `sortBy` (`createdAt`,
`seeders`, `leechers`, `completions`, `size`, `name`, `comments`) et
`sortOrder` (`asc` / `desc`, défaut `desc`). La réponse contient `data[]` et `meta` (`page`, `totalPages`, `total`,
compteurs par catégorie). `limit` est ignoré.

Limite : 120 requêtes / minute par clé (Torznab inclus).

Le `.torrent` est envoyé à Transmission en `metainfo` (base64) plutôt qu'en
magnet : sur un tracker privé, c'est le `.torrent` qui contient le passkey.

### Transmission RPC

- Protocole JSON `{method, arguments}` en POST sur `/transmission/rpc`.
- Protection CSRF : la première requête reçoit un `409` avec l'en-tête
  `X-Transmission-Session-Id`, que le client renvoie ensuite (rejeu automatique).
- Authentification Basic si un utilisateur est renseigné.
- Le client utilise le protocole historique (clés kebab-case). Transmission
  4.1 introduit JSON-RPC 2.0 et le snake_case, mais accepte toujours l'ancien
  format ; la migration sera nécessaire avant Transmission 5.
- `test/fixtures/` contient des réponses réelles d'un `transmission-daemon`
  4.0.5 (session, statistiques, détail d'un torrent), utilisées par les tests
  d'interface.
- Champs inconnus d'une version (ex. `sequentialDownload`, 4.1) : ignorés par
  le serveur ; l'option correspondante n'est simplement pas affichée.
- Valeurs spéciales : `eta` et `uploadRatio` valent `-1` (indisponible) ou `-2`
  (infini).

## Tests

```sh
flutter test        # tests unitaires et d'interface
flutter analyze
```

| Fichier | Ce qui est vérifié |
|---|---|
| `parsing_test.dart` | noms de release, dates RFC 822, tri local, tailles TMDB |
| `cross_seed_test.dart` | lecture bencode, origine par les annonces, analyse dans les deux sens, mémoire, ajout |
| `add_files_test.dart` | envoi de `.torrent` : ajoutés, doublons, invalides, refusés |
| `socket_test.dart`, `chat_send_test.dart` | client Socket.IO contre un faux serveur (ping, événements, refus, envoi avec accusé de réception, réessai) |
| `notifications_test.dart`, `chat_test.dart`, `chat_format_test.dart` | trames WebSocket et réponses d'API réelles anonymisées, salon, mise en forme, notifications du site, cache |
| `server_settings_test.dart`, `torrent_detail_test.dart` | écrans de configuration et de détail sur des réponses réelles de `transmission-daemon` 4.0.5 (`test/fixtures/`) |
| `charts_test.dart` | graphiques (survol, info-bulle sans débordement) |
| `row_layout_test.dart` | lignes de liste sans débordement (390 / 1 705 px, police × 1 et × 1,3) |
| `reorder_test.dart`, `smoke_test.dart` | aucune erreur : liste réordonnée à chaque rafraîchissement, app complète (onglets, info-bulles, rafraîchissements) |

Banc d'essai de fluidité (défilement des Transferts et des Sorties, temps de
calcul et de dessin de chaque image), à lancer de préférence sur un téléphone
branché en débogage USB — sur ordinateur, les mesures varient avec la charge
de la machine :

```sh
flutter drive --profile -d <appareil> --driver=test_driver/perf_driver.dart \
  --target=integration_test/scroll_perf_test.dart   # résultats : build/perf/*.json
```

Après l'ajout d'un paquet à code natif (`file_selector`, `url_launcher`…), un
redémarrage à chaud ne suffit pas : relancer `flutter run`.

## Sécurité

- Aucun secret dans le dépôt : clé API et identifiants sont saisis dans
  l'application et stockés dans le trousseau du système.
- L'onglet Trackers n'affiche que l'hôte, jamais l'URL d'annonce (qui contient
  le passkey).
- Le cookie de session C411 donne un accès complet au compte : il n'est saisi
  que dans l'application (trousseau), jamais journalisé.
- Android : sauvegarde Google désactivée pour ne pas exporter les secrets ;
  trafic HTTP autorisé uniquement parce que l'adresse RPC de Transmission est
  souvent en `http://` (dans ce cas le mot de passe Transmission circule en
  clair : préférer `https://`).

## Pistes

- Mesurer la fluidité sur téléphone avec le banc d'essai.
- Marquer les notifications du site comme lues (requête à identifier).
- Répondre à un message et réagir depuis le salon (trames à identifier) ;
  remonter plus loin dans l'historique d'un salon (pagination à identifier).
- Cross-seed des releases renommées (`torrent-rename-path` après ajout).
- Glisser-déposer de fichiers `.torrent` sur la fenêtre (ordinateur).
- Icône d'application dédiée ; clé de signature pour une diffusion publique.
- Notifications système quand l'application est fermée (service de fond).
- Tableau de bord du profil C411 (`/api/user/profile`, scope `profile:read`).
