#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_whole_of() {
  disk_wo_os="$(disk_os)"
  case "${disk_wo_os}" in
  Darwin)
    disk_wo_whole="$(disk_plist_value "$1" ParentWholeDisk)"
    [ -n "${disk_wo_whole}" ] || return 0
    printf '/dev/%s\n' "${disk_wo_whole}"
    disk_wo_store="$(disk_plist_value "${disk_wo_whole}" APFSPhysicalStores.0.APFSPhysicalStore)"
    if [ -n "${disk_wo_store}" ]; then
      disk_wo_parent="$(disk_plist_value "${disk_wo_store}" ParentWholeDisk)"
      [ -n "${disk_wo_parent}" ] && printf '/dev/%s\n' "${disk_wo_parent}"
    fi
    ;;
  Linux)
    disk_wo_tree="$(lsblk -nrso NAME,TYPE "$1" 2>/dev/null)"
    printf '%s\n' "${disk_wo_tree}" | awk '$2 == "disk" || $2 == "loop" { print "/dev/" $1 }'
    ;;
  *) ;;
  esac
  return 0
}

disk_boot_disks() {
  disk_bd_os="$(disk_os)"
  if [ "${disk_bd_os}" = "Darwin" ]; then
    disk_whole_of /
    disk_whole_of /System/Volumes/Data
  else
    disk_bd_root="$(findmnt -n -o SOURCE / 2>/dev/null)"
    [ -n "${disk_bd_root}" ] && disk_whole_of "${disk_bd_root}"
  fi
  return 0
}

disk_listed() {
  printf '%s\n' "$2" | grep -qx -- "$1"
}

disk_is_internal() {
  disk_ii_os="$(disk_os)"
  case "${disk_ii_os}" in
  Darwin)
    disk_ii_internal="$(disk_plist_value "$1" Internal)"
    disk_ii_eject="$(disk_plist_value "$1" Ejectable)"
    [ "${disk_ii_internal}" = "true" ] && [ "${disk_ii_eject}" != "true" ]
    ;;
  Linux)
    disk_ii_flags="$(lsblk -dnro RM,HOTPLUG,TRAN "$1" 2>/dev/null)"
    case "${disk_ii_flags}" in
    1\ * | ?\ 1* | *usb* | *mmc*) return 1 ;;
    *) return 0 ;;
    esac
    ;;
  *) return 0 ;;
  esac
}

disk_human() {
  awk -v b="$1" 'BEGIN {
    split("B KiB MiB GiB TiB", u, " ")
    i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf (i == 1 ? "%d %s\n" : "%.1f %s\n"), b, u[i]
  }'
}

disk_candidates() {
  disk_cn_os="$(disk_os)"
  case "${disk_cn_os}" in
  Darwin)
    disk_cn_list="$(diskutil list 2>/dev/null)"
    printf '%s\n' "${disk_cn_list}" | awk '/^\/dev\/disk[0-9]+ / && !/synthesized/ { print $1 }'
    ;;
  Linux)
    disk_cn_list="$(lsblk -dnro NAME,TYPE,SIZE -b 2>/dev/null)"
    printf '%s\n' "${disk_cn_list}" | awk '($2 == "disk" || $2 == "loop") && $3 > 0 { print "/dev/" $1 }'
    ;;
  *) ;;
  esac
  return 0
}

disk_eligible() {
  disk_el_boot="$(disk_boot_disks)"
  disk_el_all="$(disk_candidates)"
  for disk_el_disk in ${disk_el_all}; do
    disk_listed "${disk_el_disk}" "${disk_el_boot}" && continue
    if [ "${NISEMONO_ALLOW_INTERNAL:-}" != "y" ] && disk_is_internal "${disk_el_disk}"; then
      continue
    fi
    printf '%s\n' "${disk_el_disk}"
  done
  return 0
}

disk_pick_targets() {
  disk_pt_list="$(disk_eligible)"
  if [ -z "${disk_pt_list}" ]; then
    disk_error "no external or removable disk is attached." >&2
    return 1
  fi
  disk_pt_index=0
  disk_pt_lines=""
  for disk_pt_disk in ${disk_pt_list}; do
    disk_pt_index=$((disk_pt_index + 1))
    disk_pt_size="$(disk_size_bytes "${disk_pt_disk}")"
    disk_is_uint "${disk_pt_size}" || disk_pt_size=0
    disk_pt_human="$(disk_human "${disk_pt_size}")"
    disk_pt_id="$(disk_identity "${disk_pt_disk}")"
    disk_pt_lines="${disk_pt_lines}$(printf '%-14s %10s  %s|%s' "${disk_pt_disk}" "${disk_pt_human}" "${disk_pt_id}" "${disk_pt_disk}")
"
    disk_ui_prompts || printf '  %d) %-14s %10s  %s\n' "${disk_pt_index}" "${disk_pt_disk}" "${disk_pt_human}" "${disk_pt_id}" >&2
  done
  if disk_ui_prompts; then
    disk_pick_drawn "${disk_pt_lines}"
    return
  fi
  printf '%s' "${DISK_PICK_PROMPT:-Write to which disk(s)? Numbers or names, separated by commas: }" >&2
  disk_pt_answer=""
  IFS= read -r disk_pt_answer
  disk_pt_answer="$(printf '%s' "${disk_pt_answer}" | tr -s ', ' '\n')"
  for disk_pt_choice in ${disk_pt_answer}; do
    disk_pick_one "${disk_pt_choice}" "${disk_pt_list}" "${disk_pt_index}" || return 1
  done
  return 0
}

disk_pick_drawn() {
  disk_pd_prompt="${DISK_PICK_PROMPT:-Write to which disk(s)?}"
  disk_pd_header="${disk_pd_prompt%%\?*}?"
  printf '%s' "$1" | disk_ui_choose "${disk_pd_header}" --label-delimiter "|"
}

disk_pick_one() {
  if disk_is_uint "$1" && [ "$1" -ge 1 ] && [ "$1" -le "$3" ]; then
    printf '%s\n' "$2" | sed -n "$1p"
    return 0
  fi
  for disk_po_disk in $2; do
    if [ "${disk_po_disk}" = "$1" ] || [ "${disk_po_disk##*/}" = "$1" ]; then
      printf '%s\n' "${disk_po_disk}"
      return 0
    fi
  done
  disk_error "not a listed number or disk: $1."
  return 1
}

disk_refuse_target() {
  disk_rt_boot="$(disk_boot_disks)"
  if disk_listed "$1" "${disk_rt_boot}"; then
    disk_error "stopped: $1 holds the running system, so it is never written."
    return 1
  fi
  if [ "${NISEMONO_ALLOW_INTERNAL:-}" != "y" ] && disk_is_internal "$1"; then
    disk_error "stopped: $1 is an internal disk. use --allow-internal to test it on purpose."
    return 1
  fi
  return 0
}

disk_confirm_names() {
  disk_cn_expected=""
  for disk_cn_target in $1; do
    disk_cn_expected="${disk_cn_expected}${disk_cn_expected:+ }${disk_cn_target##*/}"
  done
  disk_cn_answer=""
  if disk_ui_prompts; then
    disk_ui_danger "Everything on ${disk_cn_expected} is lost." "Check the name before you type it."
    disk_cn_answer="$(disk_ui_input "Type ${disk_cn_expected} to $2, or anything else to stop" "${disk_cn_expected}")" || disk_cn_answer=""
  else
    printf 'Type %s to %s, or anything else to stop: ' "${disk_cn_expected}" "$2" >&2
    IFS= read -r disk_cn_answer
  fi
  disk_cn_given=""
  for disk_cn_word in ${disk_cn_answer}; do
    disk_cn_given="${disk_cn_given}${disk_cn_given:+ }${disk_cn_word##*/}"
  done
  if [ "${disk_cn_given}" != "${disk_cn_expected}" ]; then
    disk_warning "cancelled, nothing was touched."
    return 1
  fi
  return 0
}

disk_progress() {
  disk_pg_done="$2"
  disk_pg_total="$3"
  [ "${disk_pg_total}" -gt 0 ] || return 0
  disk_pg_percent=$((disk_pg_done * 100 / disk_pg_total))
  disk_pg_now="$(disk_now_ms)"
  disk_pg_ms=$((disk_pg_now - $4))
  [ "${disk_pg_ms}" -gt 0 ] || disk_pg_ms=1
  disk_pg_rate=$((disk_pg_done * 1000 / disk_pg_ms))
  disk_pg_eta=0
  [ "${disk_pg_rate}" -gt 0 ] && disk_pg_eta=$(((disk_pg_total - disk_pg_done) / disk_pg_rate))
  disk_pg_speed="$(disk_human "${disk_pg_rate}")"
  disk_pg_minutes=$((disk_pg_eta / 60))
  disk_pg_seconds=$((disk_pg_eta % 60))
  disk_pg_line="$(printf '%s %3d%%  %s/s  %dm%02ds left' "$1" "${disk_pg_percent}" "${disk_pg_speed}" "${disk_pg_minutes}" "${disk_pg_seconds}")"
  if disk_ui_err; then
    disk_progress_bar "$1" "${disk_pg_percent}" "$(printf '%s/s  %dm%02ds left' "${disk_pg_speed}" "${disk_pg_minutes}" "${disk_pg_seconds}")"
    disk_progress_end "${disk_pg_done}" "${disk_pg_total}"
    return 0
  fi
  if [ -t 2 ]; then
    printf '\r%s   ' "${disk_pg_line}" >&2
    disk_progress_end "${disk_pg_done}" "${disk_pg_total}"
    return 0
  fi
  disk_pg_step=$((disk_pg_percent / 10))
  if [ "${disk_pg_step}" -gt "${DISK_PROGRESS_STEP}" ] || [ "${disk_pg_done}" -ge "${disk_pg_total}" ]; then
    DISK_PROGRESS_STEP="${disk_pg_step}"
    disk_info "${disk_pg_line}"
  fi
  return 0
}

disk_progress_bar() {
  disk_pb_full=$(($2 * 24 / 100))
  disk_pb_char="$(printf '\342\224\201')"
  disk_pb_done="$(printf '%*s' "${disk_pb_full}" '' | sed "s/ /${disk_pb_char}/g")"
  disk_pb_rest="$(printf '%*s' $((24 - disk_pb_full)) '' | sed "s/ /${disk_pb_char}/g")"
  disk_pb_done="$(disk_ui_ink "${DISK_UI_ACCENT}" -- "${disk_pb_done}")"
  disk_pb_rest="$(disk_ui_ink "${DISK_UI_SURFACE}" -- "${disk_pb_rest}")"
  disk_pb_tail="$(disk_ui_ink "${DISK_UI_MUTED}" -- "$3")"
  printf '\r%s %s%s %3d%%  %s   ' "$1" "${disk_pb_done}" "${disk_pb_rest}" "$2" "${disk_pb_tail}" >&2
}

disk_summary_box() {
  disk_sb_text="$1"
  set --
  while IFS= read -r disk_sb_line; do
    case "${disk_sb_line}" in
    "") continue ;;
    " "*) set -- "$@" "" "${disk_sb_line#"${disk_sb_line%%[! ]*}"}" ;;
    *)
      disk_sb_value="${disk_sb_line#*:}"
      set -- "$@" "${disk_sb_line%%:*}:" "${disk_sb_value#"${disk_sb_value%%[! ]*}"}"
      ;;
    esac
  done <<EOF
${disk_sb_text}
EOF
  disk_ui_summary "$@"
}

disk_progress_end() {
  if [ "$1" -ge "$2" ]; then
    printf '\n' >&2
    DISK_PROGRESS_OPEN=0
    return 0
  fi
  DISK_PROGRESS_OPEN=1
}

disk_progress_close() {
  [ "${DISK_PROGRESS_OPEN}" = 1 ] || return 0
  printf '\n' >&2
  DISK_PROGRESS_OPEN=0
}
