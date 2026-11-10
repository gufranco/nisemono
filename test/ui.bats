#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-ui.XXXXXX")"
  if [[ "${NISEMONO_TEST_OS}" == "Linux" ]]; then
    export NISEMONO_ALLOW_INTERNAL=y
  fi
  IMAGE="${WORK}/target.img"
  disk_test_fill "${IMAGE}" 2 '\252'
  DEVICE="$(disk_test_attach "${IMAGE}")"
  NAME="${DEVICE##*/}"
  unset KODOUGU_THEME KODOUGU_ACCENT NISEMONO_THEME NO_COLOR
  export NISEMONO_TEST_GUM=1
  export NISEMONO_TEST_GUM_LOG="${WORK}/gum.log"
  export NISEMONO_TEST_GUM_ANSWERS="${WORK}/answers"
  export NISEMONO_INTERACTIVE=1
  export NISEMONO_SAMPLES=4
  : >"${NISEMONO_TEST_GUM_LOG}"
}

teardown() {
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

answers() {
  printf '%s\n' "$@" >"${NISEMONO_TEST_GUM_ANSWERS}"
}

never_called() {
  if grep -q -F -- "$1" "${NISEMONO_TEST_GUM_LOG}"; then
    return 1
  fi
}

called() {
  grep -q -F -- "$1" "${NISEMONO_TEST_GUM_LOG}"
}

untouched() {
  local bytes
  bytes="$(disk_test_range_bytes "${IMAGE}" 0 2097152)"
  [[ "${bytes}" == "aa" ]]
}

@test "the disk is picked from a gum list, its name typed in a danger box, and probed" {
  # Arrange
  local bar
  bar="$(printf '\342\224\201')"
  answers "${DEVICE}" "${NAME}"

  # Act
  run disk_test_run nisemono </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"find out whether a card or USB drive holds what it claims"* ]]
  [[ "${output}" == *"Device:"*"${DEVICE}"* ]]
  [[ "${output}" == *"${bar}"* ]]
  [[ "${output}" == *"No fault found. Every test block across the 2.0 MiB of ${DEVICE} came back as written."* ]]
  called "choose --header Probe which disk?"
  called "--border thick"
  called "input --header Type ${NAME} to probe"
}

@test "a cancelled disk pick probes nothing" {
  # Arrange
  answers "<cancel>"

  # Act
  run disk_test_run nisemono </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  untouched
}

@test "a wrong name typed into gum probes nothing" {
  # Arrange
  answers "disk999"

  # Act
  run disk_test_run nisemono probe "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"WARN nisemono: cancelled, nothing was touched."* ]]
  untouched
}

@test "a cancelled typed name probes nothing" {
  # Arrange
  answers "<cancel>"

  # Act
  run disk_test_run nisemono probe "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"cancelled, nothing was touched."* ]]
  untouched
}

@test "a fake verdict is drawn in the error colour" {
  # Arrange
  local call='DISK_VERDICT=fake DISK_SIZE=4194304 DISK_REAL=2097152 DISK_WRAPPED=1 DISK_LOST=0 disk_probe_result /dev/disk9'

  # Act
  run disk_test_call eval "disk_ui_setup && ${call}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Fake. /dev/disk9 holds 2.0 MiB, not 4.0 MiB."* ]]
  called "--foreground #FF5555 --bold -- Fake. /dev/disk9 holds 2.0 MiB, not 4.0 MiB."
}

@test "doctor draws its rows in a table" {
  # Arrange
  local expected="dd"

  # Act
  run disk_test_run nisemono doctor </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Tool"*"State"*"Detail"* ]]
  [[ "${output}" == *"${expected}"* ]]
  [[ "${output}" == *"Ready. Every tool nisemono needs is here."* ]]
}

@test "doctor reports a missing tool below the table" {
  # Arrange
  local farm
  farm="$(disk_test_farm od)"

  # Act
  run disk_test_run_path "${farm}" nisemono doctor </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"ERROR nisemono: a required tool is missing."* ]]
}

@test "doctor draws a missing fix tool as a warning on Linux" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "macOS partitions through diskutil"
  local farm
  farm="$(disk_test_farm mkfs.exfat)"

  # Act
  run disk_test_run_path "${farm}" nisemono doctor </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"mkfs.exfat"*"warn"*"exfatprogs package, needed only by fix"* ]]
}

@test "doctor fails without gum" {
  # Arrange
  local farm
  farm="$(disk_test_farm gum)"

  # Act
  NISEMONO_TEST_GUM=0 run disk_test_run_path "${farm}" nisemono doctor </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"gum                missing  install with: brew install gum"* ]]
}

@test "version shows the version and platform as badges" {
  # Arrange
  local version
  version="$(sed -n 's/^NISEMONO_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"

  # Act
  run disk_test_run nisemono version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "nisemono ${version} platform "* ]]
}

@test "help is formatted with gum" {
  # Arrange
  local expected="## Usage"

  # Act
  run disk_test_run nisemono help </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"${expected}"* ]]
  called "format --theme pink"
}

@test "--theme picks the palette over the environment" {
  # Arrange
  local theme="nord"

  # Act
  KODOUGU_THEME=dracula NISEMONO_THEME=gruvbox run disk_test_run nisemono --theme "${theme}" version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #88C0D0"
}

@test "--theme= with a value picks the palette" {
  # Arrange
  local option="--theme=tokyo-night"

  # Act
  run disk_test_run nisemono "${option}" version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #7AA2F7"
}

@test "an unknown theme stops before the disk is touched" {
  # Arrange
  local theme="solarized"

  # Act
  KODOUGU_THEME="${theme}" run disk_test_run nisemono probe "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"got: solarized"* ]]
  untouched
}

@test "--theme without a value stops with the usage hint" {
  # Arrange
  local option="--theme"

  # Act
  run disk_test_run nisemono version "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"option '--theme' needs a value. run 'nisemono help' for usage."* ]]
}

@test "--theme after -- names the disk" {
  # Arrange
  local option="--theme"

  # Act
  run disk_test_run nisemono probe -- "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"not a device or mount point: --theme"* ]]
}

@test "a message after a progress bar still running starts on its own line" {
  # Arrange
  local call='disk_progress Writing 512 1024 0; disk_info "Bypassing the page cache."'

  # Act
  run disk_test_call eval "disk_ui_setup && ${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"%"*$'\n'"Bypassing the page cache."* ]]
}
