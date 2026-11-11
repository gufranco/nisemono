#!/usr/bin/env bats
# shellcheck disable=SC2016

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-fill.XXXXXX")"
  SHIMS="${WORK}/shims"
  mkdir -p "${SHIMS}"
  export SHIMS
  disk_test_setup_env
  VOLUME="${WORK}/mnt"
  LOOP=""
}

teardown() {
  volume_unmount
  fake_counterfeit_release
  [[ -z "${LOOP}" ]] || sudo losetup -d "${LOOP}" 2>/dev/null || true
  rm -rf "${WORK}"
}

volume_mount() {
  local source="$1"
  mkdir -p "${VOLUME}"
  case "${NISEMONO_TEST_OS}" in
  Darwin) hdiutil attach -nobrowse -mountpoint "${VOLUME}" "${source}" >/dev/null ;;
  *)
    local user group
    user="$(id -u)"
    group="$(id -g)"
    sudo mount -o "uid=${user},gid=${group}" "${source}" "${VOLUME}"
    ;;
  esac
}

volume_unmount() {
  [[ -d "${VOLUME:-}" ]] || return 0
  case "${NISEMONO_TEST_OS}" in
  Darwin) hdiutil detach "${VOLUME}" >/dev/null 2>&1 || true ;;
  *) sudo umount "${VOLUME}" 2>/dev/null || true ;;
  esac
}

fat_volume() {
  local mebibytes="$1"
  case "${NISEMONO_TEST_OS}" in
  Darwin)
    hdiutil create -size "${mebibytes}m" -fs "MS-DOS FAT16" -volname FILLT -o "${WORK}/volume.dmg" >/dev/null
    volume_mount "${WORK}/volume.dmg"
    ;;
  *)
    disk_test_image "${WORK}/volume.img" "${mebibytes}"
    mkfs.fat -F 16 -n FILLT "${WORK}/volume.img" >/dev/null
    LOOP="$(sudo losetup -f --show "${WORK}/volume.img")"
    volume_mount "${LOOP}"
    ;;
  esac
}

fill() {
  disk_test_run nisemono fill "$@" "${VOLUME}"
}

@test "nisemono fill passes a volume whose every check file reads back" {
  # Arrange
  fat_volume 24

  # Act
  run fill

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"No fault found. All "*" MiB of check files on ${VOLUME} read back as written." ]]
}

@test "nisemono fill leaves every file already on the volume untouched" {
  # Arrange
  fat_volume 24
  printf 'keep me\n' >"${VOLUME}/notes.txt"
  head -c 65536 /dev/urandom >"${VOLUME}/photo.bin"
  local before
  before="$(cksum "${VOLUME}/notes.txt" "${VOLUME}/photo.bin")"

  # Act
  run fill

  # Assert
  local after
  after="$(cksum "${VOLUME}/notes.txt" "${VOLUME}/photo.bin")"
  find "${VOLUME}" -name '.nisemono-*' >"${WORK}/left"
  [[ "${status}" -eq 0 ]]
  [[ "${after}" == "${before}" ]]
  [[ ! -s "${WORK}/left" ]]
}

@test "nisemono fill reports its result as JSON" {
  # Arrange
  fat_volume 24

  # Act
  run fill --json

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ ^\{\"volume\":\"${VOLUME}\",\"checked_bytes\":[0-9]+,\"bad_bytes\":0,\"verdict\":\"pass\",\"first_bad_file\":null,\"first_bad_offset\":null\}$ ]]
}

@test "nisemono fill names the first bad check file on a fake volume" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "the fake card is a device-mapper table on Linux"
  disk_test_image "${WORK}/card.img" 64
  LOOP="$(sudo losetup -f --show "${WORK}/card.img")"
  local fake
  fake="$(fake_counterfeit "${LOOP}" 16777216 lost)"
  sudo mkfs.fat -F 16 -n FILLT "${fake}" >/dev/null
  volume_mount "${fake}"

  # Act
  run fill --json

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *'"verdict":"fake","first_bad_file":"check-0000.bin"'* ]]
}

@test "nisemono fill says where the fake data starts in words" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "the fake card is a device-mapper table on Linux"
  disk_test_image "${WORK}/card.img" 64
  LOOP="$(sudo losetup -f --show "${WORK}/card.img")"
  local fake
  fake="$(fake_counterfeit "${LOOP}" 16777216 lost)"
  sudo mkfs.fat -F 16 -n FILLT "${fake}" >/dev/null
  volume_mount "${fake}"

  # Act
  run fill

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Fake. ${VOLUME} handed back wrong data, first in check-0000.bin at byte "* ]]
}

@test "nisemono fill removes its check files when interrupted" {
  # Arrange
  fat_volume 24
  disk_test_shim sync 'kill -INT "$PPID"; trap - INT; kill -INT $$'

  # Act
  run fill

  # Assert
  find "${VOLUME}" -name '.nisemono-*' >"${WORK}/left"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: interrupted, and the check files are removed." ]]
  [[ ! -s "${WORK}/left" ]]
}

@test "nisemono fill warns when the volume takes less than it said it would" {
  # Arrange
  fat_volume 24
  disk_test_shim df "printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\nfake 40960 0 40960 0%% /\\n'"

  # Act
  run fill

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"nisemono: warning: the volume took "*" of 38 MiB before it refused more."* ]]
}

@test "nisemono fill says when not one check file could be written" {
  # Arrange
  fat_volume 24
  head -c $((23 * 1048576)) /dev/zero >"${VOLUME}/full.bin" 2>/dev/null || true
  disk_test_shim df "printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\nfake 40960 0 40960 0%% /\\n'"

  # Act
  run fill

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: unable to write a single check file to ${VOLUME}." ]]
}

@test "nisemono fill stops on a volume with no free space" {
  # Arrange
  mkdir -p "${VOLUME}"
  disk_test_shim df "printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\nfake 40960 40960 1024 100%% /\\n'"

  # Act
  run fill

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: stopped: ${VOLUME} has no free space to check." ]]
}

@test "nisemono fill says when it cannot write to the volume" {
  # Arrange
  local user
  user="$(id -u)"
  [[ "${user}" != 0 ]] || skip "root writes into a read-only folder"
  mkdir -p "${VOLUME}"
  chmod 555 "${VOLUME}"

  # Act
  run fill

  # Assert
  chmod 755 "${VOLUME}"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: unable to write to ${VOLUME}." ]]
}

@test "nisemono fill needs a mounted volume" {
  # Arrange
  local missing="${WORK}/nowhere"

  # Act
  run disk_test_run nisemono fill "${missing}"

  # Assert
  local bare
  bare="$(disk_test_run nisemono fill 2>&1 || true)"
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: not a mounted volume: ${missing}" ]]
  [[ "${bare}" == "nisemono: fill needs a mounted volume. run 'nisemono help' for usage." ]]
}

@test "nisemono fill stops when the volume cannot be remounted to read past the cache" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Darwin" ]] || skip "macOS reads past the cache by remounting"
  fat_volume 24
  disk_test_shim diskutil 'case "$1" in unmount) exit 1 ;; esac; exec "$REAL" "$@"'

  # Act
  run fill

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: unable to remount ${VOLUME} to read past the cache, so nothing was proven. remove its .nisemono-"*" folder once it mounts again." ]]
}

@test "nisemono fill reads past the cache directly where the volume allows it" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "macOS remounts the volume instead"
  fat_volume 24
  disk_test_shim dd 'for word do shift; [ "${word}" = iflag=direct ] || set -- "$@" "${word}"; done; exec "$REAL" "$@"'

  # Act
  run fill

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"No fault found."* ]]
}

@test "nisemono fill says when it cannot read random bytes" {
  # Arrange
  fat_volume 24
  disk_test_shim head 'case "$*" in *urandom*) exit 1 ;; esac; exec "$REAL" "$@"'

  # Act
  run fill

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: unable to read random bytes for the check files." ]]
}

@test "nisemono fill drops the page cache where direct reads are refused" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "Linux reads past the cache directly"
  fat_volume 24
  disk_test_shim dd 'case " $* " in *" iflag=direct "*) exit 1 ;; esac; exec "$REAL" "$@"'

  # Act
  run fill

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"No fault found."* ]]
}
