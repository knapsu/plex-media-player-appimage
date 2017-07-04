#!/bin/bash
set -e

SCRIPT=$(readlink -f "$0")
SCRIPTDIR=$(dirname "$SCRIPT")
WORKDIR=${PWD}

APP="Plex Media Player"
LOWERAPP="plexmediaplayer"

# Load helper functions
source "$SCRIPTDIR/functions.sh"

# Initialize Qt environment
set +e
source "/opt/qt59/bin/qt59-env.sh"
set -e

# Define build variables
CURRENT_DATE=$(date -u +'%Y%m%d')

case "$(uname -i)" in
  x86_64|amd64)
    SYSTEM_ARCH="x86_64"
    SYSTEM_ARCHX="x86-64";;
  i?86)
    SYSTEM_ARCH="i686"
    SYSTEM_ARCHX="x86";;
  *)
    echo "Unsupported system architecture"
    exit 1;;
esac
echo "System architecture: ${SYSTEM_ARCHX}"

case "${ARCH:-$(uname -i)}" in
  x86_64|amd64)
    TARGET_ARCH="x86_64"
    TARGET_ARCHX="x86-64";;
  i?86)
    TARGET_ARCH="i686"
    TARGET_ARCHX="x86";;
  *)
    echo "Unsupported target architecture"
    exit 1;;
esac
echo "Target architecture: ${TARGET_ARCHX}"

# Build mpv player
cd "${WORKDIR}"
if [ -d mpv-build ]; then
  cd mpv-build
  git clean -xf
  git checkout master
  git pull
else
  git clone https://github.com/mpv-player/mpv-build.git
  cd mpv-build
fi

echo "--prefix=/usr" > mpv_options
echo "--enable-libmpv-shared" >> mpv_options
echo "--disable-cplayer" >> mpv_options
./rebuild
./install

# Build Plex Media Player
cd "${WORKDIR}"
if [ -d plex-media-player ]; then
  cd plex-media-player
  git clean -xf
  git checkout master
  git pull
else
  git clone https://github.com/plexinc/plex-media-player.git
  cd plex-media-player
fi

# if on travis and release tag detected, build from this tag
# TODO
COMMIT_HASH=$(git log -n 1 --pretty=format:'%h')

rm -rf build 
mkdir -p build
cd build
conan install ..
cmake -DCMAKE_BUILD_TYPE=Release -DQTROOT="${QTDIR}" -DCMAKE_INSTALL_PREFIX=/usr ..
make
mkdir -p install
make install DESTDIR=install

# Prepare working directory
cd "${WORKDIR}"
mkdir -p "appimage"
cd "appimage"
download_linuxdeployqt

# Initialize AppDir
rm -rf "AppDir"
mkdir "AppDir"
APPDIR="${PWD}/AppDir"

# Copy binaries
cp -pr "${WORKDIR}/plex-media-player/build/install/"* "${APPDIR}"
ln -s "../share/plexmediaplayer/web-client" "${APPDIR}/usr/bin/web-client"

# Setup desktop integration (launcher, icon, menu entry)
cp "${WORKDIR}/plexmediaplayer.desktop" "${APPDIR}/${LOWERAPP}.desktop"
cp "${WORKDIR}/plex-media-player/resources/images/icon.png" "${APPDIR}/${LOWERAPP}.png"

cd "${APPDIR}"
get_apprun
get_desktopintegration ${LOWERAPP}
cd "${OLDPWD}"

# Create AppImage bundle
APPIMAGE_FILE_NAME="Plex_Media_Player_${CURRENT_DATE}_${COMMIT_HASH}_${TARGET_ARCHX}.AppImage"
echo "AppImage file name: ${APPIMAGE_FILE_NAME}"
cd "${WORKDIR}/appimage"
./linuxdeployqt "${APPDIR}/usr/bin/plexmediaplayer" -bundle-non-qt-libs
./linuxdeployqt "${APPDIR}/usr/bin/plexmediaplayer" -qmldir="../plex-media-player/src/ui" -appimage
mv *.AppImage "${WORKDIR}/${APPIMAGE_FILE_NAME}"
ls -l --time-style=long-iso *.AppImage | cut -d" " -f5-
