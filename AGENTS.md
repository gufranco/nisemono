# nisemono

Guidance for anyone, human or agent, changing nisemono. What nisemono is and how to use it lives in [README.md](README.md).

[FAMILY.md](FAMILY.md) holds everything nisemono shares with the rest of the kodougu family, and it is the same in every member. This file holds only what is exclusive to nisemono, under the same headings as the agent guide of every member. Read both before changing anything; a rule that would serve the other members goes into `FAMILY.md` instead of here.

## Layout

| Path | Holds |
|:-----|:------|
| [`bin/nisemono`](bin/nisemono) | The entry point: usage, options and command routing |
| [`lib/`](lib) | The modules. [`lib/state.sh`](lib/state.sh) declares every global; [`lib/probe.sh`](lib/probe.sh) runs the grid pass, [`lib/refine.sh`](lib/refine.sh) narrows a fake down to its exact size, [`lib/fill.sh`](lib/fill.sh) checks a volume's free space and [`lib/fix.sh`](lib/fix.sh) repartitions a fake |
| [`man/nisemono.1`](man/nisemono.1) | The man page |
| [`completions/`](completions) | bash, zsh and fish completions |
| [`test/`](test) | The `bats` suite, its helpers, the counterfeit stand-ins in [`test/fakes.bash`](test/fakes.bash), the fake `sudo` and the Linux container script |
| [`screens/`](screens) | The VHS tapes and scripts behind `make screens`; [`screens/fake-dd.sh`](screens/fake-dd.sh) makes the demo disk image wrap every 16 MiB |
| [`scripts/`](scripts) | Coverage, the coverage gate, the Linux coverage run and the name check, which `make` runs |
| [`.github/scripts/`](.github/scripts) | The toolset helper and the release version stamp, which only CI and the release run |

## Names

- Globals carry `DISK_`; function-scoped variables carry a per-function `disk_` prefix. kiyome and kakikomi use the same names, see Domain rules.
- Settings come from `NISEMONO_<NAME>`, such as `NISEMONO_SAMPLES`, `NISEMONO_JSON` or `NISEMONO_THEME`; test switches are `NISEMONO_TEST_SHELLS`, `NISEMONO_TEST_RECORD`, `NISEMONO_TEST_GUM` and `NISEMONO_INTERACTIVE`.
- Output goes through `disk_info`, `disk_say`, `disk_error` and `disk_warning`, which hand over to the `disk_ui_` helpers in [`lib/ui.sh`](lib/ui.sh) where gum draws.

## Behaviour

- nisemono has three jobs, probe, fill and fix, so a bare `nisemono` on a terminal opens the menu.
- `fill` writes 1 MiB blocks into `.nisemono-<code>` on the volume, each a 64-byte header naming the run code and block index and a random filler shared by the run, reads them back with `iflag=direct` on Linux, or after dropping the page cache, and after remounting at the same mount point on macOS, then removes the folder, also on an interrupt.
- `fix` probes first, stops on a pass, and on a fake builds a sparse image of the real size rounded down to a MiB with an MBR partition at 1 MiB and a FAT16 filesystem, FAT32 past 2 GiB, made by `mformat`, then writes only up to the end of its FAT metadata, the way kakikomi's format does.
- The verdict is `pass` or `fake`. A fake verdict is proof; a pass never claims the card is genuine, only that every test block came back.
- `--json` reports the disk, the size it reports, its real size, the size up to the last block that read back, the verdict, and the counts of grid blocks that read back, came back from a lower address and were lost.

## Domain rules

- kiyome and kakikomi are the closest siblings and share the `disk_` helpers; a fix to a shared helper, such as the option parser in [`lib/cli.sh`](lib/cli.sh) or the transfer handling in [`lib/io.sh`](lib/io.sh), lands in all three repositories.
- Every block is written before any block is read. Reading a block right after writing it hides a wrap, because the overwrite only happens when a later block lands on the same place.
- The grid step is a power of two, so a wrap at any power of two at or above the step makes two grid blocks collide. Fake controllers wrap that way because they ignore high address bits.
- Tags carry a random code per run, so a block left by an earlier run never counts as this run's.
- Each test block is one `dd` call, because `dd` seeks once per call and the blocks are scattered across the disk.
- A device-mapper table lives in the kernel of the VM every container shares, so a leaked one keeps its loop device busy for every later run. `fake_counterfeit` runs inside `$(...)`, so it records its table's name in `$WORK/fake-mapper` for teardown to remove, and [`test/linux-container.sh`](test/linux-container.sh) removes any `nisemono-fake-*` table left by an earlier run before the suite starts.
- Tests play a fake card on Linux with a device-mapper table over a loop device, and on macOS with a `dd` stand-in that remaps or drops offsets past the real size, only for a `dd` that reads or writes the fake device.
- The bytes a `dd` moved come from its bytes line; BusyBox's `dd` prints only record counts, so there the count is the whole records out times the block size.

## Release

- `NISEMONO_VERSION` lives in [`lib/core.sh`](lib/core.sh).
- The tap's `Formula/nisemono.rb` depends on `gum` and `mtools`.

## Gaps against FAMILY.md

None (as of 2026-11-10). One departure from the Safety section is approved: each test block is its own `dd` call, recorded under Domain rules.
