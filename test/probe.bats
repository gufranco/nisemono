#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-probe.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  disk_test_setup_env
  disk_test_image "${WORK}/card.img" 32
  DEVICE="$(disk_test_attach "${WORK}/card.img")"
}

teardown() {
  fake_counterfeit_release
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

probe() {
  local target="$1"
  shift
  printf '%s\n' "${CONFIRM:-${target##*/}}" | NISEMONO_INTERACTIVE=1 disk_test_run nisemono probe --samples 32 "$@" "${target}"
}

@test "nisemono probe passes a disk whose every test block comes back" {
  # Arrange
  local target="${DEVICE}"

  # Act
  run probe "${target}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[-2]}" == "Result: 33 of 33 blocks read back as written" ]]
  [[ "${lines[-1]}" == "No fault found. Every test block across the 32.0 MiB of ${target} came back as written." ]]
}

@test "nisemono probe finds the exact end of the flash when writes past it are lost off the grid" {
  # Arrange
  local target
  target="$(fake_counterfeit "${DEVICE}" 9961472 lost)"

  # Act
  run probe "${target}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${lines[-3]}" == "Result: 9.5 MiB (9961472 bytes) of the 32.0 MiB it reports" ]]
  [[ "${lines[-1]}" == "Fake. ${target} holds 9.5 MiB, not 32.0 MiB." ]]
}

@test "nisemono probe finds a wrap whose size is not a power of two" {
  # Arrange
  local target
  target="$(fake_counterfeit "${DEVICE}" 9961472 wrap)"

  # Act
  run probe "${target}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${lines[-3]}" == "Result: 9.5 MiB (9961472 bytes) of the 32.0 MiB it reports" ]]
  [[ "${lines[-1]}" == "Fake. ${target} holds 9.5 MiB, not 32.0 MiB." ]]
}

@test "nisemono probe names the real size of a disk that wraps past it" {
  # Arrange
  local target
  target="$(fake_counterfeit "${DEVICE}" 8388608 wrap)"

  # Act
  run probe "${target}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${lines[-3]}" == "Result: 8.0 MiB (8388608 bytes) of the 32.0 MiB it reports" ]]
  [[ "${lines[-2]}" == "        24 blocks came back from a lower address, 0 were lost" ]]
  [[ "${lines[-1]}" == "Fake. ${target} holds 8.0 MiB, not 32.0 MiB." ]]
}

@test "nisemono probe names the real size of a disk that loses writes past it" {
  # Arrange
  local target
  target="$(fake_counterfeit "${DEVICE}" 8388608 lost)"

  # Act
  run probe "${target}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${lines[-3]}" == "Result: 8.0 MiB (8388608 bytes) of the 32.0 MiB it reports" ]]
  [[ "${lines[-2]}" == "        0 blocks came back from a lower address, 25 were lost" ]]
  [[ "${lines[-1]}" == "Fake. ${target} holds 8.0 MiB, not 32.0 MiB." ]]
}

@test "nisemono probe stops when a block fails while it narrows down the real size" {
  # Arrange
  local target
  target="$(fake_counterfeit "${DEVICE}" 8388608 lost)"
  export FAKE_FAIL_SEEK=1024
  if [[ "${NISEMONO_TEST_OS}" == "Linux" ]]; then
    disk_test_shim dd "case \" \$* \" in *\" seek=1024 \"*) printf 'dd: error writing: Input/output error\\n' >&2; exit 1 ;; esac
exec \"\$REAL\" \"\$@\""
  fi

  # Act
  run probe "${target}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: stopped: a block could not be tested while narrowing down the real size of ${target}."* ]]
}

@test "nisemono probe --json prints the verdict of a fake disk as one object" {
  # Arrange
  local target device
  target="$(fake_counterfeit "${DEVICE}" 8388608 wrap)"
  device="\"${target}\""

  # Act
  run probe "${target}" --json

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *": {\"device\":${device},\"reported_bytes\":33554432,\"real_bytes\":8388608,\"verified_bytes\":8388608,\"verdict\":\"fake\",\"ok\":9,\"wrapped\":24,\"lost\":0}" ]]
}

@test "nisemono probe writes nothing when the typed name is wrong" {
  # Arrange
  local target="${DEVICE}"
  CONFIRM=nope

  # Act
  run probe "${target}"

  # Assert
  local bytes
  bytes="$(disk_test_unique_bytes "${WORK}/card.img")"
  [[ "${status}" -eq 1 ]]
  [[ "${lines[-1]}" == "Type ${target##*/} to probe, or anything else to stop: nisemono: warning: cancelled, nothing was touched." ]]
  [[ "${bytes}" == "00" ]]
}

@test "nisemono probe refuses a sample count that is not a whole number" {
  # Arrange
  local target="${DEVICE}"

  # Act
  run disk_test_run nisemono probe --samples=many "${target}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: --samples must be a whole number of 1 or more, got: many" ]]
}
