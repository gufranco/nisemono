#!/bin/sh
sed -E \
  -e '/overhead from throughput was not possible/d' \
  -e '/answered too fast to time/d' \
  -e '/Speed is not being watched on this disk/d' \
  -e '/^.*Measured (read|write): /d' \
  -e '/^Pass [0-9]+ of [0-9]+, .* [0-9]{1,2}%  /d' \
  -e 's#/dev/r?disk[0-9]+#DEV#g' \
  -e 's#/dev/loop[0-9]+#DEV#g' \
  -e 's/[0-9.]+ (B|KiB|MiB|GiB)\/s/RATE/g' \
  -e 's/[0-9]+m[0-9]{2}s left/T left/g' \
  -e 's/(^| )(disk|loop)[0-9]+( |$)/\1DISK\3/g' \
  -e 's/[0-9]+m?s to reach/N to reach/g' \
  -e 's/allowing [0-9]+x/allowing Nx/g' \
  -e 's/over [0-9]+ chunks/over N chunks/g' \
  -e 's/\[[0-9][0-9]:[0-9][0-9]\] //g'
