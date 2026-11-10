#!/bin/sh
set -eu

: "${SCREENS_REPO:?}"
demo=/Users/Shared/demo
rm -rf "${demo}"
mkdir -p "${demo}/bin"
cp -f "${SCREENS_REPO}/test/shim/sudo" "${demo}/bin/sudo"
if [ -d /Volumes/USB ]; then
  hdiutil detach -quiet /Volumes/USB
fi
hdiutil create -quiet -size 16m -fs "MS-DOS FAT16" -volname USB -layout MBRSPUD "${demo}/usb.dmg"
listing=$(hdiutil attach "${demo}/usb.dmg")
device=$(printf '%s\n' "${listing}" | awk 'NR == 1 { print $1 }')
mkdir -p /Volumes/USB/Photos
for name in beach sunset family dog; do
  head -c 131072 /dev/urandom >"/Volumes/USB/Photos/${name}.jpg"
done
sync
printf 'DISK=%s\n' "${device##*/}" >"${demo}/demo.env"
