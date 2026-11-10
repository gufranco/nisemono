#!/bin/sh

demo=/Users/Shared/demo
disk=$(sed -n 's/^DISK=//p' "${demo}/demo.env")
real=$((16 * 1048576))
bs=512
at=0
for word in "$@"; do
  case "${word}" in
  bs=*) bs="${word#bs=}" ;;
  seek=*) at="${word#seek=}" ;;
  skip=*) at="${word#skip=}" ;;
  *) ;;
  esac
done
target=0
for word in "$@"; do
  case "${word}" in
  "of=/dev/r${disk}" | "if=/dev/r${disk}") target=1 ;;
  *) ;;
  esac
done
count=$#
for word in "$@"; do
  if [ "${target}" = 1 ] && [ $((at * bs)) -ge "${real}" ]; then
    case "${word}" in
    seek=*) word="seek=$(((at * bs % real) / bs))" ;;
    skip=*) word="skip=$(((at * bs % real) / bs))" ;;
    *) ;;
    esac
  fi
  set -- "$@" "${word}"
done
shift "${count}"
exec /bin/dd "$@"
