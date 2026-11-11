#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
duplicates=$(cat "${root}"/bin/nisemono "${root}"/lib/*.sh |
  sed -n 's/^\([a-z_][a-z0-9_]*\)() {$/\1/p' | sort | uniq -d)
if [ -n "${duplicates}" ]; then
  printf 'function defined more than once:\n%s\n' "${duplicates}" >&2
  exit 1
fi

unprefixed=$(cat "${root}"/bin/nisemono "${root}"/lib/*.sh |
  grep -oE '[$][{]?[A-Z][A-Z0-9_]*' | sed 's/^[$][{]*//' | sort -u |
  grep -vE '^(DISK|NISEMONO)_' | grep -vxE 'HOME|PATH|TMPDIR|NF|ZSH_VERSION|KODOUGU_THEME|KODOUGU_ACCENT|NO_COLOR' || true)
if [ -n "${unprefixed}" ]; then
  printf 'environment variable without the NISEMONO_ prefix:\n%s\n' "${unprefixed}" >&2
  exit 1
fi

scrub="for disk_inherited in \$(env | sed -n 's/^\\(DISK_[A-Za-z0-9_]*\\)=.*/\\1/p'); do"
if ! grep -qF "${scrub}" "${root}/bin/nisemono"; then
  printf 'bin/nisemono must clear every inherited DISK_ variable before it starts\n' >&2
  exit 1
fi

forbidden=$(awk '
  /\$\(dd / && !/tr -d/ { print FILENAME ":" FNR ": a dd read into a variable keeps its NUL bytes" }
  /^[[:space:]]*\}[[:space:]]*>/ { print FILENAME ":" FNR ": a brace group closes on a redirect bashcov cannot count" }
  /done[[:space:]]+[0-9]+</ { print FILENAME ":" FNR ": a loop redirects a fixed descriptor bashcov can take" }
  /function[[:space:]]+(xor|and|or|compl|lshift|rshift|strftime|systime)[[:space:]]*\(/ { print FILENAME ":" FNR ": an awk function is named like a gawk built-in" }
  /while[[:space:]]+![[:space:]]+mkdir/ { print FILENAME ":" FNR ": a lock is taken with mkdir" }
' "${root}"/bin/* "${root}"/lib/*.sh)
if [ -n "${forbidden}" ]; then
  printf 'code FAMILY.md forbids:\n%s\n' "${forbidden}" >&2
  exit 1
fi
