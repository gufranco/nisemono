# kodougu 小道具: the family standard

The tools in the table below are one family of command-line tools, called kodougu (小道具), Japanese for the small tools of a craft. Each one is named for a single task in Japanese, and they look, read and behave alike, so a person who knows one already knows how to drive the others.

Two files carry the family, and every member implements everything both say:

- `FAMILY.md`, this file, holds everything the members share. It is the same, byte for byte, in every member.
- [`AGENTS.md`](AGENTS.md) holds only what is exclusive to its own repository: its layout, its names, the rules of its own domain, its release details and its open gaps. Every member's `AGENTS.md` has the same headings. A rule that would serve more than one member belongs here instead.

Nothing about the family lives anywhere else, so anyone with the repositories has all of it. A coding agent's own instruction file in a member only imports `AGENTS.md`.

| Member | What it does | Repository |
|:-------|:-------------|:-----------|
| fusho | Sends an encrypted message through any chat, using the recipient's published SSH keys | [gufranco/fusho](https://github.com/gufranco/fusho) |
| jimaku | Downloads subtitles for videos and saves them as UTF-8 | [gufranco/jimaku](https://github.com/gufranco/jimaku) |
| kakikomi | Writes a disk image to removable media, verified chunk by chunk, never mounted | [gufranco/kakikomi](https://github.com/gufranco/kakikomi) |
| katazuke | Clears the junk other systems leave on a FAT or exFAT disk, then sorts its folders | [gufranco/katazuke](https://github.com/gufranco/katazuke) |
| kiban | Runs Docker and the local databases a project needs, in a native VM on a Mac and with no VM on Linux | [gufranco/kiban](https://github.com/gufranco/kiban) |
| kirisute | Cuts Game Boy Advance, DS, DSi and 3DS ROMs and PSP ISOs down to their real size, and renames them after their headers | [gufranco/kirisute](https://github.com/gufranco/kirisute) |
| kiyome | Overwrites a disk with five verified patterns and names any failing bit line | [gufranco/kiyome](https://github.com/gufranco/kiyome) |
| nazuke | Gives long names short, readable, unique ones, and renames a folder's files to them | [gufranco/nazuke](https://github.com/gufranco/nazuke) |
| shiwake | Sorts the files of a folder into A to Z subfolders by their first letter | [gufranco/shiwake](https://github.com/gufranco/shiwake) |
| yakitsuke | Turns any video into Video CD images, split across discs, with readable subtitles | [gufranco/yakitsuke](https://github.com/gufranco/yakitsuke) |

## How a repository joins

Copy this file in unchanged, write an `AGENTS.md` with the same headings as the other members', follow both, and add the repository to the table above in every member in the same task. With the members checked out side by side, this shows any drift:

```bash
for member in fusho jimaku kakikomi katazuke kiban kirisute kiyome nazuke shiwake yakitsuke; do
  cmp FAMILY.md "../${member}/FAMILY.md"
done
```

A new member also needs, in the same task:

1. The identical files listed under Layout and tooling, and a `ci.yml` modeled on an existing member's, with its own package lists and the shared jobs, `plan`, `lint`, `test-linux`, `test-macos` and `coverage gate`.
2. A public repository, so Actions minutes and the scheduled runs cost nothing, with Dependabot alerts on and the Renovate GitHub App, which the owner keeps installed on every repository.
3. The `TAP_APP_ID` and `TAP_APP_PRIVATE_KEY` secrets, which `formula.yml` uses to reach the tap.
4. In the tap, `Formula/<tool>.rb`, written once the first release tag exists, and the tool's row in each of the tap's four READMEs.
5. Its name in the `for member in` loop above, in every member.

A member that replaces a script in the owner's dotfiles, such as a zsh module, removes that script and its `source` line in the same task, and the dotfiles install the member instead through their Brewfile, since the dotfiles support macOS only.

A rule the owner sets for any member is written here and applied to every member, so they keep one style and one standard of quality. A rule that needs changing is changed in every member in the same task. The family is also the owner's reference standard: another of his projects that is refactored adopts these rules wherever they apply.

The Homebrew tap that ships the members, [gufranco/homebrew-tap](https://github.com/gufranco/homebrew-tap), is not a member: it also carries tools and apps outside the family.

## Commands

Every tool answers the same three commands.

| Command | Prints | Exit |
|:--------|:-------|:-----|
| `help`, `-h`, `--help` | The help page on stdout | 0 |
| `version`, `-V`, `--version` | `<tool> X.Y.Z`, then one `key: value` context line | 0 |
| `doctor` | One row per dependency | 1 only when a required one is missing |

No other spelling of these commands exists. A file named `help`, `doctor` or `version` is still reachable by giving its path, such as `./help`. An action is always a command, such as `kakikomi format`, never an option.

## Help page

One plain page, in this order:

1. `<tool> - <one line saying what it does>`
2. `usage:`, one line per form, each with a short description, ending with `doctor`, `version` and `help`
3. Option sections: `options:`, or named groups such as `disc:` and `picture:` when there are many
4. `environment:`, only for settings that really come from the environment
5. `notes:`
6. `examples:`

The plain page has no colour, no emoji and no bracketed level tags. On a terminal where gum draws, the same page is turned into Markdown, each section a heading over a code block, and printed with `gum format` in the theme's help style.

## Input

- Every setting is a long option. `--name value` and `--name=value` both work, and `--` ends the options.
- A yes or no setting that is asked about interactively has both forms, such as `--verify` and `--no-verify`.
- A setting may also come from an environment variable named after the tool, `<TOOL>_<SETTING>` in capitals, such as `KIYOME_PASSES=3` or `JIMAKU_LANGUAGE=pt-BR`. An option on the command line wins over the environment.
- The family's one shared setting is its look: `KODOUGU_THEME` and `KODOUGU_ACCENT`, read by every member, under Terminal interface.
- No member reads a bare name such as `PASSES`, and none takes its internal variables from the environment: a member either assigns each one outright, or its entry point clears every inherited variable with its internal prefix, such as `JM_`, before anything runs. Test-only switches follow the same rule, such as `JIMAKU_TEST_GUM` and `JIMAKU_TEST_SHELLS`. `scripts/check-names.sh` fails lint on any other name.
- Anything required and not given is asked for when stdin is a terminal: `Label [default]: ` on stderr, up to three tries for a required value.
- Without a terminal the tool never waits on a prompt. It stops with the usage hint below.
- A destructive step asks the person to type the device name: `Type disk4 to erase, or anything else to stop: `.
- With no arguments on a terminal, a tool with several jobs offers a menu headed `What would you like to do?`, numbered on the plain interface and a `gum choose` list where gum draws; a tool with one job asks for its inputs directly.
- A member that takes a disk accepts its device, such as `/dev/disk4`, or any volume mounted from it, such as `/Volumes/USB`, and works on the whole disk behind the volume. Its README shows both forms.

## Output

- Results and progress lines go to stdout. Prompts, diagnostics, and a progress line redrawn in place on a terminal go to stderr.
- Before a long or destructive run, a summary block states what is about to happen. Each label carries a colon and is padded to 8 columns; continuation lines are indented 8 spaces, and the block has a blank line above and below.

  ```text

  Image:  debian.img.xz
          xz, 1.4 GiB (1503238553 bytes)
  Target: /dev/disk4, 7.5 GiB, SANDISK CRUZER

  ```

- A long step shows one progress line: `<Verb> NNN%  <rate>  XmYYs left`. On a terminal it redraws in place; otherwise it prints once per 10 percent.
- The last line states the result in a full sentence, such as `Ejected. /dev/disk4 is safe to remove.`
- A message is printed as one line, and the terminal wraps it at its own width. No member breaks a message into lines itself, so a narrow window, a wide one and a pipe all get the same text, and a script reads one message per line.
- Text written ahead of time, such as the help page and the fixed lines of a summary block, keeps its lines within 80 columns, the default width of Terminal, iTerm2, xterm and GNOME Terminal. `test/width.bats` checks that `help` and `version` stay within them.
- A command whose result a script would read offers `--json`, which prints that result as one JSON object on stdout in place of the text form.

## Terminal interface

Every member draws its terminal interface with [gum](https://github.com/charmbracelet/gum), and every member looks the same.

- gum draws only where it can: prompts when stdin and stderr are terminals, diagnostics when stderr is one, and results when stdout is one, each only when `gum` is on `PATH`. Anywhere else the plain interface above runs, byte for byte, so pipes, files, scripts, `--json` and the golden transcripts never change. A terminal without gum gets the plain interface too, and `doctor` reports gum missing.
- One look for the family: a rounded header box with the tool's name, version and tagline opens the menu; `gum choose` for a menu or a choice, `--no-limit` for several, whose header names `x`, the key gum 2.0.2 marks with, and `--label-delimiter "|"` for a label that carries a value; `gum filter` for a long list or a file; `gum input` for a value, with a default shown as its placeholder and taken when the answer is empty, never prefilled with `--value`, which makes typing append to it, and `--password` for a secret; `gum write` for text, where Enter submits and Ctrl+J adds a line; `gum confirm` for yes or no; `gum spin --spinner dot` while a short step runs; a rounded summary box before a long or destructive run; a thick red danger box above the typed confirmation; a rounded table with a state cell coloured ok, warn or error; the progress line with a bar in the accent; `gum pager` for long output; log lines `INFO`, `WARN` and `ERROR` in the theme's colours, where a message whose first word is capitalized, not an acronym, continues in lowercase after the prefix; badges for a short state; and a bold closing sentence in the ok colour.
- gum's own `gum file` redraws from the top of the screen and hides its header, `gum table --print` styles the first data row as the header and cannot colour a cell, and `gum log` joins lines and breaks words at the screen's edge. No member uses them: files are picked with `gum filter`, tables come from `lib/table.awk` inside a `gum style` box, and log lines are drawn by `<prefix>_ui_log`, one line per message.
- `gum style` drops colour it reads from stdin, so coloured text is passed to it as arguments. `gum spin` draws on stdout, so a member sends it to stderr and lets it wait on the step's process, which runs in the background with its diagnostics held in a file until the spinner stops. The step runs with `<PREFIX>_UI_STEP` set, so its warnings and errors are drawn as they would be on the terminal.
- The palette comes from a theme: `--theme NAME`, else `<TOOL>_THEME`, else `KODOUGU_THEME`, else `kodougu`. The themes are `kodougu`, `catppuccin-mocha`, `catppuccin-latte`, `dracula`, `nord`, `gruvbox`, `tokyo-night` and `mono`, each with an accent, ok, warning, error, muted, text and surface colour and a `gum format` style. `<TOOL>_ACCENT`, else `KODOUGU_ACCENT`, replaces only the accent with a colour such as `#CBA6F7`. An unknown theme or a malformed colour stops the tool with the bad value error below. `NO_COLOR` switches every theme to `mono`, since gum's `CLICOLOR_FORCE` outranks it.
- `lib/ui.sh` holds the themes and every drawing helper, and `lib/table.awk` the table. A member calls them and never calls gum directly from its own modules.
- `test/ui-kit.bats` calls every helper in `lib/ui.sh` directly, so each member covers the whole module whatever it draws. Tests drive the gum path with `<TOOL>_TEST_GUM=1` and `test/bin/gum`, a shim first on `PATH` in every test that records each call in `<TOOL>_TEST_GUM_LOG` and answers from `<TOOL>_TEST_GUM_ANSWERS`, one line per prompt, `<cancel>` for Escape. gum needs a terminal, so CI cannot run the real one; the screens below run the real one.
- The tap's formula for every member depends on `gum`.

## Screens

Every README shows the tool running for real: an animated `screens/hero.gif` under the introduction, the main flow from the first prompt to the closing line, and a collapsed gallery of PNG stills, one per screen, from the summary and the danger box to `doctor`, help and the themes.

- [VHS](https://github.com/charmbracelet/vhs) records them from the real tool and real gum, never from mockups. `make screens` runs `screens/record.sh`, which builds fresh fixtures with `screens/prepare.sh` in `/Users/Shared/demo` before each tape, records it, cleans up with `screens/cleanup.sh`, and crops each still to its content with rounded corners.
- A disk tool works on disk images that `prepare.sh` creates and attaches, addresses them by mount point, and gets root through the test suite's `sudo` shim, so a recording never reaches a real disk. Its tapes end in `.tape.in`, because they type the device name, which `record.sh` fills in. A service tool removes what it created.
- `screens/common.tape` sets one look: the Catppuccin Mocha terminal theme, JetBrainsMono Nerd Font at 24 px, 1600 px wide, with the default `kodougu` theme for the tool.
- The screens are recorded on macOS, which every disk tool needs; `record.sh` refuses elsewhere and names the missing tool when `vhs` or `magick` is absent.
- A change that alters what a screen shows records the screens again in the same commit.

## Diagnostics

| Kind | Form |
|:-----|:-----|
| Error | `<tool>: <message>` |
| Warning | `<tool>: warning: <message>` |
| Refusal before any harm | `<tool>: stopped: <reason>.` |
| Usage error | `<tool>: <problem>. run '<tool> help' for usage.` |
| Unknown option | `<tool>: unknown option '--x'. run '<tool> help' for usage.` |
| Option without its value | `<tool>: option '--x' needs a value. run '<tool> help' for usage.` |
| Bad value | `<tool>: --x must be <rule>, got: <value>` |
| Missing input without a terminal | `<tool>: no <thing> given. run '<tool> help' for usage.` |

- A message starts in lowercase, unless it starts with a name such as `FAT32` or `--passes`, and every sentence after the first does too.
- A sentence ends with a period. A `label: value` line ends with its value.
- Exit status is 0 on success and 1 on failure. An interrupt removes temporary files before the tool exits.

## doctor

```text
dd                 ok       /bin/dd
mcopy              missing  mtools, needed for Windows ISOs and format
```

Each row is `printf '%-18s %-8s %s\n'`, and where gum draws the rows form a table followed by the closing sentence: the dependency; `ok`, `missing` or `warn`; then the path when found, followed by a short note when one matters, or the remedy when not.

A row for a core tool, such as `awk`, `sed`, `dd`, `od`, `cmp`, `tr` or `date`, names its flavor and version after the path, so a bug report says which tools ran:

```text
awk                ok       /usr/bin/awk, bsd 20200816
dd                 ok       /usr/bin/dd, uutils 0.10.0
sed                ok       /opt/homebrew/opt/gnu-sed/libexec/gnubin/sed, gnu 4.10
```

The flavor is `gnu`, `uutils`, `bsd`, `mawk`, `busybox` or `unknown`. It comes from the tool's own `--version` answer, then from where it is installed, then from the system it runs on. A BusyBox applet prints its usage error before the line that names BusyBox, and BusyBox `sed` answers `This is not GNU sed version 4.0`, so the answer is read from the first line that names BusyBox or says it is not GNU, and that `sed` answer reads as `busybox` with no version. A new dependency gets its `doctor` row, with its flavor when it is a core tool, in the same change.

## Toolsets

Every tool that can be installed in more than one version on a supported system is tested in every one of them. Every member runs on the six toolsets below, and CI runs the whole suite on each:

| Toolset | What it is |
|:--------|:-----------|
| Linux, uutils | Ubuntu's default since 25.10: uutils coreutils, with GNU sed and mawk |
| Linux, GNU | GNU coreutils and gawk |
| Linux, BusyBox | BusyBox's applets first on `PATH`: coreutils, awk, sed, grep, find and the rest |
| macOS, native | Everything macOS ships, first on `PATH`: its BSD tools, bash 3.2, zsh, perl, openssl and the rest |
| macOS, Homebrew | Homebrew's current build of every tool macOS also ships, first on `PATH`: coreutils, findutils, gnu-sed, gawk, grep, diffutils, bash, zsh, and each member's own, such as openssl@3, curl, perl, libarchive, gzip, bzip2, libiconv or file-formula |
| macOS, uutils | Homebrew's uutils-coreutils, uutils-diffutils and uutils-findutils, first on `PATH` |

- A member's own dependencies are tested in every build those routes offer, such as `ffmpeg` and `ffmpeg-full`, `subliminal` from apt and its current release, or `age` from apt and from Homebrew. A dependency that gains a new route or build gets its leg in the same change.
- Homebrew on Linux is not a supported route: no member documents it, and CI does not test it.
- A script uses only options all six accept. Where they differ, the code handles each one and a test covers it. A change that passes on one toolset only is not done.
- Any tool macOS ships that Homebrew also builds in a newer version is tested in both: the macOS native toolset runs the system's copy, and the macOS Homebrew toolset runs Homebrew's. A member that starts calling such a tool adds its formula to the Homebrew leg in CI.
- `.github/scripts/toolset.sh native`, `homebrew`, `gnu`, `uutils` or `busybox` prints the directories that put a toolset first on `PATH`; on Linux, `busybox` links BusyBox's applets other than its shells. CI uses it, and a report is reproduced by putting the reporter's toolset first: `export PATH="$(sh .github/scripts/toolset.sh gnu | paste -sd: -):$PATH"`.

## Safety

- A file is written to a temporary file beside it, then renamed over it with `mv -f`, so an interrupted run never leaves half a file. A file the person did not name is never overwritten, and a step that fails leaves the original exactly as it was.
- Files are found with shell globs, never by parsing `ls` or `find` output, so any name, with spaces, brackets or a newline, passes through intact.
- An external command runs once per batch of items, never once per item, such as one `mv` for a batch of files.
- Every external dependency works with the version the current Ubuntu LTS packages and with the current one Homebrew ships. An optional flag is detected once per run, from the tool's own `--help` or `--version`, and used only when it is there.
- A tuned default, such as an encoder setting or a buffer size, is chosen by measurement. A change to one records, in its commit body, a measurement that beats the current value.

## Documentation

- A README in English, Japanese, Simplified Chinese and Hong Kong Traditional Chinese, with the same sections in the same order: Quick start, with Prerequisites, Install and Verify; Usage; the tool's own topic sections; Portability; Development; License.
- The Hong Kong README is written Standard Chinese in Traditional characters with Hong Kong vocabulary, never colloquial Cantonese.
- The console sample at the top of every README is output copied from a real run. Only long data, such as ciphertext, may be cut short.
- A man page, `man/<tool>.1`.
- Completions for bash, zsh and fish under `completions/`.
- A new option goes into the help page, the man page and all three completions in the same commit, and a test fails when they disagree.

## Install

- `brew install gufranco/tap/<tool>` installs the tool, its man page and its completions.
- `make install` does the same from a checkout, under `PREFIX`, `~/.local` by default.
- The formula lives in the tap as `Formula/<tool>.rb`. Its `install` block decides which files reach users, so a new installed file or a new dependency needs a matching change there.
- A release updates the formula on its own: `formula.yml` asks the tap through a GitHub App, and the tap rewrites the formula's `url` and `sha256`. A version bump is never written into the tap by hand. The tap never moves a formula back to an older tag, so two releases close together are safe in any order.
- No member is published to any other package registry.

## Layout and tooling

- `bin/<tool>` is the entry point and sources `lib/*.sh`. There is no build step; `share/` holds data files only. `lib/state.sh` declares every global, and `lib/core.sh` holds `<TOOL>_VERSION`.
- POSIX `sh` without `local`: every global carries the tool's internal prefix, such as `JM_`, and every function-scoped variable carries its function's prefix, such as `jm_fe_`. Variables are written `${name}`.
- `shfmt -i 2` formats every script, and `make lint` fails on unformatted code.
- Release tooling is pnpm, pinned through `packageManager` in `package.json`, running semantic-release. The release job installs it with `pnpm install --frozen-lockfile` and stops on `pnpm audit --audit-level high`.
- Dependabot updates the GitHub Actions and the release tooling, and Renovate updates the runner labels, `.ruby-version` and the Gemfile, so each update arrives once. Both look for updates three times a day, at 05:00, 13:00 and 21:00 UTC. Every bot pull request merges itself once CI passes: when `ci` finishes on a pull request from Dependabot, Renovate or any other bot, `bot-merge.yml` checks that every check on that commit passed, squash-merges it at that commit with a fixed commit body so upstream release notes never trigger a release, then starts `ci` on `main` with `gh workflow run`, since a merge made with `GITHUB_TOKEN` starts no workflow by itself. Renovate's own automerge never merged anything, so `bot-merge.yml` merges its pull requests too. None is merged by hand.
- `actions/*` and `github/*` actions are referenced by version tag, such as `actions/checkout@v7.0.1`; every other action is pinned to a full commit SHA with its version in a trailing comment.
- These files are identical in every member apart from the tool's own name: `FAMILY.md`, `.editorconfig`, `.yamllint.yml`, `.github/actionlint.yaml`, `.github/dependabot.yml`, `renovate.json`, `.github/workflows/release.yml`, `.github/workflows/formula.yml`, `.github/workflows/bot-merge.yml`, `Gemfile`, `Gemfile.lock`, `.ruby-version`, `.simplecov`, `.github/scripts/toolset.sh`, `.github/scripts/set-version.sh`, `.github/scripts/ci-state.sh`, `.github/scripts/recover.sh`, `test/ci-state.bats`, `test/recover.bats`, `lib/ui.sh`, `lib/table.awk`, `test/bin/gum`, `test/ui-kit.bats`, `screens/common.tape`, `screens/record.sh`, `screens/finish.sh`, `scripts/coverage-gate.py`, `scripts/bashcov-run.rb` and `scripts/linux-coverage.sh`.
- A script that only CI or the release runs lives in `.github/scripts/`: `toolset.sh`, `set-version.sh`, `ci-state.sh` and `recover.sh`. A script that a `make` target runs lives in `scripts/`, so everything a contributor can run locally sits in one place. `make lint` checks both folders.

## Tests

- Tests live in `test/`: `helpers.bash` for the shared helpers, `call.sh` to call one function, `run-matrix.sh`, which runs the suites under each shell named in `<TOOL>_TEST_SHELLS`, and `linux-container.sh`, which runs a command in an Ubuntu container. `<TOOL>_TEST_JOBS` runs the files of a suite in parallel through GNU parallel, while the tests inside one file run in order, since they share what `setup_file` built; `<TOOL>_TEST_IMAGE` picks the container image.
- A file that a test file writes when it loads into a folder the whole run shares, such as a wrapper under `BATS_RUN_TMPDIR`, is written to a temporary file beside it and renamed into place. Test files run in parallel, and a file rewritten in place can be read empty by a test in another file, which then passes or fails on nothing.
- A test that hides a tool runs the program with `<prefix>_test_farm`, a folder of links to every program on PATH except the hidden ones. It links one PATH folder per `ln -s` call: one call per program forks thousands of times on a Homebrew Mac and cost about 11 seconds per test.
- `bats` tests drive the real tools on real files, disks or media, and inject faults only through small wrappers on `PATH`.
- Golden transcripts guard the terminal output. A test runs a whole flow, replaces the values that change between runs, such as paths, sizes and rates, and compares the result with `test/golden/<flow>.<OS>.txt`. `<TOOL>_TEST_RECORD=1` rewrites them from a fresh run, on macOS and in the container; the diff is read before it is committed.
- 100 percent bashcov line coverage, gated locally and in CI. `make coverage` runs bashcov on the Mac and in the Ubuntu container and merges both before the gate, so a Linux-only branch counts locally as it does in CI. Every `case` branch runs a command, because bashcov never counts a branch that holds only `;;`. The condition of an `if`, `elif`, `while` or `until` stays on one line, because bashcov 4.0.1 never marks a backslash-continued line of a condition as run; a long command whose output is assigned with `$(...)` moves into its own function for the same reason. `scripts/bashcov-run.rb` reads the trace one record at a time and skips a damaged record, because two traced processes writing at once on macOS can splice a record, and bashcov's own reader stops at the first damaged one and leaves every traced process blocked on a full pipe. `scripts/coverage.sh` feeds bashcov a damaged record before the suite and fails if it stops reading. Before that probe it loads the gems `Gemfile.lock` names and, when one is missing, stops with a message that says to run `bundle install`, so a gem bump that was never installed reads as what it is rather than as a damaged record.
- Tests never write the member's version as a literal; they read it from `lib/core.sh`, so a release does not break them.
- A wait loop polls from milliseconds upward, never with a fixed `sleep 1`. On a runner without `timeout`, a one-second poll per `dd` made two members ten times slower.
- Every test is three blocks, opened by the bare markers `# Arrange`, `# Act` and `# Assert`.

## Quality

- 100% shell script in POSIX `sh`, working under `sh`, `dash`, `bash` and `zsh` on both Linux and macOS, each combination tested in CI. A finding or a failure in any one of them blocks the change.
- On macOS, `bash` and `zsh` each mean two shells, and all four are tested: the system's `/bin/bash`, which is bash 3.2, and `/bin/zsh`, next to Homebrew's current builds in `$(brew --prefix)/bin`. Code that runs under bash uses nothing bash 3.2 lacks.
- ShellCheck at zero errors and zero warnings.
- No comments in source, apart from tool directives and the test markers.
- Make targets, with the same meaning in every member:

  | Target | Does |
  |:-------|:-----|
  | `make help` | Lists the targets |
  | `make fmt` | Formats every script with `shfmt -i 2` |
  | `make lint` | `shfmt -i 2 -d`, ShellCheck `-o all`, the name check and `mandoc -T lint` at zero findings |
  | `make test` | The suites under the system `sh` |
  | `make test-all` | The suites under every installed shell, both builds of bash and zsh on macOS |
  | `make test-linux` | The suites in the Ubuntu container |
  | `make coverage` | bashcov on the Mac and in the container, merged, gated at 100% |
  | `make screens` | the README screens, recorded from the real tool with VHS, on macOS |
  | `make check` | `lint` and `test` |
  | `make install` | The tool, man page and completions under `PREFIX` |

  CI installs shfmt v3.14.1 from its release binary, checked against its SHA-256.
- Conventional commits pushed straight to `main`; there are no pull requests from people. semantic-release cuts the version: a `feat` or `fix` commit publishes a release, stamps `<TOOL>_VERSION` in `lib/core.sh` through `.github/scripts/set-version.sh` and updates `CHANGELOG.md`.
- Before every push: `make lint`, `make test-all` on macOS, `make test-linux` and `make coverage`. CI repeats them; it does not replace them.
- Any push or merge to `main` is safe at any moment, and nobody times or watches one. Push as soon as the local gates pass, never waiting for a CI or release run. The newest green push releases every commit since the last tag, and semantic-release publishes nothing from a commit `main` has already moved past.
- CI follows the owner's workflow defaults. `ci.yml` runs on every push to `main` and every pull request that changes anything other than Markdown, and on demand. GitHub's free plan runs at most five macOS jobs at a time, so the macOS jobs start only after lint and every Linux job passed, a failing macOS job cancels the others, and a pull request from Dependabot or Renovate runs only the macOS coverage job, which the `plan` job decides. The Ubuntu bash job and the macOS Homebrew bash job run their suites under bashcov, and `coverage gate` merges the two. Homebrew neither updates itself nor cleans up in CI, the Linux jobs cache their apt downloads, and every suite runs with `<TOOL>_TEST_JOBS` set. It has one top-level concurrency group per event and ref with `cancel-in-progress: true`, so a newer push cancels the run for an older commit. The release lives in `release.yml`, started by `workflow_run` when `ci` succeeds on `main` for a push or an on-demand run, in a job group that never cancels, so no push can stop a release halfway. GitHub sometimes never gives a job a runner and cancels it, which fails the run and would lose the release, so the `recover` job in `release.yml` runs every hour, on demand, and whenever `ci` fails on `main`: `.github/scripts/ci-state.sh` reads the state of `main`'s newest commit, `.github/scripts/recover.sh` starts a new `ci` run when every failed job of the newest run never got a runner, up to five per commit and then fails visibly, and it releases a green commit that still holds unreleased `feat`, `fix`, `perf`, `revert` or breaking commits. Starting `ci` with `gh workflow run` is used because `GITHUB_TOKEN` is documented to start `workflow_dispatch` runs, while its re-runs are not. A run that `GITHUB_TOKEN` started fires no `workflow_run` of its own when it ends, and GitHub runs the hourly schedule only now and then, so `recover` waits for the run it started, polling once a minute within a 355-minute job: it starts another when that run also never got a runner, and hands the commit to the release when it turns green, unless `main` has moved on. The release asks the tap to bump through `gh workflow run formula.yml`, since a `workflow_run` workflow cannot call a reusable workflow. `step-security/harden-runner` is the first step of every job.
- macOS runners are an approved exception to the Ubuntu-only default (owner, 2026-10-29): the native and Homebrew toolsets and the macOS disk paths can only be tested there.
