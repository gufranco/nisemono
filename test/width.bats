#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d /tmp/disk-width.XXXXXX)"
}

teardown() {
  rm -rf "${WORK}"
}

widest_line() {
  awk '{ if (length($0) > widest) { widest = length($0) } } END { print widest + 0 }'
}

@test "help never prints a line wider than 80 columns" {
  # Arrange
  local page widest

  # Act
  page="$(disk_test_run nisemono help)"

  # Assert
  widest="$(printf '%s\n' "${page}" | widest_line)"
  [[ "${widest}" -le 80 ]]
}

@test "version never prints a line wider than 80 columns" {
  # Arrange
  local page widest

  # Act
  page="$(disk_test_run nisemono version)"

  # Assert
  widest="$(printf '%s\n' "${page}" | widest_line)"
  [[ "${widest}" -le 80 ]]
}

@test "an error stays on one line, however long" {
  # Arrange
  local message="the drive answered the write but read back a different byte on every pass of this chunk"

  # Act
  run disk_test_call disk_error "${message}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "nisemono: ${message}" ]]
}

@test "a doctor row stays on one line, however long" {
  # Arrange
  local expected="sha256sum|shasum   ok       /opt/homebrew/opt/uutils-coreutils/libexec/uubin/sha256sum, uutils 0.12.0"

  # Act
  run disk_test_call disk_doctor_row "sha256sum|shasum" ok "/opt/homebrew/opt/uutils-coreutils/libexec/uubin/sha256sum, uutils 0.12.0"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "internal DISK_ variables from the environment change nothing" {
  # Arrange
  local expected="nisemono: unknown option '--nope'. run 'nisemono help' for usage."

  # Act
  DISK_PROG=other run disk_test_run nisemono --nope

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}
