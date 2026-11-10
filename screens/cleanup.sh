#!/bin/sh
set -u

demo=/Users/Shared/demo
if [ -f "${demo}/demo.env" ]; then
  disk=$(sed -n 's/^DISK=//p' "${demo}/demo.env")
  if [ -n "${disk}" ] && hdiutil info | grep -q "${demo}/"; then
    hdiutil detach -quiet -force "/dev/${disk}"
  fi
fi
rm -rf "${demo}"
