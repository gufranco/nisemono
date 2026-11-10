#!/bin/sh
set -eu

version=${1:?version required}
root=$(cd "$(dirname "$0")/../.." && pwd)
core="${root}/lib/core.sh"

if ! grep -q '^NISEMONO_VERSION=' "${core}"; then
  printf 'no NISEMONO_VERSION assignment found in %s\n' "${core}" >&2
  exit 1
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/nisemono-version-XXXXXX")
sed "s/^NISEMONO_VERSION=\".*\"$/NISEMONO_VERSION=\"${version}\"/" "${core}" >"${tmp}"
cat "${tmp}" >"${core}"
rm -f "${tmp}"

reported=$("${root}/bin/nisemono" --version)
printf 'version set to %s\n' "${reported}"
