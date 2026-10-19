# Compilation personnalisée

[← Sommaire](../README.md)

C411 Remote peut être compilé dans une **variante personnelle** : au
premier lancement, les réglages passés à la compilation sont écrits dans
le trousseau du système (libsecret, Keychain, Keystore), comme si
l'utilisateur venait de les saisir. Les lancements suivants lisent depuis
le trousseau et les modifications faites dans *Réglages* priment toujours.

Le mécanisme utilise les `--dart-define` de Flutter, qui injectent des
constantes au moment de la compilation. Les valeurs sont lues par
[`lib/build_defaults.dart`](../../lib/build_defaults.dart) et appliquées
par [`lib/core/settings.dart`](../../lib/core/settings.dart) au premier
chargement de `settingsProvider` quand le trousseau est vide.

## Utilisation

```sh
flutter build apk \
  --dart-define=C411_RPC_URL=http://seedbox.local:9091/transmission/rpc \
  --dart-define=C411_RPC_USER=admin \
  --dart-define=C411_RPC_PASSWORD=**** \
  --dart-define=C411_C411_KEY=**** \
  --dart-define=C411_TR4KER_KEY=**** \
  --dart-define=C411_NOSTRADAMUS_KEY=**** \
  --dart-define=C411_ASTRATORRENT_KEY=**** \
  --dart-define=C411_SESSION_COOKIE=connect_sid=**** \
  --dart-define=C411_TMDB_KEY=**** \
  --dart-define=C411_JELLYFIN_URL=http://seedbox.local:8096 \
  --dart-define=C411_JELLYFIN_KEY=**** \
  --dart-define=C411_FTP_HOST=app.seedbox.local \
  --dart-define=C411_FTP_USER=**** \
  --dart-define=C411_FTP_PASSWORD=**** \
  --dart-define=C411_FTP_TLS=true \
  --dart-define=C411_MEDIA_FOLDERS=/torrents/completed,/data/media
```

L'APK produit, installé sur un appareil vierge, ouvre les Réglages
préremplis. L'utilisateur peut encore modifier n'importe quel champ — les
valeurs sont écrites dans le trousseau et les `--dart-define` n'ont plus
d'effet.

## Variables disponibles

Toutes les variables sont facultatives. Une seule suffit à activer la
variante ; les autres champs restent vides et l'utilisateur les saisit
lui-même.

| Variable                       | Champ `AppSettings`    | Exemple |
|--------------------------------|------------------------|---------|
| `C411_RPC_URL`                 | `rpcUrl`               | `http://seedbox:9091/transmission/rpc` |
| `C411_RPC_USER`                | `rpcUser`              | `admin` |
| `C411_RPC_PASSWORD`            | `rpcPassword`          | `secret` |
| `C411_SESSION_COOKIE`          | `sessionCookie`        | `connect_sid=abc; session=def` |
| `C411_TMDB_KEY`                | `tmdbKey`              | clé API TMDB ou jeton de lecture |
| `C411_JELLYFIN_URL`            | `jellyfinUrl`          | `http://seedbox:8096` |
| `C411_JELLYFIN_KEY`            | `jellyfinKey`          | clé API Jellyfin |
| `C411_FTP_HOST`                | `ftpHost`              | `app.seedbox.local` |
| `C411_FTP_PORT`                | `ftpPort`              | `21` |
| `C411_FTP_USER`                | `ftpUser`              | utilisateur FTP |
| `C411_FTP_PASSWORD`            | `ftpPassword`          | mot de passe FTP |
| `C411_FTP_TLS`                 | `ftpTls`               | `true` / `false` |
| `C411_MEDIA_FOLDERS`           | `mediaFolders`         | `/films,/series` (CSV) |
| `C411_<TRACKER>_KEY`           | `apiKeys[<tracker>]`   | clé API ou passkey |

`<TRACKER>` est l'un de : `C411`, `TR4KER`, `NOSTRADAMUS`,
`ASTRATORRENT`. La clé est stockée dans `apiKeys` sous le nom en
camelCase du tracker (`c411`, `tr4ker`, …) — l'alignement exact est
maintenu par `BuildDefaults._trackerVars` dans
[`lib/build_defaults.dart`](../../lib/build_defaults.dart) et doit rester
synchronisé avec l'enum `Tracker` de
[`lib/api/tracker.dart`](../../lib/api/tracker.dart).

## Sécurité

Les `--dart-define` sont **compilés dans le binaire**. Toute personne qui
décompile l'APK peut les lire. La règle simple :

- **Distribution publique** : ne mets pas les secrets en `--dart-define`,
  laisse l'utilisateur les saisir dans *Réglages* (et donc les stocker
  dans le trousseau).
- **Installation familiale / poste personnel** : c'est l'usage prévu.
  Le binaire n'est pas partagé.

Si l'utilisateur veut repartir d'un trousseau vierge (pour annuler les
défauts de build), il peut effacer les clés dans *Réglages → Avancé* ou
réinitialiser le trousseau du système d'exploitation ; au prochain
lancement, les `--dart-define` seront réappliqués.

## Mise à jour

Quand un nouveau réglage est ajouté à `AppSettings`, ajouter
simultanément :

1. la constante `String.fromEnvironment('C411_<NOM>')` dans
   `lib/build_defaults.dart`,
2. la lecture correspondante dans `BuildDefaults.toAppSettings()`,
3. l'entrée dans `BuildDefaults.allVariables`,
4. la ligne dans le tableau ci-dessus,
5. un test dans `test/build_defaults_test.dart`.

Sans l'étape 1, le réglage reste vide sur la variante compilée.