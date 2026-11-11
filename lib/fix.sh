#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_le_bytes() {
  printf '\\0%03o\\0%03o\\0%03o\\0%03o' \
    $(($1 % 256)) $(($1 / 256 % 256)) $(($1 / 65536 % 256)) $(($1 / 16777216 % 256))
}

disk_le_uint() {
  disk_lu_bytes="$(od -An -tu1 -v -j "$2" -N "$3" "$1" 2>/dev/null)"
  printf '%s\n' "${disk_lu_bytes}" | awk '
    { for (i = 1; i <= NF; i++) b[++n] = $i }
    END {
      v = 0
      for (i = n; i >= 1; i--) v = v * 256 + b[i]
      printf "%.0f\n", v
    }
  '
}

disk_mbr_write() {
  disk_mw_start="$(disk_le_bytes "$3")"
  disk_mw_count="$(disk_le_bytes "$4")"
  disk_mw_type="$(printf '\\0%03o' "$2")"
  printf '%b' "\0000\0376\0377\0377${disk_mw_type}\0376\0377\0377${disk_mw_start}${disk_mw_count}" |
    dd of="$1" bs=1 seek=446 conv=notrunc 2>/dev/null || return 1
  printf '%b' '\0125\0252' | dd of="$1" bs=1 seek=510 conv=notrunc 2>/dev/null
}

disk_fat_build() {
  disk_fb_sectors=$(($3 / 512))
  case "$2" in
  fat32) mformat -i "$1@@1M" -F -T "${disk_fb_sectors}" -v "$4" :: >/dev/null 2>&1 ;;
  *) mformat -i "$1@@1M" -T "${disk_fb_sectors}" -v "$4" :: >/dev/null 2>&1 ;;
  esac
}

disk_metadata_end() {
  disk_me_bps="$(disk_le_uint "$1" $(($2 + 11)) 2)"
  [ "${disk_me_bps}" -gt 0 ] || disk_me_bps=512
  disk_me_reserved="$(disk_le_uint "$1" $(($2 + 14)) 2)"
  disk_me_fats="$(disk_le_uint "$1" $(($2 + 16)) 1)"
  disk_me_roots="$(disk_le_uint "$1" $(($2 + 17)) 2)"
  disk_me_fat16="$(disk_le_uint "$1" $(($2 + 22)) 2)"
  disk_me_fat32="$(disk_le_uint "$1" $(($2 + 36)) 4)"
  disk_me_spc="$(disk_le_uint "$1" $(($2 + 13)) 1)"
  disk_me_fatlen="${disk_me_fat16}"
  [ "${disk_me_fatlen}" -gt 0 ] || disk_me_fatlen="${disk_me_fat32}"
  printf '%s\n' "$(($2 + (disk_me_reserved + disk_me_fats * disk_me_fatlen) * disk_me_bps + disk_me_roots * 32 + 64 * disk_me_spc * disk_me_bps))"
}

disk_fix_fs() {
  if [ "$1" -le 2147483648 ]; then
    printf 'fat\n'
  else
    printf 'fat32\n'
  fi
}

disk_fix_type() {
  case "$1" in
  fat32) printf '12\n' ;;
  *) printf '14\n' ;;
  esac
}

disk_fix_image() {
  disk_fi_image="${DISK_TMPDIR}/fix.img"
  rm -f "${disk_fi_image}"
  dd if=/dev/zero of="${disk_fi_image}" bs=1 count=0 seek="${DISK_FIX_SIZE}" 2>/dev/null || return 1
  disk_fi_type="$(disk_fix_type "${DISK_FIX_FS}")"
  disk_mbr_write "${disk_fi_image}" "${disk_fi_type}" 2048 $((DISK_FIX_SIZE / 512 - 2048)) || return 1
  disk_fat_build "${disk_fi_image}" "${DISK_FIX_FS}" $((DISK_FIX_SIZE - 1048576)) NISEMONO || return 1
  disk_fi_end="$(disk_metadata_end "${disk_fi_image}" 1048576)"
  DISK_FIX_BLOCKS=$(((disk_fi_end + 1048575) / 1048576))
}

disk_fix_write() {
  disk_fx_io="$(disk_io_device "$1")"
  if ! sudo dd if="${DISK_TMPDIR}/fix.img" of="${disk_fx_io}" bs=1048576 count="${DISK_FIX_BLOCKS}" conv=notrunc 2>"${DISK_TMPDIR}/fix.err"; then
    disk_fz_reason="$(disk_dd_error "${DISK_TMPDIR}/fix.err")"
    disk_error "the new partition could not be written to $1: ${disk_fz_reason:-dd failed.}"
    return 1
  fi
  sync
}

disk_fix_tools() {
  disk_cmd_exists mformat && return 0
  disk_error "fix needs mformat from mtools. install mtools and try again."
  return 1
}

disk_fix_apply() {
  DISK_FIX_SIZE=$((DISK_REAL / 1048576 * 1048576))
  if [ "${DISK_FIX_SIZE}" -lt 4194304 ]; then
    disk_fa_real="$(disk_human "${DISK_REAL}")"
    disk_error "stopped: $1 really holds only ${disk_fa_real}, too little for a partition."
    return 1
  fi
  DISK_FIX_FS="$(disk_fix_fs "${DISK_FIX_SIZE}")"
  disk_make_tmpdir nisemono || return 1
  disk_fa_status=0
  disk_fix_image || disk_fa_status=1
  if [ "${disk_fa_status}" -ne 0 ]; then
    disk_error "unable to build the new partition for $1."
  else
    disk_fix_write "$1" || disk_fa_status=1
  fi
  disk_drop_tmpdir
  return "${disk_fa_status}"
}

disk_fix_report() {
  disk_fix_tools || return 1
  DISK_CONFIRM_VERB="probe and repartition"
  disk_probe_run "$1" >&2 || :
  case "${DISK_VERDICT}" in
  pass)
    disk_error "stopped: ${DISK_TARGET} is genuine, so there is nothing to fix."
    return 1
    ;;
  fake) disk_fix_apply "${DISK_TARGET}" || return 1 ;;
  *) return 1 ;;
  esac
  disk_fix_done
}

disk_fix_done() {
  disk_fd_size="$(disk_human "${DISK_FIX_SIZE}")"
  disk_fd_name=FAT16
  [ "${DISK_FIX_FS}" = fat ] || disk_fd_name=FAT32
  if [ "${NISEMONO_JSON:-n}" = y ]; then
    disk_fd_device="$(disk_json_string "${DISK_TARGET}")"
    printf '{"device":%s,"real_bytes":%s,"partition_bytes":%s,"filesystem":"%s"}\n' "${disk_fd_device}" "${DISK_REAL}" $((DISK_FIX_SIZE - 1048576)) "${disk_fd_name}"
    return 0
  fi
  disk_success "Fixed. ${DISK_TARGET} now holds one ${disk_fd_name} partition named NISEMONO within the ${disk_fd_size} it really holds. Eject it and plug it back in to use it."
}
