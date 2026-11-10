#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_probe_blocks() {
  awk -v size="$1" -v sector="$2" -v samples="$3" 'BEGIN {
    blocks = int(size / sector)
    step = 1
    while (step * 2 <= blocks / samples) step *= 2
    for (b = 0; b < blocks; b += step) print b
    print blocks - 1
  }' | sort -n -u
}

disk_probe_nonce() {
  disk_pn_value="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  [ "${#disk_pn_value}" -eq 16 ] || return 1
  printf '%s\n' "${disk_pn_value}"
}

disk_probe_tag() {
  disk_pt_head="$(printf 'NISEMONO %s %s' "${DISK_NONCE}" "$1")"
  printf '%s\n' "${disk_pt_head}" >"$2"
  head -c $((DISK_SECTOR - ${#disk_pt_head} - 1)) /dev/zero >>"$2"
}

disk_probe_claim() {
  head -c 64 "$1" | tr -d '\000' | awk -v nonce="${DISK_NONCE}" '
    NR == 1 && $1 == "NISEMONO" && $2 == nonce && $3 ~ /^[0-9]+$/ { print $3; found = 1 }
    END { if (!found) print -1 }'
}

disk_probe_read_one() {
  disk_pr_back="${DISK_TMPDIR}/back"
  disk_move read "$1" "${disk_pr_back}" "${DISK_SECTOR}" "$2" || return 1
  disk_pr_claim="$(disk_probe_claim "${disk_pr_back}")"
  if [ "${disk_pr_claim}" -ge 0 ]; then
    disk_probe_tag "${disk_pr_claim}" "${DISK_TMPDIR}/expected"
    cmp -s "${disk_pr_back}" "${DISK_TMPDIR}/expected" || disk_pr_claim=-1
  fi
  printf '%s %s\n' "$2" "${disk_pr_claim}"
}

disk_probe_phase() {
  disk_ph_total="$(wc -l <"$3" | tr -d '[:space:]')"
  disk_ph_done=0
  disk_ph_started="$(disk_now_ms)"
  DISK_PROGRESS_STEP=0
  while IFS= read -r disk_ph_block; do
    if [ "$1" = write ]; then
      disk_probe_tag "${disk_ph_block}" "${DISK_TMPDIR}/tag"
      disk_move write "${DISK_TMPDIR}/tag" "$2" "${DISK_SECTOR}" "${disk_ph_block}" || return 1
    else
      disk_probe_read_one "$2" "${disk_ph_block}" >>"$4" || return 1
    fi
    disk_ph_done=$((disk_ph_done + 1))
    disk_progress "$5" $((disk_ph_done * DISK_SECTOR)) $((disk_ph_total * DISK_SECTOR)) "${disk_ph_started}"
  done <"$3"
  return 0
}

disk_probe_judge() {
  awk -v sector="$2" -v size="$3" '
    { block[NR] = $1; claim[$1] = $2 }
    END {
      for (i = 1; i <= NR; i++) {
        b = block[i]; c = claim[b]
        if (c < 0) { bad[b] = 1; lost++; continue }
        if (!(c in low) || b < low[c]) low[c] = b
        if (c < low[c]) low[c] = c
      }
      for (i = 1; i <= NR; i++) {
        b = block[i]; c = claim[b]
        if (c < 0) continue
        if (b != low[c]) bad[b] = 1
        if (c != low[c] && (c in claim)) bad[c] = 1
      }
      first = -1
      for (i = 1; i <= NR; i++) { b = block[i]; if ((b in bad) && (first < 0 || b < first)) first = b }
      wrapped = 0; ok = 0; good = -1; gap = 0; base = 0
      for (i = 1; i <= NR; i++) {
        b = block[i]
        if (b in bad) {
          if (claim[b] < 0) continue
          wrapped++
          d = b - low[claim[b]]
          if (d > 0 && (gap == 0 || d < gap)) { gap = d; base = low[claim[b]] }
          continue
        }
        ok++
        if (first < 0 || b < first) { if (b > good) good = b }
      }
      real = (first < 0) ? size : first * sector
      verified = (first < 0) ? size : (good + 1) * sector
      printf "%d %d %d %d %d %d %d %d %d\n", ok, wrapped, lost + 0, real, verified, first, good, gap, base
    }' "$1"
}

disk_probe_verdict() {
  disk_pv_line="$(disk_probe_judge "$1" "${DISK_SECTOR}" "${DISK_SIZE}")"
  read -r DISK_OK DISK_WRAPPED DISK_LOST DISK_REAL DISK_VERIFIED DISK_FIRST_BAD DISK_LAST_GOOD DISK_GAP DISK_BASE <<EOF
${disk_pv_line}
EOF
  DISK_VERDICT=pass
  [ "${DISK_FIRST_BAD}" -ge 0 ] && DISK_VERDICT=fake
  return 0
}

disk_probe_measure() {
  disk_pm_io="$(disk_io_device "$1")"
  disk_pm_list="${DISK_TMPDIR}/blocks"
  disk_pm_reads="${DISK_TMPDIR}/reads"
  disk_probe_blocks "${DISK_SIZE}" "${DISK_SECTOR}" "${DISK_SAMPLES}" >"${disk_pm_list}"
  : >"${disk_pm_reads}"
  DISK_DEADLINE="${DISK_BLOCK_DEADLINE}"
  if ! disk_probe_phase write "${disk_pm_io}" "${disk_pm_list}" "" Writing; then
    disk_fault "$1" "a test block could not be written to $1."
    return 1
  fi
  sync
  disk_flush_reads "${disk_pm_io}"
  if ! disk_probe_phase read "${disk_pm_io}" "${disk_pm_list}" "${disk_pm_reads}" Reading; then
    disk_fault "$1" "a test block could not be read back from $1."
    return 1
  fi
  disk_probe_verdict "${disk_pm_reads}"
  [ "${DISK_VERDICT}" = fake ] || return 0
  if ! disk_refine "${disk_pm_io}"; then
    disk_fault "$1" "a block could not be tested while narrowing down the real size of $1."
    return 1
  fi
  return 0
}
