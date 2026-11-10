#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_refine_put() {
  disk_probe_tag "$2" "${DISK_TMPDIR}/tag"
  disk_move write "${DISK_TMPDIR}/tag" "$1" "${DISK_SECTOR}" "$2"
}

disk_refine_get() {
  disk_rg_line="$(disk_probe_read_one "$1" "$2")" || return 1
  printf '%s\n' "${disk_rg_line#* }"
}

disk_refine_divisors() {
  awk -v gap="$1" -v min="$2" 'BEGIN {
    for (d = 1; d * d <= gap; d++) {
      if (gap % d) continue
      if (d >= min) print d
      if (gap / d >= min) print gap / d
    }
  }' | sort -n -u
}

disk_refine_aliases() {
  awk -v b="$1" -v lo="$2" -v m="$3" 'BEGIN {
    while (m <= b) { a = b % m; if (a < lo) print a; m *= 2 }
  }' | sort -n -u
}

disk_refine_module() {
  disk_rm_blocks=$((DISK_SIZE / DISK_SECTOR))
  disk_rm_list="$(disk_refine_divisors "${DISK_GAP}" $((DISK_MIN_MODULE / DISK_SECTOR)))"
  for disk_rm_m in ${disk_rm_list}; do
    disk_rm_far=$((DISK_BASE + disk_rm_m))
    [ "${disk_rm_far}" -lt "${disk_rm_blocks}" ] || continue
    disk_refine_put "$1" "${DISK_BASE}" || return 1
    disk_refine_put "$1" "${disk_rm_far}" || return 1
    disk_rm_claim="$(disk_refine_get "$1" "${DISK_BASE}")" || return 1
    if [ "${disk_rm_claim}" = "${disk_rm_far}" ]; then
      printf '%s\n' "${disk_rm_m}"
      return 0
    fi
  done
  printf '0\n'
}

disk_refine_good() {
  disk_rgd_list="$(disk_refine_aliases "$2" "$3" $((DISK_MIN_MODULE / DISK_SECTOR)))"
  for disk_rgd_alias in ${disk_rgd_list}; do
    disk_refine_put "$1" "${disk_rgd_alias}" || return 2
  done
  disk_refine_put "$1" "$2" || return 2
  for disk_rgd_alias in ${disk_rgd_list}; do
    disk_rgd_claim="$(disk_refine_get "$1" "${disk_rgd_alias}")" || return 2
    [ "${disk_rgd_claim}" = "$2" ] && return 1
  done
  disk_rgd_claim="$(disk_refine_get "$1" "$2")" || return 2
  [ "${disk_rgd_claim}" = "$2" ] || return 1
  return 0
}

disk_refine_floor() {
  disk_probe_blocks "${DISK_SIZE}" "${DISK_SECTOR}" "${DISK_SAMPLES}" |
    awk -v hi="$1" '$1 < hi { low = $1 } END { print low + 0 }'
}

disk_refine_bounds() {
  DISK_REFINE_HI="${DISK_FIRST_BAD}"
  DISK_REFINE_LO="${DISK_LAST_GOOD}"
  [ "${DISK_GAP}" -gt 0 ] || return 0
  disk_rb_module="$(disk_refine_module "$1")" || return 1
  if [ "${disk_rb_module}" -gt 0 ] && [ "${disk_rb_module}" -lt "${DISK_REFINE_HI}" ]; then
    DISK_REFINE_HI="${disk_rb_module}"
    DISK_REFINE_LO="$(disk_refine_floor "${disk_rb_module}")"
  fi
  return 0
}

disk_refine() {
  disk_refine_bounds "$1" || return 1
  disk_rf_total="$(awk -v span=$((DISK_REFINE_HI - DISK_REFINE_LO)) 'BEGIN { n = 0; while (span > 1) { span = int((span + 1) / 2); n++ } print n }')"
  disk_rf_done=0
  disk_rf_started="$(disk_now_ms)"
  DISK_PROGRESS_STEP=0
  while [ $((DISK_REFINE_HI - DISK_REFINE_LO)) -gt 1 ]; do
    disk_rf_mid=$(((DISK_REFINE_LO + DISK_REFINE_HI) / 2))
    disk_rf_state=0
    disk_refine_good "$1" "${disk_rf_mid}" "${DISK_REFINE_LO}" || disk_rf_state="$?"
    case "${disk_rf_state}" in
    0) DISK_REFINE_LO="${disk_rf_mid}" ;;
    1) DISK_REFINE_HI="${disk_rf_mid}" ;;
    *) return 1 ;;
    esac
    disk_rf_done=$((disk_rf_done + 1))
    disk_progress Narrowing $((disk_rf_done * DISK_SECTOR)) $((disk_rf_total * DISK_SECTOR)) "${disk_rf_started}"
  done
  DISK_REAL=$((DISK_REFINE_HI * DISK_SECTOR))
  DISK_VERIFIED="${DISK_REAL}"
  return 0
}
