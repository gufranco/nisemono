# nisemono

Guidance for anyone, human or agent, changing nisemono. What nisemono is and how to use it lives in [README.md](README.md).

[FAMILY.md](FAMILY.md) holds everything nisemono shares with the rest of the kodougu family, and it is the same in every member. This file holds only what is exclusive to nisemono, under the same headings as the agent guide of every member. Read both before changing anything; a rule that would serve the other members goes into `FAMILY.md` instead of here.

## Layout

| Path | Holds |
|:-----|:------|
| [`bin/nisemono`](bin/nisemono) | The entry point: usage, options and command routing |
| [`lib/`](lib) | The modules. [`lib/state.sh`](lib/state.sh) declares every global; [`lib/probe.sh`](lib/probe.sh) runs the grid pass and [`lib/refine.sh`](lib/refine.sh) narrows a fake down to its exact size |
| [`man/nisemono.1`](man/nisemono.1) | The man page |
| [`completions/`](completions) | bash, zsh and fish completions |
| [`test/`](test) | The `bats` suite, its helpers, the counterfeit stand-ins in [`test/fakes.bash`](test/fakes.bash), the fake `sudo` and the Linux container script |
| [`scripts/`](scripts) | Coverage, the coverage gate, the Linux coverage run and the name check, which `make` runs |
| [`.github/scripts/`](.github/scripts) | The toolset helper and the release version stamp, which only CI and the release run |

## Names

- Globals carry `DISK_`; function-scoped variables carry a per-function `disk_` prefix. kiyome and kakikomi use the same names, see Domain rules.
- Settings come from `NISEMONO_<NAME>`, such as `NISEMONO_SAMPLES`, `NISEMONO_JSON` or `NISEMONO_THEME`; test switches are `NISEMONO_TEST_SHELLS`, `NISEMONO_TEST_RECORD`, `NISEMONO_TEST_GUM` and `NISEMONO_INTERACTIVE`.
- Output goes through `disk_info`, `disk_say`, `disk_error` and `disk_warning`, which hand over to the `disk_ui_` helpers in [`lib/ui.sh`](lib/ui.sh) where gum draws.

## Behaviour

- nisemono has one job today, so a bare `nisemono` on a terminal asks for the disk directly and probes it.
- The verdict is `pass` or `fake`. A fake verdict is proof; a pass never claims the card is genuine, only that every test block came back.
- `--json` reports the disk, the size it reports, its real size, the size up to the last block that read back, the verdict, and the counts of grid blocks that read back, came back from a lower address and were lost.

## Domain rules

- kiyome and kakikomi are the closest siblings and share the `disk_` helpers; a fix to a shared helper, such as the option parser in [`lib/cli.sh`](lib/cli.sh) or the transfer handling in [`lib/io.sh`](lib/io.sh), lands in all three repositories.
- Every block is written before any block is read. Reading a block right after writing it hides a wrap, because the overwrite only happens when a later block lands on the same place.
- The grid step is a power of two, so a wrap at any power of two at or above the step makes two grid blocks collide. Fake controllers wrap that way because they ignore high address bits.
- Tags carry a random code per run, so a block left by an earlier run never counts as this run's.
- Each test block is one `dd` call, because `dd` seeks once per call and the blocks are scattered across the disk.
- Tests play a fake card on Linux with a device-mapper table over a loop device, and on macOS with a `dd` stand-in that remaps or drops offsets past the real size.
- The bytes a `dd` moved come from its bytes line; BusyBox's `dd` prints only record counts, so there the count is the whole records out times the block size.

## Release

- `NISEMONO_VERSION` lives in [`lib/core.sh`](lib/core.sh).
- The tap's `Formula/nisemono.rb` depends on `gum`.

## Gaps against FAMILY.md

- The README is in English only; the Japanese, Simplified Chinese and Hong Kong Traditional Chinese READMEs are not written yet (as of 2026-11-10).
- The screens are not recorded yet: `make screens` still needs tapes for probe (as of 2026-11-10).
