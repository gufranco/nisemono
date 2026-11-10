#!/bin/sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
SCREENS_REPO=$(cd "${here}/.." && pwd)
export SCREENS_REPO
demo=/Users/Shared/demo

system=$(uname -s)
if [ "${system}" != Darwin ]; then
  printf 'screens: the screens are recorded on macOS, where every disk tool runs against a disk image.\n' >&2
  exit 1
fi
for tool in vhs magick; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    printf 'screens: %s is not installed. install it with: brew install vhs imagemagick\n' "${tool}" >&2
    exit 1
  fi
done

cd "${here}"
status=0
for source in *.tape *.tape.in; do
  [ -f "${source}" ] || continue
  [ "${source}" != common.tape ] || continue
  name=${source%%.tape*}
  sh ./prepare.sh
  tape="${source}"
  if [ "${source}" = "${name}.tape.in" ]; then
    disk=$(sed -n 's/^DISK=//p' "${demo}/demo.env")
    tape="${name}.rendered.tape"
    sed "s/@DISK@/${disk}/g" "${source}" >"${tape}"
  fi
  if ! vhs "${tape}" >/dev/null 2>&1; then
    printf 'screens: %s did not record.\n' "${source}" >&2
    status=1
  fi
  rm -f ./*.rendered.tape scratch.gif
  sh ./cleanup.sh
done
sh ./finish.sh ./*.png
exit "${status}"
