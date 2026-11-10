#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

# shellcheck disable=SC2034
disk_ui_set() {
  DISK_UI_ACCENT="$1"
  DISK_UI_OK="$2"
  DISK_UI_WARN="$3"
  DISK_UI_ERR="$4"
  DISK_UI_MUTED="$5"
  DISK_UI_TEXT="$6"
  DISK_UI_SURFACE="$7"
  DISK_UI_HELP="$8"
}

disk_ui_palette() {
  case "$1" in
  kodougu) disk_ui_set "#F25D94" "#50FA7B" "#FFB86C" "#FF5555" "#6C7086" "#CDD6F4" "#313244" pink ;;
  catppuccin-mocha) disk_ui_set "#CBA6F7" "#A6E3A1" "#FAB387" "#F38BA8" "#6C7086" "#CDD6F4" "#313244" dark ;;
  catppuccin-latte) disk_ui_set "#8839EF" "#40A02B" "#FE640B" "#D20F39" "#8C8FA1" "#4C4F69" "#CCD0DA" light ;;
  dracula) disk_ui_set "#BD93F9" "#50FA7B" "#FFB86C" "#FF5555" "#6272A4" "#F8F8F2" "#44475A" dracula ;;
  nord) disk_ui_set "#88C0D0" "#A3BE8C" "#EBCB8B" "#BF616A" "#4C566A" "#D8DEE9" "#3B4252" dark ;;
  gruvbox) disk_ui_set "#FE8019" "#B8BB26" "#FABD2F" "#FB4934" "#928374" "#EBDBB2" "#3C3836" dark ;;
  tokyo-night) disk_ui_set "#7AA2F7" "#9ECE6A" "#E0AF68" "#F7768E" "#565F89" "#C0CAF5" "#292E42" tokyo-night ;;
  mono) disk_ui_set "" "" "" "" "" "" "" ascii ;;
  *) return 1 ;;
  esac
}

disk_ui_is_colour() {
  case "$1" in
  \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) return 0 ;;
  *) return 1 ;;
  esac
}

# shellcheck disable=SC2034
disk_ui_setup() {
  if ! disk_ui_palette "${DISK_THEME}"; then
    disk_ui_palette mono
    DISK_UI_PROBLEM="--theme must be one of ${DISK_UI_THEMES}, got: ${DISK_THEME}"
    return 1
  fi
  if [ -n "${DISK_ACCENT}" ] && ! disk_ui_is_colour "${DISK_ACCENT}"; then
    DISK_UI_PROBLEM="KODOUGU_ACCENT must be a colour such as #CBA6F7, got: ${DISK_ACCENT}"
    return 1
  fi
  if [ -n "${DISK_ACCENT}" ]; then
    DISK_UI_ACCENT="${DISK_ACCENT}"
  fi
  if [ -n "${NO_COLOR:-}" ]; then
    disk_ui_palette mono
  fi
}

disk_ui_forced() {
  [ "${NISEMONO_TEST_GUM:-}" = 1 ]
}

disk_ui_has_gum() {
  command -v gum >/dev/null 2>&1
}

disk_ui_prompts() {
  disk_ui_forced && return 0
  [ -t 0 ] && [ -t 2 ] && disk_ui_has_gum
}

disk_ui_err() {
  disk_ui_forced && return 0
  [ "${DISK_UI_STEP}" = 1 ] && return 0
  [ -t 2 ] && disk_ui_has_gum
}

disk_ui_out() {
  disk_ui_forced && return 0
  [ -t 1 ] && disk_ui_has_gum
}

disk_gum() {
  if [ -n "${DISK_UI_TEXT}" ]; then
    CLICOLOR_FORCE=1 gum "$@"
    return
  fi
  gum "$@"
}

disk_ui_ink() {
  disk_ui_colour="$1"
  shift
  if [ -z "${disk_ui_colour}" ]; then
    disk_gum style "$@"
    return
  fi
  disk_gum style --foreground "${disk_ui_colour}" "$@"
}

disk_ui_header() {
  disk_uh_name=$(disk_ui_ink "${DISK_UI_ACCENT}" --bold -- "nisemono")
  disk_uh_number=$(disk_version | sed -n '1p')
  disk_uh_number="${disk_uh_number#nisemono }"
  disk_uh_version=$(disk_ui_ink "${DISK_UI_MUTED}" -- "${disk_uh_number}")
  disk_uh_tagline=$(disk_ui_ink "${DISK_UI_TEXT}" -- "${DISK_TAGLINE}")
  disk_uh_top=$(disk_gum join --horizontal "${disk_uh_name}" "  " "${disk_uh_version}")
  disk_uh_body=$(disk_gum join --vertical "${disk_uh_top}" "${disk_uh_tagline}")
  printf '\n' >&2
  disk_gum style --border rounded --border-foreground "${DISK_UI_ACCENT}" --padding "0 2" -- "${disk_uh_body}" >&2
  printf '\n' >&2
}

disk_ui_title() {
  printf '\n' >&2
  disk_ui_ink "${DISK_UI_ACCENT}" --bold -- "$1" >&2
  printf '\n' >&2
}

disk_ui_titled() {
  if disk_ui_prompts; then
    disk_ui_title "$1"
  fi
}

disk_ui_lower_first() {
  printf '%s\n' "$1" | awk 'NR == 1 { a = substr($0, 1, 1); b = substr($0, 2, 1); if (a != tolower(a) && b != toupper(b)) { $0 = tolower(a) substr($0, 2) } } { print }'
}

disk_ui_log() {
  disk_ul_level="$1"
  disk_ul_text=$(disk_ui_lower_first "$2")
  case "${disk_ul_level}" in
  ERROR) disk_ul_colour="${DISK_UI_ERR}" ;;
  WARN) disk_ul_colour="${DISK_UI_WARN}" ;;
  *) disk_ul_colour="${DISK_UI_OK}" ;;
  esac
  disk_ul_label=$(disk_ui_ink "${disk_ul_colour}" --bold -- "${disk_ul_level}")
  printf '%s nisemono: %s\n' "${disk_ul_label}" "${disk_ul_text}" >&2
}

disk_ui_choose() {
  disk_uc_header="$1"
  shift
  disk_gum choose --header "${disk_uc_header}" --cursor "> " --height 14 \
    --cursor.foreground "${DISK_UI_ACCENT}" --selected.foreground "${DISK_UI_ACCENT}" \
    --header.foreground "${DISK_UI_TEXT}" "$@"
}

disk_ui_input() {
  disk_ui_header_text="$1"
  disk_ui_placeholder="$2"
  shift 2
  disk_gum input --header "${disk_ui_header_text}" --placeholder "${disk_ui_placeholder}" --prompt "> " \
    --prompt.foreground "${DISK_UI_ACCENT}" --cursor.foreground "${DISK_UI_ACCENT}" \
    --header.foreground "${DISK_UI_TEXT}" --placeholder.foreground "${DISK_UI_MUTED}" "$@"
}

disk_ui_write() {
  disk_gum write --header "$1" --placeholder "$2" --width 72 --height 8 --show-line-numbers \
    --cursor.foreground "${DISK_UI_ACCENT}" --header.foreground "${DISK_UI_TEXT}" \
    --placeholder.foreground "${DISK_UI_MUTED}"
}

disk_ui_confirm() {
  disk_ucf_prompt="$1"
  disk_ucf_yes="$2"
  disk_ucf_no="$3"
  shift 3
  disk_gum confirm "${disk_ucf_prompt}" --affirmative "${disk_ucf_yes}" --negative "${disk_ucf_no}" \
    --prompt.foreground "${DISK_UI_TEXT}" --selected.background "${DISK_UI_ACCENT}" \
    --unselected.background "${DISK_UI_SURFACE}" "$@"
}

disk_ui_summary() {
  disk_us2_pairs=$(($# / 2))
  while [ "${disk_us2_pairs}" -gt 0 ]; do
    disk_us2_label=$(printf '%-7s' "$1")
    disk_us2_label=$(disk_ui_ink "${DISK_UI_MUTED}" -- "${disk_us2_label}")
    disk_us2_value=$(disk_ui_ink "${DISK_UI_TEXT}" --bold -- "$2")
    shift 2
    set -- "$@" "${disk_us2_label} ${disk_us2_value}"
    disk_us2_pairs=$((disk_us2_pairs - 1))
  done
  printf '\n'
  disk_gum style --border rounded --border-foreground "${DISK_UI_MUTED}" --padding "0 1" -- "$@"
  printf '\n'
}

disk_ui_spin() {
  disk_us_title="$1"
  disk_us_log="$2"
  shift 2
  (DISK_UI_STEP=1 && "$@") 2>"${disk_us_log}" &
  disk_us_pid=$!
  if ! disk_ui_spin_wait "${disk_us_title}" "${disk_us_pid}"; then
    kill "${disk_us_pid}" 2>/dev/null
    exit 130
  fi
  disk_us_status=0
  wait "${disk_us_pid}" || disk_us_status=$?
  cat "${disk_us_log}" >&2
  return "${disk_us_status}"
}

disk_ui_spin_wait() {
  # shellcheck disable=SC2016
  disk_uw_loop='while kill -0 "$1" 2>/dev/null; do sleep 0.1; done'
  disk_gum spin --spinner dot --spinner.foreground "${DISK_UI_ACCENT}" --title.foreground "${DISK_UI_TEXT}" --title "$1" -- sh -c "${disk_uw_loop}" _ "$2" >&2
}

disk_ui_table() {
  disk_ut_line="-"
  if [ -n "${DISK_UI_TEXT}" ]; then
    disk_ut_line=$(printf '\342\224\200')
  fi
  disk_ut_body=$(disk_ui_table_body "${disk_ut_line}")
  disk_gum style --border rounded --border-foreground "${DISK_UI_MUTED}" --padding "0 1" -- "${disk_ut_body}"
}

disk_ui_table_body() {
  LC_ALL=C awk -F '\t' -v acc="${DISK_UI_ACCENT}" -v ok="${DISK_UI_OK}" -v warn="${DISK_UI_WARN}" \
    -v bad="${DISK_UI_ERR}" -v txt="${DISK_UI_TEXT}" -v mut="${DISK_UI_MUTED}" -v dash="$1" \
    -f "${DISK_LIB}/table.awk"
}

disk_ui_done() {
  printf '\n'
  disk_ui_ink "${DISK_UI_OK}" --bold -- "$1"
}

disk_ui_badge() {
  disk_ub_colour="$1"
  shift
  if [ -z "${disk_ub_colour}" ]; then
    disk_gum style --bold --underline --padding "0 1" -- "$*"
    return
  fi
  disk_gum style --background "${disk_ub_colour}" --foreground "#1E1E2E" --bold --padding "0 1" -- "$*"
}

disk_ui_chip() {
  if [ -z "${DISK_UI_SURFACE}" ]; then
    disk_gum style --padding "0 1" -- "$1"
    return
  fi
  disk_gum style --background "${DISK_UI_SURFACE}" --foreground "${DISK_UI_TEXT}" --padding "0 1" -- "$1"
}

disk_ui_danger() {
  disk_ud_title=$(disk_ui_ink "${DISK_UI_ERR}" --bold -- "$1")
  shift
  disk_gum style --border thick --border-foreground "${DISK_UI_ERR}" --padding "0 1" -- "${disk_ud_title}" "$@" >&2
}

disk_ui_markdown() {
  awk '
    NR == 1 {
      split($0, head, " - ")
      printf "# %s\n\n%s\n", head[1], head[2]
      next
    }
    /^[a-z][a-z ]*:$/ {
      if (open) { print "```" }
      printf "\n## %s\n\n```text\n", toupper(substr($0, 1, 1)) substr($0, 2, length($0) - 2)
      open = 1
      next
    }
    { print }
    END { if (open) { print "```" } }
  '
}
