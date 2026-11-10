#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-io.XXXXXX")"
  export NISEMONO_SAMPLES=4
  if [[ "${NISEMONO_TEST_OS}" == "Linux" ]]; then
    export NISEMONO_ALLOW_INTERNAL=y
  fi
  SHIMS="${WORK}/shims"
  export SHIMS
  disk_test_fill "${WORK}/target.img" 2 '\252'
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
  NAME="${DEVICE##*/}"
  fake_install
}

teardown() {
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

probing() {
  printf '%s\n' "${NAME}" | disk_test_run nisemono probe "${DEVICE}"
}

picking() {
  printf '%b' "$1" | NISEMONO_INTERACTIVE=1 disk_test_run nisemono
}

write_dd() {
  disk_test_shim dd "case \"\$*\" in *of=*${NAME}*) $1 ;; esac
exec \"\$REAL\" \"\$@\""
}

read_dd() {
  disk_test_shim dd "case \"\$*\" in *if=*${NAME}*of=*/back*) $1 ;; esac
exec \"\$REAL\" \"\$@\""
}

@test "nisemono warns when the drive will not eject after a fault" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Darwin" ]] || skip "a loop device on Linux is ejected through a stand-in"
  fake_flag eject-fails
  write_dd "printf 'dd: error writing: Input/output error\\n' >&2; exit 1"

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: stopped: a test block could not be written to ${DEVICE}."* ]]
  [[ "${output}" == *"dd said: dd: error writing: Input/output error"* ]]
  [[ "${output}" == *"${DEVICE} did not eject. remove it once its light stops blinking."* ]]
}

@test "nisemono says when the drive is gone after a fault" {
  # Arrange
  local gone
  gone="$(fake_dir)/gone"
  write_dd ": >'${gone}'; printf 'dd: /dev/${NAME}: Device not configured\\n' >&2; exit 1"

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"${DEVICE} is no longer attached. a card that drops off mid-test often fails the same way in a camera."* ]]
}

@test "nisemono stops at once when a transfer is interrupted" {
  # Arrange
  write_dd "exit 130"

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"dd said: the write of block 0 was interrupted"* ]]
}

@test "nisemono stops a transfer that runs past its deadline" {
  # Arrange
  write_dd "exit 124"

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"dd said: the drive did not finish a write of block 0 within 30s"* ]]
}

@test "nisemono does not trust a transfer that moved fewer bytes" {
  # Arrange
  write_dd "\"\$REAL\" \"\$@\" 2>/dev/null; printf '0+0 records in\\n0+0 records out\\n0 bytes transferred\\n' >&2; exit 0"

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"dd said: dd moved 0 of 512 bytes at block 0"* ]]
}

@test "nisemono does not trust a dd whose only record count came up short" {
  # Arrange
  write_dd "\"\$REAL\" \"\$@\" 2>/dev/null; printf '0+1 records in\\n0+1 records out\\n' >&2; exit 0"

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"dd said: dd moved 0 of 512 bytes at block 0"* ]]
}

@test "nisemono probes through a dd that reports only record counts" {
  # Arrange
  disk_test_shim dd "err=\"\$(mktemp)\"
\"\$REAL\" \"\$@\" 2>\"\$err\"
status=\$?
grep -v bytes \"\$err\" >&2
rm -f \"\$err\"
exit \"\$status\""

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"No fault found. Every test block across the 2.0 MiB of ${DEVICE} came back as written."* ]]
}

@test "nisemono stops when a test block cannot be read back" {
  # Arrange
  read_dd "printf 'dd: error reading: Input/output error\\n' >&2; exit 1"

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: stopped: a test block could not be read back from ${DEVICE}."* ]]
}

@test "nisemono stops when no random bytes can be read for the tag" {
  # Arrange
  disk_test_shim od "case \"\$*\" in *urandom*) exit 1 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: unable to read random bytes for the probe tag."* ]]
}

@test "nisemono bypasses the page cache when direct I/O works" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "macOS reads the raw device, which never caches"
  local expected="Bypassing the page cache so every block reaches the media."
  disk_test_shim dd "for word in \"\$@\"; do
  shift
  case \"\$word\" in iflag=direct | oflag=direct) ;; *) set -- \"\$@\" \"\$word\" ;; esac
done
exec \"\$REAL\" \"\$@\""

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"${expected}"* ]]
}

@test "nisemono drops buffers before reading back when direct I/O fails" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "macOS reads the raw device, which never caches"
  disk_test_shim dd "case \"\$*\" in *flag=direct*) exit 1 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Direct I/O is unavailable, so buffers are dropped before reading back."* ]]
}

@test "nisemono asks for the disk by name without gum and stops on a wrong typed name" {
  # Arrange
  local answers="${NAME}\nn\n"

  # Act
  run picking "${answers}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Probe which disk? Number or name: "* ]]
  [[ "${output}" == *"Device: ${DEVICE}"* ]]
  [[ "${output}" == *"cancelled, nothing was touched."* ]]
}

@test "nisemono wants exactly one disk from the picker" {
  # Arrange
  local answers="${NAME},${NAME}\n"

  # Act
  run picking "${answers}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: pick exactly one disk."* ]]
}

@test "nisemono lists only removable disks in the picker" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "macOS reads the internal flag from diskutil"
  unset NISEMONO_ALLOW_INTERNAL
  disk_test_shim lsblk "case \"\$*\" in *RM,HOTPLUG,TRAN*${NAME}*) printf '1 0 usb\\n'; exit 0 ;; *RM,HOTPLUG,TRAN*) printf '0 0 sata\\n'; exit 0 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run picking "${NAME}\nn\n"

  # Assert
  [[ "${output}" == *"${DEVICE}"* ]]
}

@test "nisemono says when no removable disk is attached" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "an attached disk image is always removable on macOS"
  unset NISEMONO_ALLOW_INTERNAL

  # Act
  run picking "\n"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"nisemono: no external or removable disk is attached."* ]]
}

@test "nisemono ejects the disk after a fault on Linux" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || skip "a disk image on macOS ejects through diskutil"
  disk_test_shim eject "exit 0"
  write_dd "printf 'dd: error writing: Input/output error\\n' >&2; exit 1"

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Ejected. ${DEVICE} is safe to remove."* ]]
}

@test "nisemono ejects a disk after a fault on macOS" {
  # Arrange
  [[ "${NISEMONO_TEST_OS}" == "Darwin" ]] || skip "Linux ejects through a stand-in"
  disk_test_shim diskutil "case \"\$1\" in eject) exit 0 ;; esac
exec \"\$REAL\" \"\$@\""
  write_dd "printf 'dd: error writing: Input/output error\\n' >&2; exit 1"

  # Act
  run probing

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Ejected. ${DEVICE} is safe to remove."* ]]
}
