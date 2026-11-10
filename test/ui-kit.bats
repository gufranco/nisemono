# shellcheck disable=SC2016
# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  KIT="$(mktemp -d "${BATS_TMPDIR:-/tmp}/nisemono-ui-kit.XXXXXX")"
  export NISEMONO_TEST_GUM=1
  export NISEMONO_TEST_GUM_LOG="${KIT}/gum.log"
  export NISEMONO_TEST_GUM_ANSWERS="${KIT}/answers"
  unset KODOUGU_THEME KODOUGU_ACCENT NO_COLOR
  : >"${NISEMONO_TEST_GUM_LOG}"
}

teardown() {
  rm -rf "${KIT}"
}

answers() {
  printf '%s\n' "$@" >"${NISEMONO_TEST_GUM_ANSWERS}"
}

called() {
  grep -q -F -- "$1" "${NISEMONO_TEST_GUM_LOG}"
}

kit() {
  disk_test_call eval "disk_ui_setup && $1"
}

@test "the kodougu theme is the default" {
  # Arrange
  local call='disk_ui_badge "${DISK_UI_ACCENT}" x'

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #F25D94"
}

@test "the catppuccin-mocha theme uses mauve" {
  # Arrange
  local call='disk_ui_badge "${DISK_UI_ACCENT}" x'

  # Act
  KODOUGU_THEME=catppuccin-mocha run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #CBA6F7"
}

@test "the catppuccin-latte theme uses its darker mauve" {
  # Arrange
  local call='disk_ui_badge "${DISK_UI_ACCENT}" x'

  # Act
  KODOUGU_THEME=catppuccin-latte run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #8839EF"
}

@test "the dracula theme uses purple" {
  # Arrange
  local call='disk_ui_badge "${DISK_UI_ACCENT}" x'

  # Act
  KODOUGU_THEME=dracula run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #BD93F9"
}

@test "the nord theme uses frost blue" {
  # Arrange
  local call='disk_ui_badge "${DISK_UI_ACCENT}" x'

  # Act
  KODOUGU_THEME=nord run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #88C0D0"
}

@test "the gruvbox theme uses orange" {
  # Arrange
  local call='disk_ui_badge "${DISK_UI_ACCENT}" x'

  # Act
  KODOUGU_THEME=gruvbox run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #FE8019"
}

@test "the tokyo-night theme uses blue" {
  # Arrange
  local call='disk_ui_badge "${DISK_UI_ACCENT}" x'

  # Act
  KODOUGU_THEME=tokyo-night run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #7AA2F7"
}

@test "the mono theme draws a badge without colour" {
  # Arrange
  local call='disk_ui_badge "${DISK_UI_ACCENT}" x'

  # Act
  KODOUGU_THEME=mono run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  called "style --bold --underline --padding 0 1 -- x"
}

@test "an unknown theme fails setup with the list of themes" {
  # Arrange
  local call='printf "%s" "${DISK_UI_PROBLEM}"'

  # Act
  KODOUGU_THEME=solarized run disk_test_call eval "disk_ui_setup || ${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "--theme must be one of kodougu, catppuccin-mocha, catppuccin-latte, dracula, nord, gruvbox, tokyo-night, mono, got: solarized" ]]
}

@test "KODOUGU_ACCENT replaces the accent" {
  # Arrange
  local call='disk_ui_badge "${DISK_UI_ACCENT}" x'

  # Act
  KODOUGU_ACCENT="#ABCDEF" run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #ABCDEF"
}

@test "a malformed accent fails setup" {
  # Arrange
  local call='printf "%s" "${DISK_UI_PROBLEM}"'

  # Act
  KODOUGU_ACCENT="#12345" run disk_test_call eval "disk_ui_setup || ${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "KODOUGU_ACCENT must be a colour such as #CBA6F7, got: #12345" ]]
}

@test "NO_COLOR turns any theme into mono" {
  # Arrange
  local call='printf "[%s]" "${DISK_UI_ACCENT}"'

  # Act
  NO_COLOR=1 KODOUGU_THEME=nord run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "[]" ]]
}

@test "without the test switch and a terminal nothing is drawn with gum" {
  # Arrange
  local call='disk_ui_prompts || disk_ui_err || disk_ui_out || printf plain'

  # Act
  NISEMONO_TEST_GUM=0 run disk_test_call eval "${call}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "plain" ]]
}

@test "gum is found on PATH" {
  # Arrange
  local call='disk_ui_has_gum && printf found'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "found" ]]
}

@test "the header shows the name, version and tagline" {
  # Arrange
  local call='disk_ui_header'

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"nisemono"* ]]
  called "--border rounded"
}

@test "a title is drawn only where prompts are drawn" {
  # Arrange
  local call='disk_ui_titled "Pick one"'

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Pick one"* ]]
}

@test "each log level is labelled" {
  # Arrange
  local call='disk_ui_log INFO done; disk_ui_log WARN careful; disk_ui_log ERROR broken'

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "INFO nisemono: done" ]]
  [[ "${lines[1]}" == "WARN nisemono: careful" ]]
  [[ "${lines[2]}" == "ERROR nisemono: broken" ]]
}

@test "a long log line stays on one line" {
  # Arrange
  local word="abcdefghij" call
  call="disk_ui_log INFO \"$(printf '%s ' "${word}" "${word}" "${word}" "${word}" "${word}" "${word}" "${word}" "${word}")\""

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${#lines[@]}" -eq 1 ]]
  [[ "${lines[0]}" == "INFO nisemono: ${word} ${word} ${word} ${word} ${word} ${word} ${word} ${word}"* ]]
}

@test "choose, input and write return the answer" {
  # Arrange
  local call='disk_ui_choose Header a b; disk_ui_input Name hint; disk_ui_write Text hint'
  answers "b" "typed" "written"

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == $'b\ntyped\nwritten' ]]
}

@test "confirm returns yes or no" {
  # Arrange
  local call='disk_ui_confirm "Go?" Go Stop && printf yes; disk_ui_confirm "Go?" Go Stop || printf no'
  answers "yes" "no"

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "yesno" ]]
}

@test "confirm passes extra flags such as its default to gum" {
  # Arrange
  local call='disk_ui_confirm "Go?" Go Stop --default=false || printf no'
  answers "no"

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "no" ]]
  called "--default=false"
}

@test "a spinner waits for the step and keeps its status and diagnostics" {
  # Arrange
  local call="disk_ui_spin Working \"${KIT}/step.log\" sh -c '{ set +x; } 2>/dev/null; echo said >&2; exit 3' || printf 'status %s' \"\$?\""

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == $'said\nstatus 3' ]]
}

@test "a spinner step draws its diagnostics as the terminal would" {
  # Arrange
  local call="disk_ui_spin Working \"${KIT}/step.log\" eval 'disk_ui_err && printf drawn >&2'"

  # Act
  NISEMONO_TEST_GUM=0 run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "drawn" ]]
}

@test "a warning that starts with a capitalized word continues in lowercase" {
  # Arrange
  local call='disk_ui_log WARN "Renamed 1 of 3 ROMs."'

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "WARN nisemono: renamed 1 of 3 ROMs." ]]
}

@test "a warning that starts with an acronym keeps it" {
  # Arrange
  local call='disk_ui_log WARN "ISO trimmed to its real size."'

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "WARN nisemono: ISO trimmed to its real size." ]]
}

@test "an interrupted spinner stops with status 130" {
  # Arrange
  local call="disk_ui_spin Working \"${KIT}/step.log\" sleep 5"

  # Act
  NISEMONO_TEST_GUM_SPIN=cancel run kit "${call}"

  # Assert
  [[ "${status}" -eq 130 ]]
}

@test "a table aligns its columns and colours its states" {
  # Arrange
  local call
  call="printf 'Name\\tState\\nab\\t@ok:ok\\nc\\t@warn:warn\\nd\\t@bad:missing\\ne\\t@acc:new\\nf\\t@mut:off\\n' | disk_ui_table"

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"38;2;80;250;123mok"* ]]
  [[ "${output}" == *"38;2;255;85;85mmissing"* ]]
}

@test "a mono table draws its rule with dashes" {
  # Arrange
  local call="printf 'Name\\nab\\n' | disk_ui_table"

  # Act
  KODOUGU_THEME=mono run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"----"* ]]
}

@test "a mono table measures accented and wide letters by screen width" {
  # Arrange
  local call="printf 'Name\\tShort\\nStra\\303\\237e\\tX\\nabcdef\\tY\\n\\346\\227\\245\\346\\234\\254\\tZ\\n' | disk_ui_table"

  # Act
  KODOUGU_THEME=mono run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"$(printf 'Stra\303\237e   X')"* ]]
  [[ "${output}" == *"abcdef   Y"* ]]
  [[ "${output}" == *"$(printf '\346\227\245\346\234\254     Z')"* ]]
}

@test "the closing sentence, chips, danger box and summary carry their text" {
  # Arrange
  local call='disk_ui_done Finished; disk_ui_chip state; disk_ui_danger Careful detail; disk_ui_summary "Disk:" one "" two'

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Finished"* ]]
  [[ "${output}" == *"state"* ]]
  [[ "${output}" == *"Careful"* ]]
  [[ "${output}" == *"Disk:   one"$'\n'"        two"* ]]
  called "--border thick"
}

@test "mono chips have no background" {
  # Arrange
  local call='disk_ui_chip state'

  # Act
  KODOUGU_THEME=mono run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  called "style --padding 0 1 -- state"
}

@test "help text becomes markdown with a heading per section" {
  # Arrange
  local call="printf 'nisemono - does a thing\\n\\nusage:\\n  nisemono run\\n\\nnotes:\\n  text\\n' | disk_ui_markdown"

  # Act
  run kit "${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"# nisemono"* ]]
  [[ "${output}" == *"## Usage"* ]]
  [[ "${output}" == *"## Notes"* ]]
}
