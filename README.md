# Plex Media Player - Linux AppImage

[![Build Status](https://travis-ci.org/knapsu/plex-media-player-appimage.svg?branch=master)](https://travis-ci.org/knapsu/plex-media-player-appimage)

## Introduction

This repository automates building AppImage packages for Plex Media Player application. 

Packages for x86-64 (64-bit Intel/AMD) architecture are generated daily by Travis CI build system and can be downloaded from https://knapsu.eu/plex/.

## Plex Media Player

Plex is a client-server software that makes it easy to watch different kinds of digital media on all kinds of devices, including living room TV, computer, tablet and even phone.
Plex Media Player is the computer desktop client that connects to Plex Media Server system where your movies and photos are stored.

For more information about Plex please visit https://www.plex.tv/ site.

## AppImage

AppImages is a universal Linux package that can be used in any modern Linux distribution.

For more information about AppImage package please visit http://appimage.org/ site.

## Docker

Directory `docker` contains files used to create a Docker image of a fully functional build environment. This build environment image is used by Travis CI to create and publish the binaries. Using Docker also makes it easy to reproduce builds on other systems.

### Docker images

- [knapsu/plexmediaplayer-build](https://hub.docker.com/r/knapsu/plexmediaplayer-build/)
