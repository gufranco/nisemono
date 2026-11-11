#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_cli_hint() {
  disk_error "$1. run '${DISK_PROG} help' for usage."
}

disk_cli_version() {
  disk_cv_platform="$(uname -sr)" || disk_cv_platform="unknown"
  if disk_ui_out; then
    disk_cv_text="$(disk_version "${DISK_PROG}")"
    disk_cv_badge="$(disk_ui_badge "${DISK_UI_ACCENT}" "${disk_cv_text}")"
    disk_cv_chip="$(disk_ui_chip "platform ${disk_cv_platform}")"
    disk_gum join --horizontal "${disk_cv_badge}" " " "${disk_cv_chip}"
    return 0
  fi
  disk_version "${DISK_PROG}"
  printf 'platform: %s\n' "${disk_cv_platform}"
}

disk_doctor_row() {
  if disk_ui_out; then
    case "$2" in
    ok) disk_dw_state="@ok:ok" ;;
    warn) disk_dw_state="@warn:warn" ;;
    *) disk_dw_state="@bad:$2" ;;
    esac
    DISK_DOCTOR_ROWS="${DISK_DOCTOR_ROWS}$1	${disk_dw_state}	$3
"
    return 0
  fi
  printf '%-18s %-8s %s\n' "$1" "$2" "$3"
}

disk_doctor_report() {
  if ! disk_ui_out; then
    return 0
  fi
  printf 'Tool\tState\tDetail\n%s' "${DISK_DOCTOR_ROWS}" | disk_ui_table
  if [ "$1" -ne 0 ]; then
    disk_ui_log ERROR "a required tool is missing. install it and run nisemono doctor again."
    return 0
  fi
  disk_ui_done "Ready. Every tool nisemono needs is here."
}

disk_flavor_version() {
  printf '%s\n' "$1" | awk '{
    for (i = 1; i <= NF; i++) {
      t = $i
      gsub(/[,;()]/, "", t)
      sub(/^v/, "", t)
      if (t ~ /^[0-9]+(\.[0-9]+)+[a-z0-9]*$/ || t ~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$/) { print t; exit }
    }
  }'
}

disk_tool_line() {
  disk_tl_line="$(printf '%s\n' "$1" | awk '/BusyBox|This is not GNU/ { print; exit }')"
  if [ -z "${disk_tl_line}" ]; then
    disk_tl_line="$(printf '%s\n' "$1" | sed -n '1p')"
  fi
  printf '%s\n' "${disk_tl_line}"
}

disk_tool_flavor() {
  disk_tf_raw="$("$1" --version 2>&1 </dev/null)" || true
  disk_tf_text="$(disk_tool_line "${disk_tf_raw}")"
  disk_tf_version="$(disk_flavor_version "${disk_tf_text}")"
  disk_tf_os="$(disk_os)"
  case "${disk_tf_text}" in
  *uutils*) disk_tf_name=uutils ;;
  *BusyBox*) disk_tf_name=busybox ;;
  *"This is not GNU"*)
    disk_tf_name=busybox
    disk_tf_version=""
    ;;
  *GNU* | *GLIBC* | *"(coreutils)"* | *"(diffutils)"*) disk_tf_name=gnu ;;
  *mawk*) disk_tf_name=mawk ;;
  *"awk version"* | *"(Darwin)"*) disk_tf_name=bsd ;;
  *)
    disk_tf_version=""
    case "$1:${disk_tf_os}" in
    *uutils*:* | */cargo/*:*) disk_tf_name=uutils ;;
    *:Darwin | *:*BSD) disk_tf_name=bsd ;;
    *) disk_tf_name=unknown ;;
    esac
    ;;
  esac
  printf '%s%s\n' "${disk_tf_name}" "${disk_tf_version:+ ${disk_tf_version}}"
}

disk_doctor_note() {
  case "${1##*/}" in
  dd | cmp | od | awk | sed | head | tr) disk_tool_flavor "$1" ;;
  *) ;;
  esac
}

disk_doctor_found() {
  disk_df_note="$(disk_doctor_note "$1")"
  printf '%s%s\n' "$1" "${disk_df_note:+, ${disk_df_note}}"
}

disk_doctor_tool() {
  disk_dt_found="$(command -v "$1" 2>/dev/null || true)"
  if [ -n "${disk_dt_found}" ]; then
    disk_dt_detail="$(disk_doctor_found "${disk_dt_found}")"
    disk_doctor_row "$1" ok "${disk_dt_detail}"
    return 0
  fi
  disk_doctor_row "$1" missing "$2"
  return 1
}

disk_doctor_platform() {
  disk_dp_status=0
  case "$(uname -s)" in
  Darwin)
    disk_doctor_tool diskutil "lists, partitions and ejects disks" || disk_dp_status=1
    disk_doctor_tool plutil "reads disk details" || disk_dp_status=1
    ;;
  *)
    disk_doctor_tool lsblk "lists disks" || disk_dp_status=1
    disk_doctor_tool blockdev "reads disk sizes" || disk_dp_status=1
    ;;
  esac
  disk_doctor_optional mformat "mtools package, needed only by fix"
  return "${disk_dp_status}"
}

disk_doctor_optional() {
  disk_do_found="$(command -v "$1" 2>/dev/null || true)"
  if [ -n "${disk_do_found}" ]; then
    disk_doctor_row "$1" ok "${disk_do_found}"
    return 0
  fi
  disk_doctor_row "$1" warn "$2"
  return 0
}

disk_doctor_core() {
  disk_dc_status=0
  for disk_dc_tool in dd cmp od awk sed head tr sudo; do
    disk_doctor_tool "${disk_dc_tool}" "required" || disk_dc_status=1
  done
  disk_doctor_platform || disk_dc_status=1
  return "${disk_dc_status}"
}

disk_doctor() {
  disk_dr_status=0
  disk_doctor_tool gum "install with: brew install gum, or see https://github.com/charmbracelet/gum" || disk_dr_status=1
  disk_doctor_core || disk_dr_status=1
  disk_doctor_report "${disk_dr_status}"
  return "${disk_dr_status}"
}

disk_cli_interactive() {
  [ "${NISEMONO_INTERACTIVE:-}" = 1 ] && return 0
  [ -t 0 ]
}

disk_prompt() {
  if disk_ui_prompts; then
    disk_pq_answer="$(disk_ui_input "$1" "${2:-$1}")" || return 1
    printf '%s\n' "${disk_pq_answer:-$2}"
    return 0
  fi
  if [ -n "$2" ]; then
    printf '%s [%s]: ' "$1" "$2" >&2
  else
    printf '%s: ' "$1" >&2
  fi
  disk_pq_typed=""
  IFS= read -r disk_pq_typed || [ -n "${disk_pq_typed}" ] || return 1
  printf '%s\n' "${disk_pq_typed:-$2}"
}

disk_pick_single() {
  disk_ps_list="$(DISK_PICK_PROMPT="$1" disk_pick_targets)" || return 1
  disk_ps_count="$(printf '%s\n' "${disk_ps_list}" | awk 'NF' | wc -l | tr -d '[:space:]')"
  if [ "${disk_ps_count}" -ne 1 ]; then
    disk_error "pick exactly one disk."
    return 1
  fi
  printf '%s\n' "${disk_ps_list}"
}

disk_cli_is_option() {
  case "$1" in
  --* | -?*) return 0 ;;
  *) return 1 ;;
  esac
}

disk_cli_takes_value() {
  case " ${DISK_VALUE_OPTIONS} " in
  *" $1 "*) return 0 ;;
  *) return 1 ;;
  esac
}

disk_cli_assign() {
  if ! disk_cli_takes_value "${1%%=*}"; then
    if disk_option_flag "${1%%=*}"; then
      disk_cli_hint "option '${1%%=*}' takes no value"
    else
      disk_cli_hint "unknown option '${1%%=*}'"
    fi
    return 1
  fi
  disk_option_value "${1%%=*}" "${1#*=}"
}

disk_cli_option() {
  DISK_CLI_USED=0
  case "$1" in
  --*=*) disk_cli_assign "$1" ;;
  --?*)
    disk_option_flag "$1" && return 0
    if ! disk_cli_takes_value "$1"; then
      disk_cli_hint "unknown option '$1'"
      return 1
    fi
    if [ "$2" -lt 1 ]; then
      disk_cli_hint "option '$1' needs a value"
      return 1
    fi
    DISK_CLI_USED=1
    disk_option_value "$1" "$3"
    ;;
  *)
    disk_cli_hint "unknown option '$1'"
    return 1
    ;;
  esac
}
