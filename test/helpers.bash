#!/usr/bin/env bash

NISEMONO_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${NISEMONO_TESTS_DIR}/.." && pwd)"
NISEMONO_TEST_OS="$(uname -s)"
export NISEMONO_TESTS_DIR REPO_DIR NISEMONO_TEST_OS
PATH="${NISEMONO_TESTS_DIR}/bin:${PATH}"
export PATH

disk_test_path() {
  local base="${PATH}"
  if [[ "${NISEMONO_TEST_OS}" == "Darwin" ]]; then
    base="${NISEMONO_TESTS_DIR}/shim:${PATH}"
  fi
  if [[ -n "${SHIMS:-}" && -d "${SHIMS}" ]]; then
    printf '%s:%s\n' "${SHIMS}" "${base}"
  else
    printf '%s\n' "${base}"
  fi
}

disk_test_shim() {
  local name="$1"
  local body="$2"
  local real
  SHIMS="${SHIMS:-${WORK:?}/shims}"
  mkdir -p "${SHIMS}"
  real="$(PATH="$(disk_test_path_without_shims)" command -v "${name}" || true)"
  printf '#!/bin/sh\n{ set +x; } 2>/dev/null\nREAL=%q\n%s\n' "${real}" "${body}" >"${SHIMS}/${name}"
  chmod +x "${SHIMS}/${name}"
  if [[ "${NISEMONO_TEST_OS}" == "Linux" && ! -e "${SHIMS}/sudo" ]]; then
    disk_test_sudo_passthrough
  fi
  export SHIMS
}

disk_test_path_without_shims() {
  if [[ "${NISEMONO_TEST_OS}" == "Darwin" ]]; then
    printf '%s:%s\n' "${NISEMONO_TESTS_DIR}/shim" "${PATH}"
  else
    printf '%s\n' "${PATH}"
  fi
}

disk_test_sudo_passthrough() {
  local real
  real="$(command -v sudo)"
  # shellcheck disable=SC2016
  printf '#!/bin/sh\n{ set +x; } 2>/dev/null\ncase "${1:-}" in\n  -*) exec %q "$@" ;;\nesac\nexec %q env "PATH=$PATH" "$@"\n' "${real}" "${real}" >"${SHIMS}/sudo"
  chmod +x "${SHIMS}/sudo"
}

disk_test_run() {
  disk_test_run_env "" "$@"
}

disk_test_run_env() {
  local settings="$1"
  local program="$2"
  local search_path
  local -a shell_words env_words
  shift 2
  search_path="$(disk_test_path)"
  read -r -a shell_words <<<"${NISEMONO_TEST_SHELL:-sh}"
  read -r -a env_words <<<"${settings}"
  PATH="${search_path}" env "${env_words[@]}" "${shell_words[@]}" "${REPO_DIR}/bin/${program}" "$@"
}

disk_test_call() {
  local search_path
  local -a shell_words
  search_path="$(disk_test_path)"
  read -r -a shell_words <<<"${NISEMONO_TEST_SHELL:-sh}"
  PATH="${search_path}" "${shell_words[@]}" "${NISEMONO_TESTS_DIR}/call.sh" "$@"
}

disk_test_farm_wanted() {
  local farm="$1"
  local tool="$2"
  local name="${2##*/}"
  local excluded
  shift 2
  [[ -x "${tool}" && ! -e "${farm}/${name}" ]] || return 1
  for excluded in "$@"; do
    [[ "${name}" == "${excluded}" ]] && return 1
  done
  return 0
}

disk_test_farm() {
  local farm="${WORK:?}/farm"
  local dir tool search_path
  local -a dirs batch
  mkdir -p "${farm}"
  search_path="$(disk_test_path)"
  IFS=: read -r -a dirs <<<"${search_path}"
  for dir in "${dirs[@]}"; do
    batch=()
    for tool in "${dir}"/*; do
      disk_test_farm_wanted "${farm}" "${tool}" "$@" && batch+=("${tool}")
    done
    [[ ${#batch[@]} -eq 0 ]] || ln -s "${batch[@]}" "${farm}/"
  done
  printf '%s\n' "${farm}"
}

disk_test_call_path() {
  local search_path="$1"
  local -a shell_words
  shift
  read -r -a shell_words <<<"${NISEMONO_TEST_SHELL:-sh}"
  PATH="${search_path}" "${shell_words[@]}" "${NISEMONO_TESTS_DIR}/call.sh" "$@"
}

disk_test_run_path() {
  local search_path="$1"
  local program="$2"
  local -a shell_words
  shift 2
  read -r -a shell_words <<<"${NISEMONO_TEST_SHELL:-sh}"
  PATH="${search_path}" "${shell_words[@]}" "${REPO_DIR}/bin/${program}" "$@"
}

disk_test_attach() {
  local image="$1"
  local listing

  case "${NISEMONO_TEST_OS}" in
  Darwin)
    listing="$(hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage "${image}")" || return 1
    printf '%s\n' "${listing%%[[:space:]]*}"
    ;;
  Linux)
    sudo losetup -f --show "${image}"
    ;;
  *)
    printf 'unsupported OS: %s\n' "${NISEMONO_TEST_OS}" >&2
    return 1
    ;;
  esac
}

disk_test_attach_partitioned() {
  local image="$1"
  local device tries=0
  case "${NISEMONO_TEST_OS}" in
  Linux)
    device="$(sudo losetup -f -P --show "${image}")" || return 1
    if [[ -S /run/udev/control ]]; then
      sudo udevadm settle >/dev/null 2>&1 || true
    fi
    until compgen -G "/sys/block/${device##*/}/${device##*/}p*" >/dev/null || [[ "${tries}" -ge 20 ]]; do
      sleep 0.1
      tries=$((tries + 1))
    done
    if ! compgen -G "/sys/block/${device##*/}/${device##*/}p*" >/dev/null; then
      sudo partx -a "${device}" >/dev/null 2>&1 || true
    fi
    printf '%s\n' "${device}"
    ;;
  *) disk_test_attach "${image}" ;;
  esac
}

disk_test_dev_is_devtmpfs() {
  local fs_type
  fs_type="$(findmnt -n -o FSTYPE /dev 2>/dev/null)" || return 1
  [[ "${fs_type}" == "devtmpfs" ]]
}

disk_test_partition_nodes_start() {
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || return 0
  disk_test_dev_is_devtmpfs && return 0
  (
    tries=0
    while [[ "${tries}" -lt 600 ]]; do
      for part in /sys/block/loop*/loop*p*; do
        [[ -e "${part}/dev" ]] || continue
        node="/dev/${part##*/}"
        IFS=: read -r major minor <"${part}/dev"
        current="$(stat -c '%t:%T' "${node}" 2>/dev/null || true)"
        wanted="$(printf '%x:%x' "${major}" "${minor}")"
        [[ "${current}" == "${wanted}" ]] && continue
        sudo rm -f "${node}.new"
        if sudo mknod -m 660 "${node}.new" b "${major}" "${minor}" 2>/dev/null; then
          sudo mv -f "${node}.new" "${node}" || true
        fi
      done
      sleep 0.2
      tries=$((tries + 1))
    done
  ) &
  PARTITION_NODES_PID="$!"
}

disk_test_wait_partition() {
  local node="$1"
  local tries=0
  while [[ "${tries}" -lt 200 ]]; do
    if [[ -S /run/udev/control ]]; then
      sudo udevadm settle >/dev/null 2>&1 || true
    fi
    disk_test_partition_ready "${node}" && return 0
    sleep 0.1
    tries=$((tries + 1))
  done
  return 1
}

disk_test_partition_ready() {
  local node="$1"
  local sysfs="/sys/class/block/${node##*/}/dev"
  local major minor current wanted
  [[ -b "${node}" ]] || return 1
  [[ "${NISEMONO_TEST_OS}" == "Linux" ]] || return 0
  [[ -r "${sysfs}" ]] || return 1
  IFS=: read -r major minor <"${sysfs}"
  current="$(stat -c '%t:%T' "${node}" 2>/dev/null)" || return 1
  wanted="$(printf '%x:%x' "${major}" "${minor}")"
  [[ "${current}" == "${wanted}" ]]
}

disk_test_partition_nodes_stop() {
  [[ -n "${PARTITION_NODES_PID:-}" ]] || return 0
  kill "${PARTITION_NODES_PID}" 2>/dev/null || true
  wait "${PARTITION_NODES_PID}" 2>/dev/null || true
  PARTITION_NODES_PID=""
}

disk_test_detach() {
  local device="$1"

  case "${NISEMONO_TEST_OS}" in
  Darwin) hdiutil detach "${device}" >/dev/null 2>&1 || true ;;
  Linux)
    sudo losetup -d "${device}" >/dev/null 2>&1 || true
    if [[ ! -S /run/udev/control && "${device}" == /dev/loop* ]]; then
      sudo rm -f "${device}"p[0-9]*
    fi
    ;;
  *) return 1 ;;
  esac
}

disk_test_image() {
  local file="$1"
  local mebibytes="$2"

  dd if=/dev/zero of="${file}" bs=1048576 count="${mebibytes}" 2>/dev/null
}

disk_test_fat_image() {
  local file="$1"
  local mebibytes="$2"
  local label="$3"
  local base="${file%.*}"

  case "${NISEMONO_TEST_OS}" in
  Darwin)
    hdiutil create -size "${mebibytes}m" -layout MBRSPUD -fs "MS-DOS FAT16" -volname "${label}" -o "${base}.dmg" >/dev/null || return 1
    hdiutil convert "${base}.dmg" -format UDTO -o "${base}" >/dev/null || return 1
    mv -f "${base}.cdr" "${file}"
    rm -f "${base}.dmg"
    ;;
  Linux)
    disk_test_image "${file}" "${mebibytes}"
    printf 'start=2048, type=6\n' | sfdisk -q "${file}" >/dev/null || return 1
    mkfs.fat -F 16 -s 1 --offset 2048 -n "${label}" "${file}" $(((mebibytes - 1) * 1024)) >/dev/null || return 1
    ;;
  *) return 1 ;;
  esac
}

disk_test_random_bytes() {
  local count="$1"
  local key

  DISK_TEST_RANDOM_CALLS=$((${DISK_TEST_RANDOM_CALLS:-0} + 1))
  key="$(printf '%s:%s' "${BATS_TEST_NAME:-nisemono}" "${DISK_TEST_RANDOM_CALLS}" | openssl dgst -md5 -r)"
  { head -c "${count}" /dev/zero || true; } |
    openssl enc -aes-128-ctr -nosalt -K "${key%% *}" -iv 00000000000000000000000000000000
}

disk_test_fill() {
  local file="$1"
  local mebibytes="$2"
  local octal="$3"

  { head -c $((mebibytes * 1048576)) /dev/zero || true; } | LC_ALL=C tr '\000' "${octal}" >"${file}"
}

disk_test_range_bytes() {
  local file="$1"
  local skip="$2"
  local count="$3"
  local part="${file}.range"

  dd if="${file}" of="${part}" bs=512 skip=$((skip / 512)) count=$((count / 512)) 2>/dev/null || return 1
  disk_test_unique_bytes "${part}"
  rm -f "${part}"
}

disk_test_same_prefix() {
  local image="$1"
  local target="$2"
  local bytes
  bytes="$(wc -c <"${image}")"
  bytes="${bytes//[[:space:]]/}"
  head -c "${bytes}" "${target}" >"${target}.prefix" || return 1
  cmp -s "${image}" "${target}.prefix"
  local same="$?"
  rm -f "${target}.prefix"
  return "${same}"
}

disk_test_setup_env() {
  export DISK_FSTAB="${WORK:?}/fstab"
  export REMOVAL_WAIT_SECONDS=1
  export NISEMONO_SLOW_FACTOR=50
  export DISK_TRASH="${WORK}/trash.sh"
  : >"${DISK_FSTAB}"
  printf '%s\n' '#!/bin/sh' "mkdir -p '${WORK}/Trash' && mv -f \"\$1\" '${WORK}/Trash/'" >"${DISK_TRASH}"
  chmod +x "${DISK_TRASH}"
  if [[ "${NISEMONO_TEST_OS}" == "Linux" ]]; then
    export NISEMONO_ALLOW_INTERNAL=y
  fi
}

disk_test_wait_for() {
  local log="$1"
  local pattern="$2"
  local tenths="$3"
  local waited=0

  while ((waited < tenths)); do
    if grep -Eq -- "${pattern}" "${log}" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  printf 'timed out waiting for %s in %s\n' "${pattern}" "${log}" >&2
  return 1
}

disk_test_fs_type() {
  local file="$1"
  local offset="$2"
  local magic
  magic="$(dd if="${file}" bs=1 skip=$((offset + 3)) count=8 2>/dev/null)"
  case "${magic}" in
  EXFAT*) printf 'exfat\n' ;;
  *)
    magic="$(dd if="${file}" bs=1 skip=$((offset + 82)) count=5 2>/dev/null)"
    if [[ "${magic}" == "FAT32" ]]; then
      printf 'fat32\n'
    else
      magic="$(dd if="${file}" bs=1 skip=$((offset + 54)) count=5 2>/dev/null)"
      printf '%s\n' "${magic}" | tr '[:upper:]' '[:lower:]'
    fi
    ;;
  esac
}

disk_test_windows_iso() {
  local iso="$1"
  local tree="${WORK:?}/isotree"
  mkdir -p "${tree}/sources" "${tree}/efi/boot" "${WORK}/payload"
  disk_test_random_bytes $((3 * 1048576)) >"${WORK}/payload/blob"
  wimlib-imagex capture "${WORK}/payload" "${tree}/sources/install.wim" --compress=none >/dev/null || return 1
  printf 'MZ fake loader\n' >"${tree}/efi/boot/bootx64.efi"
  printf 'MZ fake setup\n' >"${tree}/setup.exe"
  case "${NISEMONO_TEST_OS}" in
  Darwin) hdiutil makehybrid -iso -joliet -default-volume-name WIN11 -o "${iso}" "${tree}" >/dev/null ;;
  *) xorriso -as mkisofs -quiet -J -V WIN11 -o "${iso}" "${tree}" >/dev/null 2>&1 ;;
  esac
}

disk_test_name() {
  printf '%s\n' "${1##*/}"
}

disk_test_unique_bytes() {
  local dump
  dump="$(od -An -tx1 -v "$1")" || return 1
  awk '
    { for (i = 1; i <= NF; i++) seen[$i] = 1 }
    END {
      n = 0
      for (b in seen) keys[++n] = b
      for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (keys[j] < keys[i]) { t = keys[i]; keys[i] = keys[j]; keys[j] = t }
      for (i = 1; i <= n; i++) printf "%s%s", keys[i], (i < n ? " " : "\n")
    }
  ' <<<"${dump}"
}

disk_test_normalize() {
  sh "${NISEMONO_TESTS_DIR}/normalize.sh"
}

disk_test_matches_golden() {
  local name="$1"
  local actual="$2"
  local golden="${NISEMONO_TESTS_DIR}/golden/${name}.${NISEMONO_TEST_OS}.txt"
  local normalized

  normalized="$(printf '%s\n' "${actual}" | disk_test_normalize)" || return 1
  if [[ "${NISEMONO_TEST_RECORD:-}" == "1" ]]; then
    printf '%s\n' "${normalized}" >"${golden}"
  fi

  diff <(printf '%s\n' "${normalized}") "${golden}"
}
