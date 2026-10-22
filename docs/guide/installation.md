# Installation

[← Sommaire](../README.md)

C411 Remote est une application Flutter. Elle se compile depuis les sources ;
la CI GitHub produit aussi un APK, une AppImage Linux et une archive Windows.

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

### Un seul fichier : AppImage ou AppBundle

```sh
flutter build linux --release
tool/build_appimage.sh
# → build/appimage/C411_Remote-x86_64.AppImage
# → build/appimage/C411_Remote-x86_64.dwfs.AppBundle
```

Deux formes, même contenu : l'**AppImage** classique, et l'**AppBundle**
de [pelf](https://github.com/xplshn/pelf) (système de fichiers DwarFS, un peu
plus petit : ~90 Mo au lieu de ~100). Sans FUSE, l'AppBundle s'extrait et se
lance quand même.

Le fichier se lance directement (`chmod +x` puis double-clic), sans rien
installer : libmpv et ffmpeg sont embarqués (d'où ~100 Mo). GTK 3, le
trousseau (libsecret) et OpenGL restent ceux du système, présents sur tout
bureau Linux. Il faut une distribution au moins aussi récente que celle de la
compilation (glibc) : Ubuntu 24.04, Debian 13, Fedora 40 ou plus récent pour
l'AppImage de la CI GitHub, publiée avec chaque compilation à côté de
l'archive. Les outils (linuxdeploy, appimagetool, pelf) sont téléchargés
par le script au premier passage.

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

## Windows

La CI GitHub compile la version Windows et publie, à chaque compilation :

- **`C411_Remote-Setup-x64.exe`** : l'installateur, un seul fichier. Il
  installe l'application pour ton compte, sans droits d'administrateur
  (« pour tous les utilisateurs » reste possible), ajoute un raccourci au
  menu Démarrer (et au bureau si tu le coches), et se désinstalle depuis les
  Paramètres de Windows. Une nouvelle version s'installe par-dessus.
- **`c411_remote-windows-x64.zip`** : la même chose sans installation ;
  décompresse et lance `c411_remote.exe`.

Les deux contiennent le runtime Visual C++ et le lecteur (libmpv) : rien
d'autre à installer. L'installateur n'est pas signé : Windows SmartScreen
peut afficher « Windows a protégé votre ordinateur » → *Informations
complémentaires* → *Exécuter quand même*.

Pour le construire soi-même (Visual Studio avec C++ et ATL,
[Inno Setup 6](https://jrsoftware.org/isinfo.php)) :

```powershell
flutter build windows --release
iscc /DAppVersion=1.0.0 windows\packaging\c411_remote.iss
# → build\installer\C411_Remote-Setup-x64.exe
```

## Autres plateformes

| Plateforme | État |
|---|---|
| iOS, macOS | projets générés, jamais testés |
| Web | non prise en charge : Transmission et les trackers refusent les requêtes venant d'un navigateur (pas d'en-têtes CORS) |

## Et ensuite ?

Au premier lancement, l'application ouvre les **Réglages**. Suis le guide de
[configuration](configuration.md).
