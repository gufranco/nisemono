#!/usr/bin/env bats
# shellcheck disable=SC2016

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-fix.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  disk_test_setup_env
  disk_test_image "${WORK}/card.img" 64
  DEVICE="$(disk_test_attach "${WORK}/card.img")"
  PART_LOOP=""
}

teardown() {
  [[ -z "${PART_LOOP}" ]] || sudo losetup -d "${PART_LOOP}" 2>/dev/null || true
  fake_counterfeit_release
  disk_test_detach "${DEVICE}"
  [[ -z "${BIG:-}" ]] || disk_test_detach "${BIG}"
  rm -rf "${WORK}"
}

fix() {
  local target="$1"
  shift
  printf '%s\n' "${CONFIRM:-${target##*/}}" | NISEMONO_INTERACTIVE=1 disk_test_run nisemono fix --samples 32 "$@" "${target}"
}

counterfeit() {
  fake_install
  fake_counterfeit "${DEVICE}" "$1" wrap
}

partition_entry() {
  local dump
  local -a bytes
  dump="$(od -An -tu1 -v -j 446 -N 16 "${WORK}/card.img")"
  read -r -a bytes <<<"${dump}"
  printf '%s\n' "${bytes[*]}"
}

@test "nisemono fix gives a fake card one partition inside its real size" {
  # Arrange
  local target
  target="$(counterfeit 16777216)"

  # Act
  run fix "${target}"

  # Assert
  local entry label
  entry="$(partition_entry)"
  label="$(mlabel -i "${WORK}/card.img@@1M" -s :: 2>/dev/null)"
  [[ "${status}" -eq 0 ]]
  [[ "${entry}" == "0 254 255 255 14 254 255 255 0 8 0 0 0 120 0 0" ]]
  [[ "${label}" == *"NISEMONO"* ]]
  [[ "${output}" == *"Fixed. ${target} now holds one FAT16 partition named NISEMONO within the 16.0 MiB it really holds. Eject it and plug it back in to use it." ]]
}

@test "nisemono fix gives a fake card past 2 GiB a FAT32 partition" {
  # Arrange
  local target
  local -a entry
  dd if=/dev/zero of="${WORK}/big.img" bs=1048576 count=0 seek=3072 2>/dev/null
  BIG="$(disk_test_attach "${WORK}/big.img")"
  fake_install
  target="$(fake_counterfeit "${BIG}" 2684354560 wrap)"

  # Act
  run fix "${target}"

  # Assert
  local dump
  dump="$(od -An -tu1 -v -j 446 -N 16 "${WORK}/big.img")"
  read -r -a entry <<<"${dump}"
  [[ "${status}" -eq 0 ]]
  [[ "${entry[4]}" == "12" ]]
  [[ "${output}" == *"now holds one FAT32 partition named NISEMONO"* ]]
}

@test "nisemono fix leaves a partition that a later probe passes" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "the partition is reached through a loop device on Linux"
  local target
  target="$(counterfeit 16777216)"
  fix "${target}" >/dev/null 2>&1
  PART_LOOP="$(sudo losetup -f --show -o 1048576 --sizelimit 15728640 "${target}")"

  # Act
  run probe_partition "${PART_LOOP}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"No fault found."* ]]
}

probe_partition() {
  printf '%s\n' "${1##*/}" | NISEMONO_INTERACTIVE=1 disk_test_run nisemono probe --samples 32 "$1"
}

@test "nisemono fix reports its partition as JSON" {
  # Arrange
  local target
  target="$(counterfeit 16777216)"

  # Act
  run fix "${target}" --json

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[${#lines[@]} - 1]}" == *"{\"device\":\"${target}\",\"real_bytes\":16777216,\"partition_bytes\":15728640,\"filesystem\":\"FAT16\"}" ]]
}

@test "nisemono fix stops on a card that passes the probe" {
  # Arrange
  local target="${DEVICE}"

  # Act
  run fix "${target}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: stopped: ${target} is genuine, so there is nothing to fix." ]]
}

@test "nisemono fix stops on a card too small for a partition" {
  # Arrange
  local target
  target="$(counterfeit 2097152)"

  # Act
  run fix "${target}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: stopped: ${target} really holds only 2.0 MiB, too little for a partition." ]]
}

@test "nisemono fix touches nothing without the disk name" {
  # Arrange
  local target
  target="$(counterfeit 16777216)"

  # Act
  CONFIRM=wrong run fix "${target}"

  # Assert
  local entry
  entry="$(partition_entry)"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"cancelled, nothing was touched."* ]]
  [[ "${entry}" == "0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0" ]]
}

@test "nisemono fix says when the partition cannot be built" {
  # Arrange
  local target
  target="$(counterfeit 16777216)"
  disk_test_shim mformat 'exit 1'

  # Act
  run fix "${target}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: unable to build the new partition for ${target}." ]]
}

@test "nisemono fix says when the partition cannot be written" {
  # Arrange
  local target
  target="$(counterfeit 16777216)"
  [[ ! -f "${SHIMS}/dd" ]] || mv -f "${SHIMS}/dd" "${SHIMS}/dd.fake"
  disk_test_shim dd 'for word; do case "$word" in if=*/fix.img) printf "dd: error writing: Input/output error\n" >&2; exit 1 ;; esac; done
[ ! -f "${SHIMS}/dd.fake" ] || exec sh "${SHIMS}/dd.fake" "$@"
exec "$REAL" "$@"'

  # Act
  run fix "${target}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: the new partition could not be written to ${target}: dd: error writing: Input/output error" ]]
}

@test "nisemono fix needs mtools" {
  # Arrange
  local farm
  farm="$(disk_test_farm mformat)"

  # Act
  run disk_test_run_path "${farm}" nisemono fix "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: fix needs mformat from mtools. install mtools and try again." ]]
}

@test "nisemono fix needs a disk" {
  # Arrange
  local command=fix

  # Act
  run disk_test_run nisemono "${command}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: fix needs a disk. run 'nisemono help' for usage." ]]
}
