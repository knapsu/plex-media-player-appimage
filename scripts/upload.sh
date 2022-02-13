#!/bin/bash
set -e

SCRIPT=$(readlink -f "$0")
SCRIPTDIR=$(dirname "${SCRIPT}")
WORKDIR=${PWD}

if [ $# -eq 0 ]; then
  echo "Missing script arguments" >&2
  exit 1
fi
OPTIONS=$(getopt -o '' -l scp,transfer -- "$@")
if [ $? -ne 0 ] ; then
  echo "Invalid script arguments" >&2
  exit 2
fi
eval set -- "$OPTIONS"

while true; do
  case "$1" in
    (--scp)
      UPLOAD_SCP="true"
      shift;;
    (--transfer)
      UPLOAD_TRANSFER="true"
      shift;;
    (--)
      shift; break;;
    (*)
      break;;
  esac
done

if [ ! -f *.AppImage ]; then
  echo "Nothing to upload"
  exit
fi

if [[ "${UPLOAD_TRANSFER}" == "true" ]]; then
  echo "Uploading to https://transfer.sh/"
  curl --upload-file *.AppImage -https://transfer.sh/
  echo
fi

if [[ "${UPLOAD_SCP}" == "true" ]]; then
  echo "Uploading to SCP server"
  SCP_USER=${SCP_USER:=knapsu}
  SCP_SERVER=${SCP_SERVER:?Missing SCP_SERVER variable}
  SCP_PATH=${SCP_PATH:?Missing SCP_PATH variable}
  scp -i keys/id_rsa *.AppImage ${SCP_USER}@${SCP_SERVER}:${SCP_PATH}
fi
