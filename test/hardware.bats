#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-hardware.XXXXXX")"
  export NISEMONO_SAMPLES=4
  if [[ "${NISEMONO_TEST_OS}" == "Linux" ]]; then
    export NISEMONO_ALLOW_INTERNAL=y
  fi
  IMAGE="${WORK}/target.img"
  disk_test_fill "${IMAGE}" 2 '\252'
  DEVICE="$(disk_test_attach "${IMAGE}")"
  NAME="${DEVICE##*/}"
  SHIMS="${WORK}/shims"
  export SHIMS
  fake_install
}

teardown() {
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

probing() {
  printf '%s\n' "${NAME}" | disk_test_run nisemono probe "${DEVICE}"
}

@test "nisemono stops on media the drive reports as read-only" {
  # Arrange
  fake_read_only

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: stopped: ${DEVICE} is write protected, so nothing on it can be probed."* ]]
  [[ "${output}" == *"Slide the lock switch on the card or adapter up, then run this again."* ]]
}

@test "nisemono stops when the disk size cannot be read" {
  # Arrange
  fake_size_unknown

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: unable to determine disk size for ${DEVICE}."* ]]
}

@test "nisemono stops when the disk stays mounted" {
  # Arrange
  fake_flag unmount-fails
  printf '%s on /Volumes/FAKE (msdos, local)\n' "${DEVICE}" >"$(fake_dir)/mounts"
  printf '/mnt/fake\n' >>"$(fake_dir)/mounts"

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"disk is still mounted, so writing to it would corrupt the mounted volume"* ]]
}

@test "nisemono stops when the mount state cannot be read" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "macOS reads the mount table directly"
  fake_flag mount-state-fails

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"unable to read the mount state of ${DEVICE}, so this stops here"* ]]
}

@test "nisemono refuses a path that is neither a device nor a mount point" {
  # Arrange
  local file="${WORK}/not-a-disk"
  : >"${file}"

  # Act
  run disk_test_run nisemono probe "${file}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: not a device or mount point: ${file}" ]]
}
