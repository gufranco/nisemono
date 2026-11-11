#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-cli.XXXXXX")"
}

teardown() {
  rm -rf "${WORK}"
}

minimal_path() {
  local bin="${WORK}/bin"
  local tool
  local found
  mkdir -p "${bin}"
  for tool in sh uname awk sed tr wc cat dirname env; do
    found="$(command -v "${tool}")"
    ln -s "${found}" "${bin}/${tool}"
  done
  printf '%s' "${bin}"
}

@test "nisemono help prints the usage page on stdout" {
  # Arrange
  local program=nisemono

  # Act
  run disk_test_run "${program}" help

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "nisemono - find out whether a card or USB drive holds what it claims" ]]
}

@test "nisemono version names the program and its version" {
  # Arrange
  local version
  version="$(sed -n 's/^NISEMONO_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"

  # Act
  run disk_test_run nisemono --version

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "nisemono ${version}" ]]
}

@test "nisemono rejects an unknown command with a usage hint" {
  # Arrange
  local command=wipe

  # Act
  run disk_test_run nisemono "${command}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: unknown command 'wipe'. run 'nisemono help' for usage." ]]
}

@test "nisemono rejects an unknown option with a usage hint" {
  # Arrange
  local option=--fast

  # Act
  run disk_test_run nisemono probe "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: unknown option '--fast'. run 'nisemono help' for usage." ]]
}

@test "nisemono reads options given before any command as probe options" {
  # Arrange
  local missing="${WORK}/missing"

  # Act
  run disk_test_run nisemono --json "${missing}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: not a device or mount point: ${missing}" ]]
}

@test "nisemono with no arguments and no terminal fails with a hint" {
  # Arrange
  local program=nisemono

  # Act
  run disk_test_run "${program}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: no disk given. run 'nisemono help' for usage." ]]
}

@test "nisemono probe with no disk and no terminal fails with a hint" {
  # Arrange
  local command=probe

  # Act
  run disk_test_run nisemono "${command}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: no disk given. run 'nisemono help' for usage." ]]
}

@test "nisemono doctor lists the tools a probe needs" {
  # Arrange
  local program=nisemono

  # Act
  run disk_test_run "${program}" doctor

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ (^|$'\n')dd\ +ok\  ]]
  [[ "${output}" =~ (^|$'\n')od\ +ok\  ]]
  [[ "${output}" != *"openssl"* ]]
}

@test "nisemono doctor fails and names a missing core tool" {
  # Arrange
  local bin
  bin="$(minimal_path)"

  # Act
  run env PATH="${bin}" "${bin}/sh" "${REPO_DIR}/bin/nisemono" doctor

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" =~ (^|$'\n')dd\ +missing\ +required ]]
}

@test "nisemono names an option that is missing its value" {
  # Arrange
  local option=--samples

  # Act
  run disk_test_run nisemono probe "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: option '--samples' needs a value. run 'nisemono help' for usage." ]]
}

@test "nisemono refuses a value given to an option that takes none" {
  # Arrange
  local option=--json=yes

  # Act
  run disk_test_run nisemono probe "${option}" /dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: option '--json' takes no value. run 'nisemono help' for usage." ]]
}

@test "nisemono names an unknown option written as name=value" {
  # Arrange
  local option=--speed=fast

  # Act
  run disk_test_run nisemono probe "${option}" /dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: unknown option '--speed'. run 'nisemono help' for usage." ]]
}

@test "nisemono lets an option on the command line win over the environment" {
  # Arrange
  local settings="NISEMONO_SAMPLES=0"

  # Act
  run disk_test_run_env "${settings}" nisemono probe --samples 8 "${WORK}/missing"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: not a device or mount point: ${WORK}/missing" ]]
}

@test "nisemono reads the sample count from the environment" {
  # Arrange
  local settings="NISEMONO_SAMPLES=none"

  # Act
  run disk_test_run_env "${settings}" nisemono probe "${WORK}/missing"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: --samples must be a whole number of 1 or more, got: none" ]]
}

@test "nisemono treats everything after -- as the disk" {
  # Arrange
  local disk=--odd-name

  # Act
  run disk_test_run nisemono probe -- "${disk}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: not a device or mount point: --odd-name" ]]
}

@test "nisemono refuses a second disk" {
  # Arrange
  local second=/dev/second

  # Act
  run disk_test_run nisemono probe /dev/first "${second}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: unexpected extra argument '/dev/second'. run 'nisemono help' for usage." ]]
}

help_options() {
  local page
  page="$(disk_test_run nisemono help)" || return 1
  awk '/^  --/ { for (i = 1; i <= NF; i++) if (match($i, /^--[a-z0-9][a-z0-9-]*/)) { name = substr($i, RSTART, RLENGTH); if (!seen[name]++) print name } }' <<<"${page}"
}

option_drift() {
  local option name man_form missing="" listed completed
  listed="$(help_options)" || return 1
  completed="$(grep -oE -- "--[a-z0-9][a-z0-9-]*" "${REPO_DIR}/completions/nisemono.bash")" || return 1
  for option in ${listed}; do
    name="${option#--}"
    man_form="\\-\\-${name//-/\\-}"
    grep -qF -- "${man_form}" "${REPO_DIR}/man/nisemono.1" || missing="${missing} man:${option}"
    grep -qE -- "(^|[ \"])${option}( |\"|$)" "${REPO_DIR}/completions/nisemono.bash" || missing="${missing} bash:${option}"
    grep -qE -- "'\\*?${option}\\[" "${REPO_DIR}/completions/_nisemono" || missing="${missing} zsh:${option}"
    grep -qE -- "-l ${name} " "${REPO_DIR}/completions/nisemono.fish" || missing="${missing} fish:${option}"
  done
  for option in ${completed}; do
    grep -qx -- "${option}" <<<"${listed}" || missing="${missing} help:${option}"
  done
  printf '%s' "${missing}"
}

@test "nisemono help, man page and completions list the same options" {
  # Arrange
  local expected=""

  # Act
  run option_drift

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "nisemono man page passes mandoc lint" {
  # Arrange
  local page="${REPO_DIR}/man/nisemono.1"

  # Act
  run mandoc -T lint "${page}"

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "nisemono accepts every switch before the disk" {
  # Arrange
  local missing="${WORK}/missing"

  # Act
  run disk_test_run nisemono probe --allow-internal --json "${missing}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: not a device or mount point: ${missing}" ]]
}

@test "nisemono rejects an unknown short option with a usage hint" {
  # Arrange
  local option=-x

  # Act
  run disk_test_run nisemono probe "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: unknown option '-x'. run 'nisemono help' for usage." ]]
}

@test "nisemono help, man page and completions list every command" {
  # Arrange
  local command missing=""

  # Act
  run disk_test_run nisemono help

  # Assert
  for command in probe fill fix; do
    [[ "${output}" == *"nisemono ${command} "* ]] || missing="${missing} help:${command}"
    grep -qF -- ".B nisemono ${command}" "${REPO_DIR}/man/nisemono.1" || missing="${missing} man:${command}"
    grep -qE -- "words=\"[^\"]*\\b${command}\\b" "${REPO_DIR}/completions/nisemono.bash" || missing="${missing} bash:${command}"
    grep -qF -- "'${command}:" "${REPO_DIR}/completions/_nisemono" || missing="${missing} zsh:${command}"
    grep -qF -- "-a ${command} " "${REPO_DIR}/completions/nisemono.fish" || missing="${missing} fish:${command}"
  done
  [[ "${status}" -eq 0 ]]
  [[ -z "${missing}" ]]
}
