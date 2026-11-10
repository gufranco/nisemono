#!/bin/sh
[ -n "${ZSH_VERSION:-}" ] && emulate sh

DISK_LIB="$(cd "$(dirname "$0")/../lib" && pwd)" || exit 1

# shellcheck source=SCRIPTDIR/../lib/core.sh
. "${DISK_LIB}/core.sh"
# shellcheck source=SCRIPTDIR/../lib/ui.sh
. "${DISK_LIB}/ui.sh"
# shellcheck source=SCRIPTDIR/../lib/io.sh
. "${DISK_LIB}/io.sh"
# shellcheck source=SCRIPTDIR/../lib/disk.sh
. "${DISK_LIB}/disk.sh"
# shellcheck source=SCRIPTDIR/../lib/cli.sh
. "${DISK_LIB}/cli.sh"
# shellcheck source=SCRIPTDIR/../lib/probe.sh
. "${DISK_LIB}/probe.sh"
# shellcheck source=SCRIPTDIR/../lib/refine.sh
. "${DISK_LIB}/refine.sh"
# shellcheck source=SCRIPTDIR/../lib/report.sh
. "${DISK_LIB}/report.sh"

call_first_boot_disk() {
  disk_cb_list="$(disk_boot_disks)"
  printf '%s\n' "${disk_cb_list}" | sed -n '1p'
}

call_judge() {
  printf '%s' "$1" >"${TMPDIR:-/tmp}/nisemono-judge.$$"
  disk_probe_judge "${TMPDIR:-/tmp}/nisemono-judge.$$" "$2" "$3"
  rm -f "${TMPDIR:-/tmp}/nisemono-judge.$$"
}

"$@"
