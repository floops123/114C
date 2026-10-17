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
- Ajout par lien magnet ou URL, et envoi depuis un tracker, avec options :
  dossier, étiquettes, priorité, en pause.
- Détail en 5 onglets :
  - Infos : progression, carte des pièces, transfert, origine des pairs
    (tracker, DHT, PEX…), dates, créateur, hash ;
  - Fichiers : sélection, priorité par fichier, renommage (`torrent-rename-path`) ;
  - Pairs : client, progression, vitesses, chiffrement, µTP, entrant ;
  - Trackers : annonces et scrapes, paliers, édition de la liste (`trackerList`) ;
  - Options : priorité, limites de vitesse, groupe de bande passante, ratio et
    inactivité propres au torrent, nombre de pairs.

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
  - Notifications : une alerte quand un compteur de non-lus du site augmente
    (message privé, salon, demande, staff), compteurs actuels, encadré
    « Mon compte » mis à jour en direct (envoyé, reçu, crédit, ratio) ;
    historique local des 500 dernières (conservé entre deux lancements,
    consultable hors ligne), groupé par jour, « Afficher plus anciennes » ;
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
| Android, iOS, Windows, macOS | projet généré, non testé |
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

Thème maison « appli média » construit sur les widgets Flutter mais sans
l'apparence Material : fond sombre profond (ou clair), cartes à bord fin sans
ombre, pas d'effet d'onde, police Inter, une seule couleur d'accent. Toutes les
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

- **Listes virtualisées** (`ListView.builder` + `itemExtent` fixe) : seules les
  lignes visibles sont construites.
- **Affiches décodées à la taille affichée** (`memCacheWidth`) et mises en cache.
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

## Sécurité

- Aucun secret dans le dépôt : clé API et identifiants sont saisis dans
  l'application et stockés dans le trousseau du système.
- L'onglet Trackers n'affiche que l'hôte, jamais l'URL d'annonce (qui contient
  le passkey).

## Pistes

- Build et test Android.
- Ajout d'un `.torrent` depuis un fichier local.
- Choix du dossier de destination à l'envoi.
- Tableau de bord du profil C411 (`/api/user/profile`, scope `profile:read`).
- Notifications de nouvelles sorties (filtres sauvegardés).
