#!/bin/bash
set -e

SCRIPT=$(readlink -f "$0")
SCRIPTDIR=$(dirname "${SCRIPT}")
WORKDIR="${PWD}"

# Load helper functions
source "${SCRIPTDIR}/appimagekit/functions.sh"

# Initialize Qt environment
set +e
source "/opt/qt59/bin/qt59-env.sh"
set -e

git config --global advice.detachedHead false

# Define build variables
APP="Plex Media Player"
LOWERAPP="plexmediaplayer"
DATE=$(date -u +'%Y%m%d')

case "$(uname -i)" in
  x86_64|amd64)
    SYSTEM_ARCH="x86_64"
    SYSTEM_PLATFORM="x86-64";;
  i?86)
    SYSTEM_ARCH="i686"
    SYSTEM_PLATFORM="x86";;
  *)
    echo "Unsupported system architecture"
    exit 1;;
esac
echo "System architecture: ${SYSTEM_PLATFORM}"

case "${ARCH:-$(uname -i)}" in
  x86_64|amd64)
    TARGET_ARCH="x86_64"
    PLATFORM="x86-64";;
  i?86)
    TARGET_ARCH="i686"
    PLATFORM="x86";;
  *)
    echo "Unsupported target architecture"
    exit 1;;
esac
echo "Target architecture: ${PLATFORM}"

# Checkout mpv player
cd "${WORKDIR}"
if [[ -d mpv-build ]]; then
  cd mpv-build
  git clean -xdf
  git checkout master
  git pull
else
  git clone https://github.com/mpv-player/mpv-build.git
  cd mpv-build
fi

# Checkout Plex Media Player
cd "${WORKDIR}"
if [[ -d plex-media-player ]]; then
  cd plex-media-player
  git clean -xdf
  git checkout tv2
  git pull
else
  git clone -b tv2 https://github.com/plexinc/plex-media-player.git
  cd plex-media-player
fi

# If building from tag use a specific version of Plex Media Player sources
if [[ -n "${PLEX_TAG}" ]]; then
  echo "Checkout from tag"
  git checkout ${PLEX_TAG}
fi
COMMIT_HASH=$(git log -n 1 --pretty=format:'%h' --abbrev=8)

if [[ "${TRAVIS_EVENT_TYPE}" == "cron" ]]; then
  echo "Scheduled build"
  echo "Checking if source code was modified since last build"

  if [[ -f "${WORKDIR}/cache/commit-hash" ]]; then
    PREVIOUS_HASH=$(cat "${WORKDIR}/cache/commit-hash")
  fi
  echo "Previous source hash: ${PREVIOUS_HASH:-unknown}"

  CURRENT_HASH=$(git log -n 1 --pretty=format:'%H')
  echo "Current source hash: ${CURRENT_HASH}"

  if [[ "${PREVIOUS_HASH}" == "${CURRENT_HASH}" ]]; then
    echo "Source code not modified"
    exit
  fi
elif [[ "${TRAVIS_EVENT_TYPE}" == "api" ]]; then
  echo "Triggered build"
else
  echo "Standard build"
fi

# Define package version string
# When building from tag use number from its name
# In all other situations use current date and commit hash
if [[ -n "${PLEX_TAG}" ]]; then
  VERSION="${PLEX_TAG}"
  if [[ "${VERSION}" =~ ^v[0-9]+ ]]; then
    VERSION=${VERSION:1}
  fi
else
  VERSION="${DATE}_${COMMIT_HASH}"
fi

# Build mpv player
cd "${WORKDIR}/mpv-build"
echo "--prefix=/usr" > mpv_options
echo "--enable-libmpv-shared" >> mpv_options
echo "--disable-cplayer" >> mpv_options
./rebuild
./install

# Build Plex Media Player
cd "${WORKDIR}/plex-media-player"
rm -rf build 
mkdir -p build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DQTROOT="${QTDIR}" -DCMAKE_INSTALL_PREFIX=/usr -DLINUX_X11POWER=on ..
make
mkdir -p install
make install DESTDIR=install

# Prepare AppImage working directory
cd "${WORKDIR}"
mkdir -p "appimage"
cd "appimage"
download_appimagetool
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
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"
cp "${WORKDIR}/plex-media-player/resources/images/icon.png" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/${LOWERAPP}.png"
cd "${APPDIR}"
get_apprun
get_desktopintegration ${LOWERAPP} "${SCRIPTDIR}/appimagekit/desktopintegration.sh"
cd "${OLDPWD}"

# Create AppImage bundle
APPIMAGE_FILE_NAME="Plex_Media_Player_${VERSION}_${PLATFORM}.AppImage"
cd "${WORKDIR}/appimage"
./linuxdeployqt "${APPDIR}/usr/bin/plexmediaplayer" -qmldir="../plex-media-player/src/ui" -bundle-non-qt-libs
./linuxdeployqt "${APPDIR}/usr/bin/pmphelper" -bundle-non-qt-libs
# Fix: linuxdeployqt overwrites AppRun binary
cd "${APPDIR}"
rm -f AppRun
get_apprun
cd "${OLDPWD}"
./appimagetool -n "${APPDIR}"
mv *.AppImage "${WORKDIR}/${APPIMAGE_FILE_NAME}"

cd "${WORKDIR}"
sha1sum *.AppImage

# Remember last source code version used by scheduled build
if [[ "${TRAVIS}" == "true" ]]; then
  mkdir -p "${WORKDIR}/cache"
  echo -n "${CURRENT_HASH}" > "${WORKDIR}/cache/commit-hash"
fi
