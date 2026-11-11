#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_fill_free() {
  df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print $4 }'
}

disk_fill_ready() {
  if [ ! -d "$1" ]; then
    disk_error "not a mounted volume: $1"
    return 1
  fi
  disk_fy_free="$(disk_fill_free "$1")"
  disk_is_uint "${disk_fy_free}" || disk_fy_free=0
  DISK_FILL_BLOCKS=$((disk_fy_free / 1024 - DISK_FILL_MARGIN))
  [ "${DISK_FILL_BLOCKS}" -gt 0 ] && return 0
  disk_error "stopped: $1 has no free space to check."
  return 1
}

disk_fill_name() {
  printf '%s/check-%04d.bin\n' "${DISK_FILL_DIR}" $(($1 / DISK_FILL_PER))
}

disk_fill_block() {
  printf '%-63s\n' "nisemono ${DISK_NONCE} $1"
  cat "${DISK_TMPDIR}/filler"
}

disk_fill_write() {
  disk_fw_index=0
  while [ "${disk_fw_index}" -lt "${DISK_FILL_BLOCKS}" ]; do
    disk_fw_file="$(disk_fill_name "${disk_fw_index}")"
    disk_fill_block "${disk_fw_index}" >>"${disk_fw_file}" 2>/dev/null || break
    disk_fw_index=$((disk_fw_index + 1))
  done
  DISK_FILL_WRITTEN="${disk_fw_index}"
  sync
  [ "${DISK_FILL_WRITTEN}" -eq "${DISK_FILL_BLOCKS}" ] && return 0
  disk_warning "the volume took ${DISK_FILL_WRITTEN} of ${DISK_FILL_BLOCKS} MiB before it refused more."
}

disk_fill_check() {
  disk_fill_block "$1" >"${DISK_TMPDIR}/want"
  disk_fk_file="$(disk_fill_name "$1")"
  dd if="${disk_fk_file}" bs=1048576 skip=$(($1 % DISK_FILL_PER)) count=1 ${DISK_READ_FLAGS:+"${DISK_READ_FLAGS}"} 2>/dev/null |
    cmp -s - "${DISK_TMPDIR}/want"
}

disk_fill_verify() {
  DISK_FILL_BAD=0
  DISK_FILL_FIRST=""
  disk_fv_index=0
  while [ "${disk_fv_index}" -lt "${DISK_FILL_WRITTEN}" ]; do
    if ! disk_fill_check "${disk_fv_index}"; then
      DISK_FILL_BAD=$((DISK_FILL_BAD + 1))
      [ -n "${DISK_FILL_FIRST}" ] || DISK_FILL_FIRST="${disk_fv_index}"
    fi
    disk_fv_index=$((disk_fv_index + 1))
  done
}

disk_fill_uncache() {
  DISK_READ_FLAGS=""
  disk_fu_os="$(disk_os)"
  [ "${disk_fu_os}" != Darwin ] || {
    disk_fill_remount
    return
  }
  disk_fu_first="$(disk_fill_name 0)"
  if dd if="${disk_fu_first}" of=/dev/null bs=1048576 count=1 iflag=direct 2>/dev/null; then
    DISK_READ_FLAGS="iflag=direct"
    return 0
  fi
  disk_require_sudo || return 1
  printf '3\n' | sudo tee /proc/sys/vm/drop_caches >/dev/null
}

disk_fill_remount() {
  disk_fm_device="$(disk_info_field "${DISK_FILL_VOLUME}" 'Device Node')"
  if [ -n "${disk_fm_device}" ] && diskutil unmount "${DISK_FILL_VOLUME}" >/dev/null 2>&1 && diskutil mount -mountPoint "${DISK_FILL_VOLUME}" "${disk_fm_device}" >/dev/null 2>&1; then
    return 0
  fi
  disk_error "unable to remount ${DISK_FILL_VOLUME} to read past the cache, so nothing was proven. remove its .nisemono-${DISK_NONCE} folder once it mounts again."
  return 1
}

disk_fill_clean() {
  [ -z "${DISK_FILL_DIR}" ] || rm -rf "${DISK_FILL_DIR}"
  DISK_FILL_DIR=""
  disk_drop_tmpdir
}

disk_fill_stop() {
  disk_fill_clean
  disk_error "interrupted, and the check files are removed."
  exit 1
}

disk_fill_start() {
  disk_make_tmpdir nisemono || return 1
  if ! DISK_NONCE="$(disk_probe_nonce)" || ! head -c $((1048576 - 64)) /dev/urandom >"${DISK_TMPDIR}/filler"; then
    disk_error "unable to read random bytes for the check files."
    return 1
  fi
  DISK_FILL_DIR="${DISK_FILL_VOLUME}/.nisemono-${DISK_NONCE}"
  mkdir "${DISK_FILL_DIR}" 2>/dev/null && return 0
  DISK_FILL_DIR=""
  disk_error "unable to write to ${DISK_FILL_VOLUME}."
  return 1
}

disk_fill_run() {
  DISK_FILL_VOLUME="${1%/}"
  disk_fill_ready "${DISK_FILL_VOLUME}" || return 1
  trap disk_fill_stop INT TERM HUP
  disk_fill_start || return 1
  [ "${NISEMONO_JSON:-n}" = y ] || disk_info "Writing ${DISK_FILL_BLOCKS} MiB of check files to ${DISK_FILL_VOLUME}, then reading them back."
  disk_fill_write
  disk_fr_status=0
  if [ "${DISK_FILL_WRITTEN}" -eq 0 ]; then
    disk_error "unable to write a single check file to ${DISK_FILL_VOLUME}."
    disk_fr_status=1
  fi
  [ "${disk_fr_status}" -ne 0 ] || disk_fill_uncache || disk_fr_status=1
  [ "${disk_fr_status}" -ne 0 ] || disk_fill_verify
  disk_fill_clean
  trap - INT TERM HUP
  return "${disk_fr_status}"
}

disk_fill_report() {
  disk_fl_status=0
  disk_fill_run "$1" || disk_fl_status=1
  [ "${disk_fl_status}" -eq 0 ] || return 1
  if [ "${NISEMONO_JSON:-n}" = y ]; then
    disk_fill_json
  else
    disk_fill_result
  fi
  [ "${DISK_FILL_BAD}" -eq 0 ]
}

disk_fill_json() {
  disk_fj_volume="$(disk_json_string "${DISK_FILL_VOLUME}")"
  disk_fj_verdict=pass
  disk_fj_file=null
  disk_fj_offset=null
  if [ "${DISK_FILL_BAD}" -gt 0 ]; then
    disk_fj_verdict=fake
    disk_fj_file="$(printf 'check-%04d.bin' $((DISK_FILL_FIRST / DISK_FILL_PER)))"
    disk_fj_file="$(disk_json_string "${disk_fj_file}")"
    disk_fj_offset=$((DISK_FILL_FIRST % DISK_FILL_PER * 1048576))
  fi
  printf '{"volume":%s,"checked_bytes":%s,"bad_bytes":%s,"verdict":"%s","first_bad_file":%s,"first_bad_offset":%s}\n' \
    "${disk_fj_volume}" $((DISK_FILL_WRITTEN * 1048576)) $((DISK_FILL_BAD * 1048576)) "${disk_fj_verdict}" "${disk_fj_file}" "${disk_fj_offset}"
}

disk_fill_result() {
  if [ "${DISK_FILL_BAD}" -eq 0 ]; then
    disk_success "No fault found. All ${DISK_FILL_WRITTEN} MiB of check files on ${DISK_FILL_VOLUME} read back as written."
    return 0
  fi
  disk_fs_file="$(printf 'check-%04d.bin' $((DISK_FILL_FIRST / DISK_FILL_PER)))"
  disk_fs_offset=$((DISK_FILL_FIRST % DISK_FILL_PER * 1048576))
  disk_info "Result: ${DISK_FILL_BAD} of ${DISK_FILL_WRITTEN} MiB of check files came back wrong"
  disk_probe_fake_line "Fake. ${DISK_FILL_VOLUME} handed back wrong data, first in ${disk_fs_file} at byte ${disk_fs_offset}."
}
