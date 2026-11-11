#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_probe_report() {
  disk_rp_status=0
  disk_probe_run "$1" || disk_rp_status=1
  if [ "${NISEMONO_JSON:-n}" = y ] && [ -n "${DISK_VERDICT}" ]; then
    disk_probe_json
  fi
  return "${disk_rp_status}"
}

disk_probe_json() {
  disk_pj_device="$(disk_json_string "${DISK_TARGET}")"
  printf '{"device":%s,"reported_bytes":%s,"real_bytes":%s,"verified_bytes":%s,"verdict":"%s","ok":%s,"wrapped":%s,"lost":%s}\n' \
    "${disk_pj_device}" "${DISK_SIZE}" "${DISK_REAL}" "${DISK_VERIFIED}" "${DISK_VERDICT}" \
    "${DISK_OK}" "${DISK_WRAPPED}" "${DISK_LOST}"
}

disk_probe_run() {
  disk_check_samples "${NISEMONO_SAMPLES:-${DISK_SAMPLES}}" || return 1
  disk_pr_disk="$(disk_resolve "$1")" || return 1
  disk_refuse_target "${disk_pr_disk}" || return 1
  DISK_TARGET="${disk_pr_disk}"
  disk_probe_prepare "${disk_pr_disk}" || return 1
  disk_make_tmpdir nisemono || return 1
  disk_pr_status=0
  if DISK_NONCE="$(disk_probe_nonce)"; then
    disk_probe_measure "${disk_pr_disk}" || disk_pr_status=1
  else
    disk_error "unable to read random bytes for the probe tag."
    disk_pr_status=1
  fi
  disk_drop_tmpdir
  [ "${disk_pr_status}" -eq 0 ] || return 1
  disk_probe_result "${disk_pr_disk}"
}

disk_probe_prepare() {
  if [ ! -b "$1" ] && [ ! -c "$1" ]; then
    disk_error "device not found or invalid: $1."
    return 1
  fi
  DISK_IDENTITY="$(disk_identity "$1")"
  disk_probe_size "$1" || return 1
  disk_probe_summary "$1"
  disk_confirm_names "$1" "${DISK_CONFIRM_VERB}" || return 1
  disk_pp_writable=0
  disk_writable_media "$1" || disk_pp_writable="$?"
  if [ "${disk_pp_writable}" -eq 1 ]; then
    disk_error "stopped: $1 is write protected, so nothing on it can be probed."
    disk_info "Slide the lock switch on the card or adapter up, then run this again."
    return 1
  fi
  disk_require_sudo || return 1
  disk_unmount_for_write "$1" || return 1
  disk_pp_io="$(disk_io_device "$1")"
  disk_probe_cache_bypass "${disk_pp_io}" "${DISK_SECTOR}"
}

disk_probe_size() {
  DISK_SIZE="$(disk_size_bytes "$1")"
  if ! disk_is_uint "${DISK_SIZE}" || [ "${DISK_SIZE}" -eq 0 ]; then
    disk_error "unable to determine disk size for $1."
    return 1
  fi
  DISK_SECTOR="$(disk_sector_bytes "$1")"
  return 0
}

disk_probe_summary() {
  [ "${NISEMONO_JSON:-n}" != y ] || return 0
  if [ "${DISK_SUMMARY_BOXED}" = no ] && disk_ui_out; then
    DISK_SUMMARY_BOXED=yes
    disk_ps_text="$(disk_probe_summary "$1")"
    DISK_SUMMARY_BOXED=no
    disk_summary_box "${disk_ps_text}"
    return 0
  fi
  disk_ps_human="$(disk_human "${DISK_SIZE}")"
  disk_ps_count="$(disk_probe_blocks "${DISK_SIZE}" "${DISK_SECTOR}" "${DISK_SAMPLES}" | wc -l | tr -d '[:space:]')"
  printf '\n'
  disk_info "Device: $1, ${disk_ps_human}, ${DISK_IDENTITY:-unnamed device}"
  disk_info "Probe:  ${disk_ps_count} blocks of ${DISK_SECTOR} bytes, all written, then all read back"
  disk_info "        a fake card loses data here, so copy anything you need first"
  printf '\n'
}

disk_probe_result() {
  [ "${NISEMONO_JSON:-n}" != y ] || {
    [ "${DISK_VERDICT}" = pass ]
    return
  }
  disk_pr_reported="$(disk_human "${DISK_SIZE}")"
  if [ "${DISK_VERDICT}" = pass ]; then
    disk_info "Result: ${DISK_OK} of ${DISK_OK} blocks read back as written"
    disk_success "No fault found. Every test block across the ${disk_pr_reported} of $1 came back as written."
    return 0
  fi
  disk_pr_real="$(disk_human "${DISK_REAL}")"
  disk_info "Result: ${disk_pr_real} (${DISK_REAL} bytes) of the ${disk_pr_reported} it reports"
  disk_info "        ${DISK_WRAPPED} blocks came back from a lower address, ${DISK_LOST} were lost"
  disk_probe_fake_line "Fake. $1 holds ${disk_pr_real}, not ${disk_pr_reported}."
  return 1
}

disk_probe_fake_line() {
  if disk_ui_out; then
    printf '\n'
    disk_ui_ink "${DISK_UI_ERR}" --bold -- "$1"
    return 0
  fi
  disk_say "$1"
}
