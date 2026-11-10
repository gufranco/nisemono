#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_release() {
  disk_rl_disk="$1"
  disk_rl_os="$(disk_os)"
  case "${disk_rl_os}" in
  Darwin)
    disk_bounded 30 sudo diskutil unmountDisk force "${disk_rl_disk}" >/dev/null 2>&1
    disk_is_mounted "${disk_rl_disk}" || return 0
    disk_rl_list="$(diskutil list "${disk_rl_disk}" 2>/dev/null)"
    disk_rl_slices="$(printf '%s\n' "${disk_rl_list}" | awk '$NF ~ /^disk[0-9]+s[0-9]+$/ { print $NF }')"
    for disk_rl_slice in ${disk_rl_slices}; do
      disk_bounded 20 sudo diskutil unmount force "/dev/${disk_rl_slice}" >/dev/null 2>&1
    done
    disk_is_mounted "${disk_rl_disk}" && return 1
    return 0
    ;;
  Linux)
    DISK_RELEASED=0
    disk_rl_children="$(lsblk -nro NAME "${disk_rl_disk}" 2>/dev/null)"
    for disk_rl_child in ${disk_rl_children}; do
      if sudo umount "/dev/${disk_rl_child}" 2>/dev/null; then
        DISK_RELEASED=$((DISK_RELEASED + 1))
      fi
    done
    if ! disk_rl_mounts="$(lsblk -nro MOUNTPOINT "${disk_rl_disk}" 2>/dev/null)"; then
      return 2
    fi
    disk_rl_mounts="$(printf '%s' "${disk_rl_mounts}" | tr -d '[:space:]')"
    [ -n "${disk_rl_mounts}" ] && return 1
    return 0
    ;;
  *) return 1 ;;
  esac
}

disk_unmount_for_write() {
  disk_info "Unmounting $1..."
  disk_uw_status=0
  disk_release "$1" || disk_uw_status="$?"
  case "${disk_uw_status}" in
  0) return 0 ;;
  2)
    disk_error "unable to read the mount state of $1, so this stops here."
    return 1
    ;;
  *)
    disk_error "disk is still mounted, so writing to it would corrupt the mounted volume."
    return 1
    ;;
  esac
}

disk_eject_now() {
  disk_en_os="$(disk_os)"
  case "${disk_en_os}" in
  Darwin)
    if disk_bounded 30 sudo diskutil eject "$1" >/dev/null 2>&1; then
      disk_success "Ejected. $1 is safe to remove."
      return 0
    fi
    ;;
  Linux)
    if disk_bounded 30 sudo eject "$1" >/dev/null 2>&1; then
      disk_success "Ejected. $1 is safe to remove."
      return 0
    fi
    ;;
  *) ;;
  esac
  disk_warning "$1 did not eject. remove it once its light stops blinking."
  return 1
}

disk_probe_cache_bypass() {
  DISK_READ_FLAGS=""
  DISK_WRITE_FLAGS=""
  DISK_FLUSH=0
  disk_pc_os="$(disk_os)"
  [ "${disk_pc_os}" = "Linux" ] || return 0
  if disk_direct_round_trip "$1" "$2"; then
    DISK_READ_FLAGS="iflag=direct"
    DISK_WRITE_FLAGS="oflag=direct"
    disk_info "Bypassing the page cache so every block reaches the media."
  else
    DISK_FLUSH=1
    disk_info "Direct I/O is unavailable, so buffers are dropped before reading back."
  fi
  return 0
}

disk_direct_round_trip() {
  disk_dr_file="${TMPDIR:-/tmp}/nisemono-direct.$$"
  disk_dr_status=1
  if sudo dd if="$1" of="${disk_dr_file}" bs="$2" count=1 iflag=direct status=none 2>/dev/null &&
    sudo dd if="${disk_dr_file}" of="$1" bs="$2" count=1 oflag=direct conv=notrunc status=none 2>/dev/null; then
    disk_dr_status=0
  fi
  sudo rm -f "${disk_dr_file}"
  return "${disk_dr_status}"
}

disk_flush_reads() {
  [ "${DISK_FLUSH:-0}" = "1" ] || return 0
  sync
  sudo blockdev --flushbufs "$1" 2>/dev/null
  return 0
}

disk_dd_bytes() {
  awk -v block="$2" '
    /bytes/ { print $1; found = 1; exit }
    /records out/ { split($1, records, "+"); whole = records[1] * block }
    END { if (!found && whole != "") print whole }
  ' "$1"
}

disk_dd_error() {
  disk_de_text="$(grep -v -E 'records (in|out)|bytes' "$1" 2>/dev/null)"
  printf '%s\n' "${disk_de_text}" | awk 'NF { line[++n] = $0 } END { s = ""; for (i = (n > 2 ? n - 1 : 1); i <= n; i++) s = s (s == "" ? "" : " ") line[i]; print s }'
}

disk_move() {
  disk_mv_direction="$1"
  disk_mv_source="$2"
  disk_mv_target="$3"
  disk_mv_block="$4"
  disk_mv_at="$5"
  disk_mv_err="${DISK_TMPDIR}/dd.err"
  DISK_MOVED=0
  DISK_TIMED_OUT=0
  DISK_INTERRUPTED=0
  disk_set_error ""

  disk_mv_outcome=0
  if [ "${disk_mv_direction}" = "write" ]; then
    disk_bounded_ms "${DISK_DEADLINE}" sudo dd if="${disk_mv_source}" of="${disk_mv_target}" bs="${disk_mv_block}" \
      seek="${disk_mv_at}" count=1 conv=notrunc ${DISK_WRITE_FLAGS:+"${DISK_WRITE_FLAGS}"} 2>"${disk_mv_err}" || disk_mv_outcome="$?"
  else
    disk_bounded_ms "${DISK_DEADLINE}" sudo dd if="${disk_mv_source}" of="${disk_mv_target}" bs="${disk_mv_block}" \
      skip="${disk_mv_at}" count=1 ${DISK_READ_FLAGS:+"${DISK_READ_FLAGS}"} 2>"${disk_mv_err}" || disk_mv_outcome="$?"
  fi

  case "${disk_mv_outcome}" in
  0) ;;
  124 | 137)
    DISK_TIMED_OUT=1
    disk_mv_shown="$(disk_duration "${DISK_DEADLINE}")"
    disk_set_error "the drive did not finish a ${disk_mv_direction} of block ${disk_mv_at} within ${disk_mv_shown}"
    return 1
    ;;
  130 | 143)
    DISK_INTERRUPTED=1
    disk_set_error "the ${disk_mv_direction} of block ${disk_mv_at} was interrupted"
    return 1
    ;;
  *)
    disk_mv_said="$(disk_dd_error "${disk_mv_err}")"
    disk_set_error "${disk_mv_said}"
    return 1
    ;;
  esac

  DISK_MOVED="$(disk_dd_bytes "${disk_mv_err}" "${disk_mv_block}")"
  disk_is_uint "${DISK_MOVED}" || DISK_MOVED=0
  if [ "${DISK_MOVED}" -ne "${disk_mv_block}" ]; then
    disk_set_error "dd moved ${DISK_MOVED} of ${disk_mv_block} bytes at block ${disk_mv_at}"
    return 1
  fi
  return 0
}

disk_fault() {
  disk_ft_detail="$(disk_get_error)"
  disk_error "stopped: $2"
  [ -n "${disk_ft_detail}" ] && disk_error "dd said: ${disk_ft_detail}"
  if disk_device_gone "$1"; then
    disk_error "$1 is no longer attached. a card that drops off mid-test often fails the same way in a camera."
    return 1
  fi
  disk_bounded 20 sync >/dev/null 2>&1
  disk_eject_now "$1"
  return 1
}
