#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-refuse.XXXXXX")"
  IMAGE="${WORK}/target.img"
  disk_test_fill "${IMAGE}" 4 '\252'
  DEVICE="$(disk_test_attach "${IMAGE}")"
}

teardown() {
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

@test "nisemono never probes the disk holding the running system" {
  # Arrange
  local boot
  boot="$(disk_test_call call_first_boot_disk)"

  # Act
  run disk_test_run nisemono probe "${boot}" </dev/null

  # Assert
  [[ -n "${boot}" ]] || skip "no block device holds / on this host"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: stopped: ${boot} holds the running system, so it is never written." ]]
}

@test "nisemono refuses an internal disk without NISEMONO_ALLOW_INTERNAL" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "macOS reports attached disk images as external"
  local before after
  before="$(disk_test_range_bytes "${IMAGE}" 0 4194304)"

  # Act
  run disk_test_run nisemono probe "${DEVICE}" </dev/null

  # Assert
  after="$(disk_test_range_bytes "${IMAGE}" 0 4194304)"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: stopped: ${DEVICE} is an internal disk. use --allow-internal to test it on purpose." ]]
  [[ "${after}" == "${before}" ]]
}
