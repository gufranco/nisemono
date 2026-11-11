#!/bin/sh
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
image="${NISEMONO_TEST_IMAGE:-ubuntu:26.04}"

docker run --rm --privileged \
  -v "${repo}:/repo" \
  -w /repo \
  -e NISEMONO_TEST_SHELLS="${NISEMONO_TEST_SHELLS:-}" \
  -e NISEMONO_TEST_RECORD="${NISEMONO_TEST_RECORD:-}" \
  "${image}" \
  sh -c '
    set -eu
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq --no-install-recommends \
      bats zsh dash openssl util-linux eject mount udev sudo ca-certificates git \
      dosfstools fdisk xz-utils zstd bzip2 libarchive-tools qemu-utils curl python3 procps dmsetup \
      mtools exfatprogs wimtools xorriso mandoc >/dev/null
    i=0
    while [ "$i" -lt 64 ]; do
      [ -e "/dev/loop$i" ] || mknod -m 660 "/dev/loop$i" b 7 "$i"
      i=$((i + 1))
    done
    for stale in $(dmsetup ls 2>/dev/null | awk '"'"'/^nisemono-fake-/ { print $1 }'"'"'); do
      dmsetup remove "$stale" 2>/dev/null || :
    done
    exec "$@"
  ' sh "$@"
