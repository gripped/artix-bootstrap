#!/bin/bash
#
# artix-bootstrap: Bootstrap a base Artix Linux system using any GNU distribution.
#
# Dependencies: bash >= 4, coreutils, wget, sed, gawk, tar, gzip, chroot, xz, zstd.
#
# Install:
#
#   # install -m 755 artix-bootstrap.sh /usr/local/bin/artix-bootstrap
#
# Usage:
#
#   # artix-bootstrap destination
#   # artix-bootstrap -i openrc -r http://mirror1.artixlinux.org/repos destination
#
# And then you can chroot to the destination directory (user: root, password: root):
#
#   # chroot destination

set -e -u -o pipefail

# Packages needed by pacman (see get-pacman-dependencies.sh)
PACMAN_PACKAGES=(
  acl artix-keyring artix-mirrorlist bzip2 curl e2fsprogs expat glibc gpgme keyutils krb5 libarchive libassuan libgpg-error libidn2 libnghttp2 libpsl libssh2 libunistring lz4 openssl pacman xz zlib zstd
)
BASIC_PACKAGES=(${PACMAN_PACKAGES[*]} filesystem)
EXTRA_PACKAGES=(coreutils bash grep gawk file tar sed)
DEFAULT_REPO_URL="http://mirror1.artixlinux.org/repos"

stderr() { 
  echo "$@" >&2 
}

debug() {
  stderr "--- $@"
}

extract_href() {
  sed -n '/<a / s/^.*<a [^>]*href="\([^\"]*\)".*$/\1/p'
}

fetch() {
  curl -L -s "$@"
}

fetch_file() {
  local FILEPATH=$1 status_code=
  shift
  if [[ -e "$FILEPATH" ]]; then
    #curl -L -z "$FILEPATH" -o "$FILEPATH" "$@"
    status_code=$(curl --write-out %{http_code} -L -z "$FILEPATH" -o "$FILEPATH" "$@")
  else
    status_code=$(curl --write-out %{http_code} -L -o "$FILEPATH" "$@")
    #curl -L -o "$FILEPATH" "$@"
  fi
  

  if [[ "$status_code" -ne 404 ]] ; then
    return 0
  else
    return 1
  fi
}

uncompress() {
  local FILEPATH=$1 DEST=$2
  
  case "$FILEPATH" in
    *.gz) 
      tar xzf "$FILEPATH" -C "$DEST";;
    *.xz) 
      xz -dc "$FILEPATH" | tar x -C "$DEST";;
    *.zst)
      tar --zstd -xf "$FILEPATH" -C "$DEST";;
    *) 
      debug "Error: unknown package format: $FILEPATH"
      return 1;;
  esac
}  

###

get_default_repo() {
  echo $DEFAULT_REPO_URL
}

get_system_repo_url() {
  local REPO_URL=$1 ARCH=$2
  echo "${REPO_URL%/}/system/os/$ARCH"
}

get_world_repo_url() {
  local REPO_URL=$1 ARCH=$2
  echo "${REPO_URL%/}/world/os/$ARCH"
}

get_galaxy_repo_url() {
  local REPO_URL=$1 ARCH=$2
  echo "${REPO_URL%/}/galaxy/os/$ARCH"
}

get_template_repo_url() {
  local REPO_URL=$1 ARCH=$2
  echo "${REPO_URL%/}/\$repo/os/$ARCH"
}

configure_pacman() {
  local DEST=$1 ARCH=$2
  debug "configure DNS and pacman"
  cp "/etc/resolv.conf" "$DEST/etc/resolv.conf"
  SERVER=$(get_template_repo_url "$REPO_URL" "$ARCH")
  echo "Server = $SERVER" > "$DEST/etc/pacman.d/mirrorlist"
}

configure_minimal_system() {
  local DEST=$1
  
  mkdir -p "$DEST/dev"
  sed -ie 's/^root:.*$/root:$1$GT9AUpJe$oXANVIjIzcnmOpY07iaGi\/:14657::::::/' "$DEST/etc/shadow"
  touch "$DEST/etc/group"
  echo "bootstrap" > "$DEST/etc/hostname"

  rm -f "$DEST/etc/mtab"
  echo "rootfs / rootfs rw 0 0" > "$DEST/etc/mtab"
  test -e "$DEST/dev/null" || mknod "$DEST/dev/null" c 1 3
  test -e "$DEST/dev/random" || mknod -m 0644 "$DEST/dev/random" c 1 8
  test -e "$DEST/dev/urandom" || mknod -m 0644 "$DEST/dev/urandom" c 1 9

  sed -i "s/^[[:space:]]*\(CheckSpace\)/# \1/" "$DEST/etc/pacman.conf"
  sed -i "s/^[[:space:]]*SigLevel[[:space:]]*=.*$/SigLevel = Never/" "$DEST/etc/pacman.conf"
}

fetch_packages_list() {
  local REPO=$1 WORLD_REPO=$2 
  echo "$(fetch_repo_packages_list "$REPO")"
  echo "$(fetch_repo_packages_list "$WORLD_REPO")"
  echo "$(fetch_repo_packages_list "$GALAXY_REPO")"
}

fetch_repo_packages_list() {
  local REPO=$1
  
  debug "fetch packages list: $REPO/"
  fetch "$REPO/" | extract_href | awk -F"/" '{print $NF}' | sort -rn ||
    { debug "Error: cannot fetch packages list: $REPO"; return 1; }
}

install_pacman_packages() {
  local BASIC_PACKAGES=$1 DEST=$2 LIST=$3 DOWNLOAD_DIR=$4
  debug "pacman package and dependencies: $BASIC_PACKAGES"
  
  for PACKAGE in $BASIC_PACKAGES; do
    local FILE=$(echo "$LIST" | grep -Pm1 "^$PACKAGE-([a-zA-Z\d.:%]*)-([\d.]*)-(i686|x86_64|any)\.pkg\.tar\.(gz|xz|zst)$")
    test "$FILE" || { debug "Error: cannot find package: $PACKAGE"; return 1; }
    local FILEPATH="$DOWNLOAD_DIR/$FILE"
    
    debug "download package: $FILE"
    [[ -f "$FILEPATH" ]] || fetch_file "$FILEPATH" "$REPO/$FILE" || fetch_file "$FILEPATH" "$WORLD_REPO/$FILE" || fetch_file "$FILEPATH" "$GALAXY_REPO/$FILE"
    debug "uncompress package: $FILEPATH"
    uncompress "$FILEPATH" "$DEST"
  done
}

install_packages() {
  local ARCH=$1 DEST=$2 PACKAGES=$3
  debug "install packages: $PACKAGES"
  LC_ALL=C mount --types proc /proc "$DEST"/proc
  LC_ALL=C chroot "$DEST" /usr/bin/pacman \
    --noconfirm --arch $ARCH -Sy --overwrite='*' $PACKAGES
  LC_ALL=C umount "$DEST"/proc
}

cleanup_files() {
  DEST=$1
  rm "$DEST/.BUILDINFO" "$DEST/.INSTALL" "$DEST/.MTREE" "$DEST/.PKGINFO"
}

show_usage() {
  stderr "Usage: $(basename "$0") [-q] [-i INIT] [-r REPO_URL] [-d DOWNLOAD_DIR] DESTDIR"
}

main() {
  # Process arguments and options
  test $# -eq 0 && set -- "-h"
  local INIT=
  local ARCH=
  local REPO_URL=
  local DOWNLOAD_DIR=
  local PRESERVE_DOWNLOAD_DIR=
  
  while getopts "qi:r:d:h" ARG; do
    case "$ARG" in
      i) INIT=$OPTARG;;
      r) REPO_URL=$OPTARG;;
      d) DOWNLOAD_DIR=$OPTARG
         PRESERVE_DOWNLOAD_DIR=true;;
      *) show_usage; return 1;;
    esac
  done
  shift $(($OPTIND-1))
  test $# -eq 1 || { show_usage; return 1; }
  
  [[ -z "$INIT" ]] && INIT="openrc"
  [[ -z "$ARCH" ]] && ARCH="x86_64"
  [[ -z "$REPO_URL" ]] && REPO_URL=$(get_default_repo "$ARCH")
  
  local DEST=$1
  local REPO=$(get_system_repo_url "$REPO_URL" "$ARCH")
  local WORLD_REPO=$(get_world_repo_url "$REPO_URL" "$ARCH")
  local GALAXY_REPO=$(get_galaxy_repo_url "$REPO_URL" "$ARCH")
  [[ -z "$DOWNLOAD_DIR" ]] && DOWNLOAD_DIR=$(mktemp -d)
  mkdir -p "$DOWNLOAD_DIR"
  [[ -z "$PRESERVE_DOWNLOAD_DIR" ]] && trap "rm -rf '$DOWNLOAD_DIR'" KILL TERM EXIT
  debug "destination directory: $DEST"
  debug "system repository: $REPO"
  debug "world repository: $WORLD_REPO"
  debug "galaxy repository: $GALAXY_REPO"
  debug "temporary directory: $DOWNLOAD_DIR"
  
  # Fetch packages, install system and do a minimal configuration
  mkdir -p "$DEST"
  local LIST=$(fetch_packages_list $REPO $WORLD_REPO $GALAXY_REPO)
  install_pacman_packages "${BASIC_PACKAGES[*]}" "$DEST" "$LIST" "$DOWNLOAD_DIR"
  configure_pacman "$DEST" "$ARCH"
  configure_minimal_system "$DEST"
  install_packages "$ARCH" "$DEST" "base ${INIT} elogind-${INIT}"
  install_packages "$ARCH" "$DEST" "artix-keyring"
  configure_pacman "$DEST" "$ARCH" # Pacman must be re-configured
  cleanup_files "$DEST"
  [[ -z "$PRESERVE_DOWNLOAD_DIR" ]] && rm -rf "$DOWNLOAD_DIR"
  
  debug "Done!"
  debug 
  debug "You may now chroot or artools-chroot from package artools-base:"
  debug "$ sudo artools-chroot $DEST"
}

main "$@"
