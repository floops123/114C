#!/usr/bin/env bash
# Empaquette la version Linux (déjà compilée par `flutter build linux
# --release`) en un seul fichier exécutable, sous deux formes :
#   C411_Remote-x86_64.AppImage        (appimagetool, SquashFS)
#   C411_Remote-x86_64.dwfs.AppBundle  (pelf, DwarFS : plus petit)
# Même contenu (AppDir) dans les deux.
#
# Embarque libmpv (lecteur) et ses dépendances (ffmpeg…), absents de
# beaucoup de systèmes ; GTK, glibc, OpenGL et le trousseau restent ceux du
# système. linuxdeploy, appimagetool et pelf sont téléchargés dans
# build/appimage/tools s'ils ne sont pas fournis (LINUXDEPLOY, APPIMAGETOOL,
# PELF).
set -euo pipefail

cd "$(dirname "$0")/.."
BUNDLE=build/linux/x64/release/bundle
OUT=build/appimage
APPDIR=$OUT/AppDir
TOOLS=$OUT/tools
NAME=c411_remote

[ -x "$BUNDLE/$NAME" ] || { echo "Compile d'abord : flutter build linux --release" >&2; exit 1; }

mkdir -p "$TOOLS"
fetch() { # fetch <fichier> <url>
  [ -x "$TOOLS/$1" ] || { curl -fsSL -o "$TOOLS/$1" "$2"; chmod +x "$TOOLS/$1"; }
}
LINUXDEPLOY=${LINUXDEPLOY:-$TOOLS/linuxdeploy}
APPIMAGETOOL=${APPIMAGETOOL:-$TOOLS/appimagetool}
PELF=${PELF:-$TOOLS/pelf}
fetch linuxdeploy https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fetch appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
fetch pelf https://github.com/xplshn/pelf/releases/download/196/pelf_x86_64

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/lib" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"
# L'application telle que Flutter la range (exécutable, lib/, data/) :
# ses chemins relatifs ($ORIGIN/lib) restent valables.
cp -r "$BUNDLE" "$APPDIR/app"

# libmpv et ce dont elle dépend, dans usr/lib (liste d'exclusion de
# linuxdeploy : glibc, X11, OpenGL… restent ceux du système).
# (awk lit tout : un arrêt anticipé casserait le tube sous pipefail.)
MPV=$(ldconfig -p | awk '/libmpv\.so\.2 / && !p {p=$NF} END {print p}')
[ -n "$MPV" ] || { echo "libmpv.so.2 introuvable (paquet libmpv2 ou libmpv-dev)" >&2; exit 1; }
APPIMAGE_EXTRACT_AND_RUN=1 "$LINUXDEPLOY" --appdir "$APPDIR" --library "$MPV"
# GTK vient du système : ses propres dépendances (GLib, cairo, pango, X11,
# Wayland…) aussi, sinon deux versions se mélangeraient. Présentes sur tout
# bureau qui a GTK 3.
( cd "$APPDIR/usr/lib" && rm -f \
    libglib-2.0.so* libgio-2.0.so* libgobject-2.0.so* libgmodule-2.0.so* libgthread-2.0.so* \
    libcairo*.so* libpango*.so* libharfbuzz*.so* libfreetype.so* libfontconfig.so* \
    libpixman-1.so* libpng16.so* libgdk_pixbuf*.so* libatk*.so* libepoxy.so* \
    libX*.so* libxcb*.so* libxkbcommon*.so* libwayland-*.so* libdrm*.so* libgbm.so* \
    libEGL*.so* libGL*.so* libGLX*.so* libgcc_s.so* libstdc++.so* libdbus-1.so* \
    libffi.so* libpcre2-8.so* libmount.so* libblkid.so* libselinux.so* libsystemd.so* \
    libudev.so* libexpat.so* libz.so* libbz2.so* liblzma.so* libzstd.so* )

cp linux/packaging/$NAME.desktop "$APPDIR/usr/share/applications/"
cp linux/packaging/$NAME.desktop "$APPDIR/"
cp linux/packaging/$NAME.png "$APPDIR/usr/share/icons/hicolor/256x256/apps/"
cp linux/packaging/$NAME.png "$APPDIR/$NAME.png"
cp linux/packaging/$NAME.png "$APPDIR/.DirIcon"

cat > "$APPDIR/AppRun" <<'RUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/app/c411_remote" "$@"
RUN
chmod +x "$APPDIR/AppRun"

ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" --no-appstream "$APPDIR" "$OUT/C411_Remote-x86_64.AppImage"

# AppBundle : même AppDir. Identifiant : application, date d'empaquetage.
rm -f "$OUT/C411_Remote-x86_64.dwfs.AppBundle"
"$PELF" --add-appdir "$APPDIR" \
  --appbundle-id "fr.c411remote.c411_remote-$(date +%Y%m%d)" \
  --output-to "$OUT/C411_Remote-x86_64.dwfs.AppBundle"

echo "→ $OUT/C411_Remote-x86_64.AppImage"
echo "→ $OUT/C411_Remote-x86_64.dwfs.AppBundle"
