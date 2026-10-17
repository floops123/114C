# media_kit_video 2.0.1 — correctif C411 Remote

Copie de https://pub.dev/packages/media_kit_video 2.0.1 (licence MIT, voir
LICENSE), sans le dossier `example`, utilisée via `dependency_overrides`.

## Problème

Sous Linux avec Impeller (moteur de rendu par défaut de Flutter 3.47), le
moteur fait son rendu OpenGL dans son propre fil : aucun contexte EGL n'est
actif sur le fil principal quand le plugin crée la sortie vidéo. Le plugin
affiche alors « EGL display or context is invalid » et passe en rendu
logiciel (conversion de chaque image par le processeur, ~5 images/s en 4K).

## Correctif (`linux/video_output.cc`, repères « C411 Remote »)

- Sans contexte actif, le plugin prend le même affichage EGL que Flutter
  (`eglGetPlatformDisplayEXT` sur l'affichage X11 / Wayland de GTK, comme le
  moteur) et choisit lui-même une configuration OpenGL ES.
- Après l'initialisation (et à la libération), il rend son contexte au lieu
  de « restaurer » un contexte Flutter inexistant : le fil de rendu de
  Flutter peut alors l'activer pour dessiner chaque image.

- Sous X11, GTK garde un contexte GLX actif sur le fil principal : tant
  qu'il l'est, Mesa refuse d'y activer un contexte EGL (`EGL_BAD_ACCESS`,
  0x3002). Le plugin le libère le temps de ses opérations EGL (création et
  libération de la sortie vidéo), puis le rétablit.

Le reste (contexte isolé pour mpv, partage par EGLImage) est inchangé.
À retirer si une version de media_kit_video corrige le problème.
