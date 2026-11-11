#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-system.XXXXXX")"
  export NISEMONO_SAMPLES=4
  if [[ "${NISEMONO_TEST_OS}" == "Linux" ]]; then
    export NISEMONO_ALLOW_INTERNAL=y
  fi
  SHIMS="${WORK}/shims"
  export SHIMS
  DEVICE=""
  MOUNTED=""
}

teardown() {
  disk_test_partition_nodes_stop
  if [[ -n "${MOUNTED}" ]]; then
    case "${NISEMONO_TEST_OS}" in
    Darwin) hdiutil detach -force "${MOUNTED}" >/dev/null 2>&1 || true ;;
    *) sudo umount "${MOUNTED}" >/dev/null 2>&1 || true ;;
    esac
  fi
  [[ -z "${DEVICE}" ]] || disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

attach_blank() {
  disk_test_fill "${WORK}/target.img" 2 '\252'
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
}

probing() {
  printf '%s\n' "${DEVICE##*/}" | disk_test_run nisemono probe "${DEVICE}"
}

declining() {
  printf 'n\n' | disk_test_run nisemono probe "$1"
}

on_terminal() {
  case "${NISEMONO_TEST_OS}" in
  Darwin) script -q /dev/null "$@" </dev/null ;;
  *) script -qec "$(printf '%q ' "$@")" /dev/null </dev/null ;;
  esac
}

@test "a bounded command past its limit is stopped without timeout" {
  # Arrange
  local farm
  farm="$(disk_test_farm timeout gtimeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded 1 sleep 5

  # Assert
  [[ "${status}" -eq 124 ]]
}

@test "a bounded command within its limit keeps its status without timeout" {
  # Arrange
  local farm
  farm="$(disk_test_farm timeout gtimeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded 3 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a bounded command without timeout is checked within milliseconds, not once a second" {
  # Arrange
  local farm first second
  farm="$(disk_test_farm timeout gtimeout)"
  disk_test_shim sleep "printf '%s\\n' \"\$1\" >>'${WORK}/sleeps'
exec \"\$REAL\" \"\$@\""

  # Act
  run disk_test_call_path "${SHIMS}:${farm}" disk_bounded 3 perl -e 'select(undef, undef, undef, 1)'

  # Assert
  [[ "${status}" -eq 0 ]]
  {
    read -r first
    read -r second
  } <"${WORK}/sleeps"
  [[ "${first}" == "0.010" ]]
  [[ "${second}" == "0.020" ]]
}

@test "a bounded command uses gtimeout when timeout is missing" {
  # Arrange
  disk_test_shim gtimeout "while [ \"\$#\" -gt 0 ]; do
  case \"\$1\" in
    -k) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
shift
exec \"\$@\""
  local farm
  farm="$(disk_test_farm timeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded 3 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a millisecond bound uses gtimeout when timeout is missing" {
  # Arrange
  disk_test_shim gtimeout "while [ \"\$#\" -gt 0 ]; do
  case \"\$1\" in
    -k) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
shift
exec \"\$@\""
  local farm
  farm="$(disk_test_farm timeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded_ms 1500 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a millisecond bound falls back to whole seconds without timeout" {
  # Arrange
  local farm
  farm="$(disk_test_farm timeout gtimeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded_ms 1500 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "the clock still reads without perl" {
  # Arrange
  disk_test_shim perl "exit 1"

  # Act
  run disk_test_call disk_now_ms

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ ^[0-9]+$ ]]
}

@test "the clock falls back to whole seconds when date has no nanoseconds" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Darwin" ]] || skip "Linux reads /proc/uptime before date"
  disk_test_shim perl "exit 1"
  disk_test_shim date "case \"\$1\" in +%s%N) printf '%sN\\n' \"\$(\"\$REAL\" +%s)\"; exit 0 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run disk_test_call disk_now_ms

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ ^[0-9]+000$ ]]
}

@test "nisemono stops when administrator access is refused" {
  # Arrange
  attach_blank
  disk_test_shim sudo "case \"\$1\" in
  -n) [ \"\${2:-}\" = true ] && exit 1 ;;
  -v) exit 1 ;;
esac
exec \"\$REAL\" \"\$@\""

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Administrator access is required to reach the raw device."* ]]
  [[ "${output}" == *"nisemono: administrator access was not granted."* ]]
}

@test "nisemono continues once administrator access is granted" {
  # Arrange
  attach_blank
  disk_test_shim sudo "case \"\$1\" in
  -n) [ \"\${2:-}\" = true ] && exit 1 ;;
  -v) exit 0 ;;
esac
exec \"\$REAL\" \"\$@\""

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Administrator access is required to reach the raw device."* ]]
}

@test "nisemono resolves a mount point to its whole disk" {
  # Arrange
  disk_test_fat_image "${WORK}/fat.img" 8 NISETEST
  case "${NISEMONO_TEST_OS}" in
  Darwin)
    local listing
    listing="$(hdiutil attach "${WORK}/fat.img")"
    DEVICE="${listing%%[[:space:]]*}"
    MOUNTED="${DEVICE}"
    MOUNT_POINT="$(printf '%s\n' "${listing}" | awk -F'\t' '/\/Volumes\// { print $NF; exit }')"
    ;;
  *)
    DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
    disk_test_partition_nodes_start
    MOUNT_POINT="${WORK}/mnt"
    mkdir -p "${MOUNT_POINT}"
    disk_test_wait_partition "${DEVICE}p1"
    sudo mount "${DEVICE}p1" "${MOUNT_POINT}"
    MOUNTED="${MOUNT_POINT}"
    ;;
  esac

  # Act
  run declining "${MOUNT_POINT}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Device: ${DEVICE}"* ]]
}

@test "nisemono unmounts each volume when the whole disk will not unmount on macOS" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Darwin" ]] || skip "Linux unmounts each partition already"
  disk_test_fat_image "${WORK}/fat.img" 8 NISESLICE
  local listing
  listing="$(hdiutil attach "${WORK}/fat.img")"
  DEVICE="${listing%%[[:space:]]*}"
  MOUNTED="${DEVICE}"
  fake_install
  fake_flag unmount-fails

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"No fault found. Every test block across the 8.0 MiB of ${DEVICE} came back as written."* ]]
}

@test "nisemono unmounts a mounted partition before it probes on Linux" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "macOS unmounts the whole disk through diskutil"
  disk_test_fat_image "${WORK}/fat.img" 8 NISEPART
  DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
  disk_test_partition_nodes_start
  mkdir -p "${WORK}/mnt"
  disk_test_wait_partition "${DEVICE}p1"
  sudo mount "${DEVICE}p1" "${WORK}/mnt"
  MOUNTED="${WORK}/mnt"

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"No fault found. Every test block across the 8.0 MiB of ${DEVICE} came back as written."* ]]
}

@test "nisemono unmounts a filesystem on the whole disk before it probes on Linux" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "macOS unmounts the whole disk through diskutil"
  disk_test_image "${WORK}/whole.img" 8
  mkfs.fat -F 16 -s 1 -n NISEWHOLE "${WORK}/whole.img" >/dev/null
  DEVICE="$(disk_test_attach "${WORK}/whole.img")"
  mkdir -p "${WORK}/mnt"
  sudo mount "${DEVICE}" "${WORK}/mnt"
  MOUNTED="${WORK}/mnt"

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"No fault found. Every test block across the 8.0 MiB of ${DEVICE} came back as written."* ]]
}

@test "nisemono refuses a folder that is not a mount point" {
  # Arrange
  local folder="${WORK}/folder"
  mkdir -p "${folder}"

  # Act
  run disk_test_run nisemono probe "${folder}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "nisemono: no device found for mount point: ${folder}" ]]
}

@test "nisemono resolves a partition to its whole disk" {
  # Arrange
  disk_test_fat_image "${WORK}/fat.img" 8 NISEPART
  DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
  disk_test_partition_nodes_start
  local partition
  case "${NISEMONO_TEST_OS}" in
  Darwin) partition="${DEVICE}s1" ;;
  *) partition="${DEVICE}p1" ;;
  esac
  disk_test_wait_partition "${partition}"

  # Act
  run declining "${partition}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Device: ${DEVICE}"* ]]
}

@test "the partition node helper leaves a devtmpfs /dev to the kernel" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "only Linux tests make partition nodes by hand"
  local shims="${WORK}/devtmpfs-shims"
  mkdir -p "${shims}"
  printf '#!/bin/sh\necho devtmpfs\n' >"${shims}/findmnt"
  chmod +x "${shims}/findmnt"
  PATH="${shims}:${PATH}"

  # Act
  disk_test_partition_nodes_start

  # Assert
  [[ -z "${PARTITION_NODES_PID:-}" ]]
}

@test "a partition node left with an old device number is not ready" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "only Linux tests make partition nodes by hand"
  disk_test_fat_image "${WORK}/fat.img" 8 NISESTALE
  DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
  local stale="${WORK}/${DEVICE##*/}p1"
  sudo mknod -m 660 "${stale}" b 7 1048000

  # Act
  run disk_test_partition_ready "${stale}"

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "nisemono refuses a mounted filesystem that is not a block device" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "macOS reports a device node for every mounted volume"

  # Act
  run disk_test_run nisemono probe /dev/shm </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: device not found or invalid: "* ]]
}

@test "doctor marks a missing required tool" {
  # Arrange
  local farm
  farm="$(disk_test_farm dd)"

  # Act
  run disk_test_run_path "${farm}" nisemono doctor

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" =~ (^|$'\n')dd\ +missing\ +required ]]
}

@test "doctor warns about a missing fix tool without failing" {
  # Arrange
  local farm
  farm="$(disk_test_farm mformat)"

  # Act
  run disk_test_run_path "${farm}" nisemono doctor

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ (^|$'\n')mformat\ +warn\ +mtools\ package ]]
}

@test "nisemono runs when called by name from PATH" {
  # Arrange
  local bin="${REPO_DIR}/bin"
  local -a shell_words
  local version
  read -r -a shell_words <<<"${NISEMONO_TEST_SHELL:-sh}"
  version="$(sed -n 's/^NISEMONO_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"

  # Act
  run bash -c 'cd "$1" && shift && PATH="$PWD:$PATH" "$@" nisemono version' _ "${bin}" "${shell_words[@]}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "nisemono ${version}" ]]
}

@test "nisemono goes on when the drive gives no write-protect answer" {
  # Arrange
  attach_blank
  fake_install
  printf '<string>unknown</string>\n' >"$(fake_dir)/plist/WritableMedia"
  disk_test_shim blockdev "case \"\$*\" in *--getro*) printf 'unknown\\n'; exit 0 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" != *"write protected"* ]]
}

@test "the sector size falls back to 512 bytes when the drive does not say" {
  # Arrange
  attach_blank
  fake_install
  printf '/Device Block Size:/d\n' >"$(fake_dir)/info.sed"
  disk_test_shim blockdev "case \"\$*\" in *--getss*) exit 1 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run disk_test_call disk_sector_bytes "${DEVICE}"

  # Assert
  [[ "${output}" == "512" ]]
}

@test "progress redraws one line on a terminal" {
  # Arrange
  local -a shell_words
  read -r -a shell_words <<<"${NISEMONO_TEST_SHELL:-sh}"
  local farm
  farm="$(disk_test_farm gum)"

  # Act
  run on_terminal env PATH="${farm}" "${shell_words[@]}" "${NISEMONO_TESTS_DIR}/call.sh" disk_progress Writing 1048576 1048576 0

  # Assert
  [[ "${output}" == *"Writing 100%"* ]]
}
