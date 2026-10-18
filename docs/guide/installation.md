# Installation

[← Sommaire](../README.md)

C411 Remote est une application Flutter. Elle se compile depuis les sources ;
il n'y a pas (encore) de paquet tout prêt.

## Ce qu'il faut

- **Flutter** 3.47 ou plus récent (Dart ≥ 3.13) — [installer Flutter](https://docs.flutter.dev/get-started/install).
- Un serveur **Transmission** joignable (RPC activé).
- Au moins un compte sur un des trackers pris en charge.

## Linux

Paquets système (Debian, Ubuntu, Mint) :

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  libsecret-1-dev libjsoncpp-dev libmpv-dev
```

| Paquet | Pourquoi |
|---|---|
| `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev` | compilation d'une application Flutter Linux |
| `libsecret-1-dev` | trousseau du système (identifiants) |
| `libjsoncpp-dev` | dépendance du trousseau |
| `libmpv-dev` | lecteur vidéo intégré (mpv) |

Puis, dans le dossier du projet :

```sh
flutter pub get
flutter run -d linux        # lancement en développement (r = rechargement à chaud)
flutter build linux         # version optimisée : build/linux/x64/release/bundle/
```

Le dossier `bundle/` est autonome : copie-le où tu veux et lance
`bundle/c411_remote`.

> **Lecture fluide sous Linux.** Le projet embarque une copie corrigée du
> module vidéo (`third_party/media_kit_video`) : sans elle, avec le moteur de
> rendu Impeller, la vidéo passait en rendu logiciel (~5 images/s en 4K).
> Rien à faire de ton côté, c'est automatique. Détails :
> [C411-PATCH.md](../../third_party/media_kit_video/C411-PATCH.md).

## Android

Le SDK Android peut s'installer sans Android Studio :

```sh
export ANDROID_HOME="$HOME/Android/Sdk"
# Une fois : outils en ligne de commande dans $ANDROID_HOME/cmdline-tools/latest, puis
sdkmanager --install "platform-tools" "platforms/android-36" \
  "build-tools/36.1.0" "ndk/28.2.13676358"
flutter config --android-sdk "$ANDROID_HOME"

flutter build apk --release --split-per-abi   # → build/app/outputs/flutter-apk/
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Pour développer avec le téléphone branché (débogage USB) :
`flutter run -d <identifiant du téléphone>`.

Ce qui est réglé dans `android/app/src/main/AndroidManifest.xml` :

- permission Internet et trafic HTTP autorisé (l'adresse de Transmission est
  souvent en `http://` ; préfère `https://` quand c'est possible) ;
- ouverture des liens dans le navigateur (`<queries>`) ;
- sauvegarde Google désactivée (`allowBackup=false`) : les secrets sont
  chiffrés par une clé propre à l'appareil, une sauvegarde restaurée ailleurs
  serait illisible.

L'APK est signé avec la clé de débogage : parfait pour un usage personnel, une
clé dédiée serait nécessaire pour le Play Store.

## Autres plateformes

| Plateforme | État |
|---|---|
| iOS, macOS, Windows | projets générés, jamais testés |
| Web | non prise en charge : Transmission et les trackers refusent les requêtes venant d'un navigateur (pas d'en-têtes CORS) |

## Et ensuite ?

Au premier lancement, l'application ouvre les **Réglages**. Suis le guide de
[configuration](configuration.md).
