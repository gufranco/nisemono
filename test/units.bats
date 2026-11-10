#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

@test "dd: /dev/rdisk9: Device not configured is a bus error" {
  # Arrange
  local detail="dd: /dev/rdisk9: Device not configured"

  # Act
  run disk_test_call disk_error_class "${detail}"

  # Assert
  [[ "${output}" == "bus" ]]
}

@test "dd: error writing: Input/output error is a media error" {
  # Arrange
  local detail="dd: error writing: Input/output error"

  # Act
  run disk_test_call disk_error_class "${detail}"

  # Assert
  [[ "${output}" == "media" ]]
}

@test "dd: invalid number is a other error" {
  # Arrange
  local detail="dd: invalid number"

  # Act
  run disk_test_call disk_error_class "${detail}"

  # Assert
  [[ "${output}" == "other" ]]
}

@test "a duration under a second prints in milliseconds" {
  # Arrange
  local ms=250

  # Act
  run disk_test_call disk_duration "${ms}"

  # Assert
  [[ "${output}" == "250ms" ]]
}

@test "a duration over a second prints in whole seconds" {
  # Arrange
  local ms=4200

  # Act
  run disk_test_call disk_duration "${ms}"

  # Assert
  [[ "${output}" == "4s" ]]
}

@test "sizes print in binary units" {
  # Arrange
  local bytes=1572864

  # Act
  run disk_test_call disk_human "${bytes}"

  # Assert
  [[ "${output}" == "1.5 MiB" ]]
}

@test "a picked number maps to the listed disk at that position" {
  # Arrange
  local listed=$'/dev/disk4\n/dev/disk5'

  # Act
  run disk_test_call disk_pick_one 2 "${listed}" 2

  # Assert
  [[ "${output}" == "/dev/disk5" ]]
}

@test "a picked name maps to the listed disk" {
  # Arrange
  local listed=$'/dev/disk4\n/dev/disk5'

  # Act
  run disk_test_call disk_pick_one disk4 "${listed}" 2

  # Assert
  [[ "${output}" == "/dev/disk4" ]]
}

@test "a pick that names no listed disk is refused" {
  # Arrange
  local listed=$'/dev/disk4\n/dev/disk5'

  # Act
  run disk_test_call disk_pick_one disk9 "${listed}" 2

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: not a listed number or disk: disk9." ]]
}

@test "an error kept without a working directory is read back from memory" {
  # Arrange
  local call='disk_set_error "dd: boom"; disk_get_error'

  # Act
  run disk_test_call eval "${call}"

  # Assert
  [[ "${output}" == "dd: boom" ]]
}

@test "a working directory that cannot be made stops with a message" {
  # Arrange
  export TMPDIR="${BATS_TMPDIR:-/tmp}/nisemono-missing-${RANDOM}/deeper"

  # Act
  run disk_test_call disk_make_tmpdir nisemono

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: unable to create a working directory."* ]]
}

@test "an unknown system cannot release a disk" {
  # Arrange
  export NISEMONO_OS=FreeBSD

  # Act
  run disk_test_call disk_release /dev/da0

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "an unknown system treats every disk as internal" {
  # Arrange
  export NISEMONO_OS=FreeBSD

  # Act
  run disk_test_call disk_is_internal /dev/da0

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "an unknown system has no eject and says so" {
  # Arrange
  export NISEMONO_OS=FreeBSD

  # Act
  run disk_test_call disk_eject_now /dev/da0

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: warning: /dev/da0 did not eject. remove it once its light stops blinking." ]]
}

@test "the bytes dd moved come from its bytes line" {
  # Arrange
  local report="${BATS_TEST_TMPDIR:?}/dd.err"
  printf '2+0 records in\n2+0 records out\n1024 bytes transferred in 0.001 secs\n' >"${report}"

  # Act
  run disk_test_call disk_dd_bytes "${report}" 512

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "1024" ]]
}

@test "the bytes dd moved come from whole records when it prints no bytes line" {
  # Arrange
  local report="${BATS_TEST_TMPDIR:?}/dd.err"
  printf '3+0 records in\n3+0 records out\n' >"${report}"

  # Act
  run disk_test_call disk_dd_bytes "${report}" 65536

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "196608" ]]
}

@test "a partial record counts as nothing when dd prints no bytes line" {
  # Arrange
  local report="${BATS_TEST_TMPDIR:?}/dd.err"
  printf '1+1 records in\n1+1 records out\n' >"${report}"

  # Act
  run disk_test_call disk_dd_bytes "${report}" 512

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "512" ]]
}

@test "probe blocks sit on a power-of-two grid and include the last block" {
  # Arrange
  local size=$((64 * 512))

  # Act
  run disk_test_call disk_probe_blocks "${size}" 512 5

  # Assert
  [[ "${output}" == $'0\n8\n16\n24\n32\n40\n48\n56\n63' ]]
}

@test "probe blocks cover every block when samples exceed the blocks" {
  # Arrange
  local size=$((3 * 512))

  # Act
  run disk_test_call disk_probe_blocks "${size}" 512 10

  # Assert
  [[ "${output}" == $'0\n1\n2' ]]
}

@test "a disk whose every block reads its own tag passes" {
  # Arrange
  local reads=$'0 0\n8 8\n16 16\n'

  # Act
  run disk_test_call call_judge "${reads}" 512 12288

  # Assert
  [[ "${output}" == "3 0 0 12288 12288 -1 16 0 0" ]]
}

@test "blocks that alias a lower block mark the real size at the first of them" {
  # Arrange
  local reads=$'0 24\n8 8\n16 24\n24 24\n'

  # Act
  run disk_test_call call_judge "${reads}" 512 16384

  # Assert
  [[ "${output}" == "2 2 0 8192 4608 16 8 16 0" ]]
}

@test "blocks that read back without a tag are lost and mark the real size" {
  # Arrange
  local reads=$'0 0\n8 8\n16 -1\n24 -1\n'

  # Act
  run disk_test_call call_judge "${reads}" 512 16384

  # Assert
  [[ "${output}" == "2 0 2 8192 4608 16 8 0 0" ]]
}

@test "divisors of an alias gap are listed from the smallest that fits" {
  # Arrange
  local gap=24

  # Act
  run disk_test_call disk_refine_divisors "${gap}" 4

  # Assert
  [[ "${output}" == $'4\n6\n8\n12\n24' ]]
}

@test "an alias gap smaller than the smallest wrap names no wrap size" {
  # Arrange
  export DISK_GAP=4 DISK_BASE=0 DISK_SECTOR=512 DISK_SIZE=1048576

  # Act
  run disk_test_call disk_refine_module /dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "0" ]]
}

@test "the power-of-two aliases of a block are those below the known good block" {
  # Arrange
  local block=21

  # Act
  run disk_test_call disk_refine_aliases "${block}" 6 4

  # Assert
  [[ "${output}" == $'1\n5' ]]
}

@test "a tag with this run's code names its block" {
  # Arrange
  local block="${BATS_TEST_TMPDIR:?}/block"
  printf 'NISEMONO 0123456789abcdef 42\n' >"${block}"
  export DISK_NONCE=0123456789abcdef

  # Act
  run disk_test_call disk_probe_claim "${block}"

  # Assert
  [[ "${output}" == "42" ]]
}

@test "a tag left by another run names no block" {
  # Arrange
  local block="${BATS_TEST_TMPDIR:?}/block"
  printf 'NISEMONO fedcba9876543210 42\n' >"${block}"
  export DISK_NONCE=0123456789abcdef

  # Act
  run disk_test_call disk_probe_claim "${block}"

  # Assert
  [[ "${output}" == "-1" ]]
}
