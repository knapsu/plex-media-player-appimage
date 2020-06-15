#!/bin/bash
set -e

SCRIPT=$(readlink -f "$0")
SCRIPTDIR=$(dirname "${SCRIPT}")
WORKDIR="${PWD}"

# Load helper functions
source "${SCRIPTDIR}/appimagekit/functions.sh"

# Initialize Qt environment
set +e
source /opt/qt*/bin/qt*-env.sh
set -e

git config --global advice.detachedHead false

# Define build variables
APP="Plex Media Player"
LOWERAPP="plexmediaplayer"
DATE=$(date -u +'%Y%m%d')
FFMPEG_VERSION="4.2.3"
MPV_VERSION="0.32.0"

case "$(uname -i)" in
  x86_64|amd64)
    SYSTEM_ARCH="x86_64"
    SYSTEM_PLATFORM="x64";;
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
    PLATFORM="x64";;
  i?86)
    TARGET_ARCH="i686"
    PLATFORM="x86";;
  *)
    echo "Unsupported target architecture"
    exit 1;;
esac
echo "Target architecture: ${PLATFORM}"

# Display Qt version
qmake --version

# Enable ccache
export PATH="/usr/lib/ccache:${PATH}"
export CCACHE_DIR="${WORKDIR}/cache/ccache"

# Checkout mpv player
cd "${WORKDIR}"
if [[ -d mpv-build ]]; then
  cd mpv-build
  git clean -xdf
  git fetch -t
  git checkout master
  git pull
  cd ..
else
  git clone https://github.com/mpv-player/mpv-build.git
fi

# Checkout Plex Media Player
cd "${WORKDIR}"
if [[ -d plex-media-player ]]; then
  cd plex-media-player
  git clean -xdf
  git fetch -t
  git checkout master
  git pull
  cd ..
else
  git clone --branch master https://github.com/plexinc/plex-media-player.git
fi

# If building from tag use a specific version of Plex Media Player sources
cd plex-media-player
if [[ -n "${PLEX_TAG}" ]]; then
  echo "Checkout from tag: ${PLEX_TAG}"
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

# Build mpv library
cd "${WORKDIR}/mpv-build"
echo "Using ffmpeg ${FFMPEG_VERSION}"
./use-ffmpeg-custom "n${FFMPEG_VERSION}"
echo "Using mpv ${MPV_VERSION}"
./use-mpv-custom "v${MPV_VERSION}"
echo "Using libass 0.14.0"
./use-libass-custom 0.14.0

# FFmpeg requires this for NVIDIA support
echo "Downloading NVIDIA headers"
if [[ -d ffnvcodec ]]; then
  cd ffnvcodec
  git clean -xdf
  git fetch -t
  git checkout n9.0.18.3
  cd ..
else
  git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git ffnvcodec
fi

# FFmpeg build options
echo "--disable-doc" > ffmpeg_options
echo "--disable-programs" >> ffmpeg_options
echo "--disable-encoders" >> ffmpeg_options
echo "--disable-muxers" >> ffmpeg_options
echo "--disable-devices" >> ffmpeg_options
echo "--disable-vaapi" >> ffmpeg_options
echo "--enable-vdpau" >> ffmpeg_options
echo "--enable-cuda" >> ffmpeg_options

# mpv build options
echo "--prefix=/usr" > mpv_options
echo "--enable-libmpv-shared" >> mpv_options
echo "--disable-cplayer" >> mpv_options
echo "--disable-build-date" >> mpv_options
echo "--disable-manpage-build" >> mpv_options
echo "--disable-vaapi" >> mpv_options
echo "--enable-vdpau" >> mpv_options
echo "--enable-cuda-hwaccel" >> mpv_options
echo "--enable-pulse" >> mpv_options
echo "--enable-alsa" >> mpv_options
echo "--disable-oss-audio" >> mpv_options
echo "--disable-tv" >> mpv_options

cd ffnvcodec
make && make install PREFIX="/usr"
cd ..

./rebuild
./install

# Build Plex Media Player
cd "${WORKDIR}/plex-media-player"
rm -rf build
mkdir -p build
cd build
cmake \
  -DCMAKE_BUILD_TYPE="Release" \
  -DCMAKE_INSTALL_PREFIX="/usr" \
  -DQTROOT="${QTDIR}" \
  ..
make

mkdir -p install
make install DESTDIR=install

# Show build cache statistics
ccache -s

# Prepare AppImage working directory
mkdir -p "${WORKDIR}/appimage"
cd "${WORKDIR}/appimage"
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
cp "${WORKDIR}/plex-media-player/resources/images/icon.svg" "${APPDIR}/${LOWERAPP}.svg"
cp "${WORKDIR}/plex-media-player/resources/images/icon.png" "${APPDIR}/${LOWERAPP}.png"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"
cp "${WORKDIR}/plex-media-player/resources/images/icon.png" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/${LOWERAPP}.png"
cd "${APPDIR}"
get_apprun
get_desktopintegration "${LOWERAPP}" "${SCRIPTDIR}/appimagekit/desktopintegration.sh"
cd "${OLDPWD}"

# Bundle libraries
cd "${WORKDIR}/appimage"
./linuxdeployqt "${APPDIR}/usr/bin/plexmediaplayer" -qmldir="../plex-media-player/src/ui" -bundle-non-qt-libs
./linuxdeployqt "${APPDIR}/usr/bin/pmphelper" -bundle-non-qt-libs

cd "${APPDIR}"
rm -rf usr/share/doc
# Fix: linuxdeployqt overwrites AppRun binary
rm -f AppRun
get_apprun
# Fix: remove problematic libraries
rm -f usr/lib/libEGL*
rm -f usr/lib/libnss*
rm -f usr/lib/libfribidi*
rm -f usr/lib/libxcb-dri2*
rm -f usr/lib/libxcb-dri3*
cd "${OLDPWD}"

# Create AppImage
APPIMAGE_FILE_NAME="Plex_Media_Player_${VERSION}_${PLATFORM}.AppImage"
cd "${WORKDIR}/appimage"
./appimagetool -n "${APPDIR}"
mv "Plex_Media_Player-${TARGET_ARCH}.AppImage" "${WORKDIR}/${APPIMAGE_FILE_NAME}"

cd "${WORKDIR}"
sha1sum ${APPIMAGE_FILE_NAME}

# Remember last source code version used by scheduled build
if [[ "${TRAVIS}" == "true" ]]; then
  mkdir -p "${WORKDIR}/cache"
  echo -n "${CURRENT_HASH}" > "${WORKDIR}/cache/commit-hash"
fi
