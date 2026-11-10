#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-flavor.XXXXXX")"
}

teardown() {
  rm -rf "${WORK}"
}

fake_tool() {
  local path="$1"
  local text="$2"
  mkdir -p "${path%/*}"
  printf '#!/bin/sh\n{ set +x; } 2>/dev/null\nprintf "%%s\\n" "%s"\nexit 1\n' "${text}" >"${path}"
  chmod +x "${path}"
  printf '%s\n' "${path}"
}

flavor_of() {
  local tool
  tool="$(fake_tool "${WORK}/bin/$1" "$2")"
  NISEMONO_OS="${3:-Darwin}" disk_test_call disk_tool_flavor "${tool}"
}

flavor_at() {
  NISEMONO_OS=Darwin disk_test_call disk_tool_flavor "$1"
}

@test "GNU coreutils reads as gnu with its version" {
  # Arrange
  local text="dd (GNU coreutils) 9.5"

  # Act
  run flavor_of dd "${text}"

  # Assert
  [[ "${output}" == "gnu 9.5" ]]
}

@test "Ubuntu's GNU coreutils without the GNU word reads as gnu" {
  # Arrange
  local text="dd (coreutils) 9.7"

  # Act
  run flavor_of dd "${text}" Linux

  # Assert
  [[ "${output}" == "gnu 9.7" ]]
}

@test "uutils coreutils reads as uutils with its version" {
  # Arrange
  local text="dd (uutils coreutils) 0.12.0"

  # Act
  run flavor_of dd "${text}"

  # Assert
  [[ "${output}" == "uutils 0.12.0" ]]
}

@test "GNU awk reads as gnu with its own version, not its API version" {
  # Arrange
  local text="GNU Awk 5.3.2, API 4.0, PMA Avon 8-g1"

  # Act
  run flavor_of awk "${text}"

  # Assert
  [[ "${output}" == "gnu 5.3.2" ]]
}

@test "mawk reads as mawk" {
  # Arrange
  local text="mawk 1.3.4 20260129"

  # Act
  run flavor_of awk "${text}" Linux

  # Assert
  [[ "${output}" == "mawk 1.3.4" ]]
}

@test "the BSD awk reads as bsd with its date stamp" {
  # Arrange
  local text="awk version 20200816"

  # Act
  run flavor_of awk "${text}"

  # Assert
  [[ "${output}" == "bsd 20200816" ]]
}

@test "BusyBox reads as busybox" {
  # Arrange
  local text="BusyBox v1.36.1 (2024-06-10) multi-call binary."

  # Act
  run flavor_of sed "${text}" Linux

  # Assert
  [[ "${output}" == "busybox 1.36.1" ]]
}

@test "BusyBox that names itself after its error line reads as busybox" {
  # Arrange
  local text
  text="$(printf "awk: invalid option -- '-'\nBusyBox v1.37.0 (Ubuntu 1:1.37.0-7ubuntu1) multi-call binary.")"

  # Act
  run flavor_of awk "${text}" Linux

  # Assert
  [[ "${output}" == "busybox 1.37.0" ]]
}

@test "BusyBox sed, which says it is not GNU sed, reads as busybox" {
  # Arrange
  local text="This is not GNU sed version 4.0"

  # Act
  run flavor_of sed "${text}" Linux

  # Assert
  [[ "${output}" == "busybox" ]]
}

@test "the macOS sha256sum reads as bsd" {
  # Arrange
  local text="sha256sum (Darwin) 1.0"

  # Act
  run flavor_of sha256sum "${text}"

  # Assert
  [[ "${output}" == "bsd 1.0" ]]
}

@test "a tool that refuses --version on macOS reads as bsd" {
  # Arrange
  local text="sed: illegal option -- -"

  # Act
  run flavor_of sed "${text}" Darwin

  # Assert
  [[ "${output}" == "bsd" ]]
}

@test "a tool that refuses --version on Linux reads as unknown" {
  # Arrange
  local text="usage: od [-v] [file ...]"

  # Act
  run flavor_of od "${text}" Linux

  # Assert
  [[ "${output}" == "unknown" ]]
}

@test "a uutils tool that refuses --version is named by where it lives" {
  # Arrange
  local tool
  tool="$(fake_tool "${WORK}/uutils-diffutils/uubin/cmp" "unrecognized option '--version'")"

  # Act
  run flavor_at "${tool}"

  # Assert
  [[ "${output}" == "uutils" ]]
}

@test "a tool outside the core set carries no flavor note" {
  # Arrange
  local tool
  tool="$(fake_tool "${WORK}/bin/curl" "curl 8.10.1")"

  # Act
  run disk_test_call disk_doctor_note "${tool}"

  # Assert
  [[ "${output}" == "" ]]
}
