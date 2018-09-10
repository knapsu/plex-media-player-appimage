#!/bin/bash
set -e

SCRIPT=$(readlink -f "$0")
SCRIPTDIR=$(dirname "${SCRIPT}")
WORKDIR=${PWD}

# Parse script arguments
while [ $# -gt 0 ]; do
  case "$1" in
    -d | --date)
      CHECK_DATE="$2"; shift 2;;
    *) echo "Invalid argument"; exit 1;;
  esac
done

if [ -n "${CHECK_DATE}" ]; then
    echo "Overriding last check date";
elif [ "${TRAVIS}" == "true" ]; then
  echo "Load last check date"
  if [ -f "${WORKDIR}/cache/last-check" ]; then
    CHECK_DATE=$(cat "${WORKDIR}/cache/last-check")
  fi
else
  echo "Missing last check date";
  exit 1
fi

echo "Last check: ${CHECK_DATE:-never}"
CURRENT_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

if [ -n "${CHECK_DATE}" ]; then

  if [[ ! ${CHECK_DATE} =~ ^([0-9]{4})-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])T([0-1][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9])Z$ ]]; then
    echo "Invalid date format"
    exit 2
  fi

  echo "Retrieving GitHub releases information"
  curl -f -s -S \
    -H "Travis-API-Version: 3" \
    -H "Accept: application/json" \
    -H "Authorization: token ${TRAVIS_API_TOKEN}" \
    -o response.json \
    https://api.github.com/repos/plexinc/plex-media-player/releases
  echo "Parsing data"
  IFS=$'\n' NEW_RELEASES=($(jq -r ".[] | {tag_name, published_at} | select(.published_at >= \"${CHECK_DATE}\") | .tag_name" response.json))
  rm -f response.json

  if [ ${#NEW_RELEASES[@]} -eq 0 ]; then
    echo "No new releases"
  else
    set +e
    for RELEASE in "${NEW_RELEASES[@]}"; do
      echo "Found new release \"${RELEASE}\""
      echo "Notifying Travis CI to schedule a build"

      curl -s -f -X POST \
        -H "Travis-API-Version: 3" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "Authorization: token ${TRAVIS_API_TOKEN}" \
        -d "{ \"request\": { \"branch\": \"master\", \"config\": { \"env\": { \"PLEX_TAG\": \"${RELEASE}\", \"DOCKER_IMAGE\": \"${DOCKER_IMAGE}\" } } } } " \
        -o response.json \
        https://api.travis-ci.org/repo/knapsu%2Fplex-media-player-appimage/requests
      if [[ $? -ne 0 ]]; then
        echo "Request to Travis CI failed"
        TRAVIS_ERROR="true"
      fi
      rm -f response.json
    done
    if [[ -n "${TRAVIS_ERROR}" ]]; then
      exit 3
    fi
    set -e
  fi
fi

if [ "${TRAVIS}" == "true" ]; then
  echo "Save current check date"
  mkdir -p "${WORKDIR}/cache"
  echo -n "${CURRENT_DATE}" > "${WORKDIR}/cache/last-check"
fi
