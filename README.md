# loup-cmd-kvstore

An embedded key-value store in [Loup](https://code-craft.ai/references/loup):
one append-only log file of checksummed records, an in-memory index rebuilt
by replaying it, compaction, and crash safety: a record torn by a crash is
detected, ignored and cut off before the next write.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is a `host.native` (host-compiled) project.

## What this example shows

- **`unique class` as the file-handle owner.** `LogFile`
  (`source/store/logfile.lphc`) owns one POSIX file descriptor, and `Store`
  (`source/store/store.lphc`) owns the `LogFile` and the index. A
  `unique class` has exactly one owner, so no second reference can use the
  descriptor after it is closed, and its `finalize()` closes it exactly once,
  at `del` or at the end of the owner's scope. `unique class` is accepted only
  in `host.native` (and `freestanding`): in a `host.dual` file it is
  `E_UNIQUE_CLASS_ARC_BINDING`.
- **Ownership verbs.** Commands change the store through
  `cmd_put(edits store: Store, ...)`; compaction consumes it:

  ```loup
  pub func compact(takes store: Store): CompactResult {
      ...
      let out = LogFile(tmp, true);   # PATH.compact, emptied
      out.append(text);               # one write(), then fsync()
      del out;                        # close the new file
      del store;                      # close the old log's descriptor now
      replace_file(tmp, path);        # rename(2): old log or new, never half
      return result;
  }
  ```

  After `compact(takes: store)` the caller cannot touch `store` again; the
  compiler reports `E_USE_AFTER_TAKE`.
- **Calling C.** `open`, `write`, `fsync`, `ftruncate`, `close` and `rename`
  are libc functions declared with `extern native "c"`. They run only in a
  native binary; `loup run` stops at the first call.
- **Crash-safe records.** Each record is one line with a CRC-32 (written in
  Loup) of its payload, written with one `write()` on an `O_APPEND`
  descriptor and made durable with `fsync()`. Replay stops at the first
  unterminated, malformed or corrupt line; a write command first cuts that
  torn tail off with `ftruncate()`.
- **Pure replay.** `replay(text)` turns the file's text into the index and
  counters without touching the file system, so most tests need no file.

## Requirements

- Linux x86-64 (the open flags are Linux's).
- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later; see [Installing Loup Lite](#installing-loup-lite).
- `make`, and `clang` 17 or later for the native build.

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. Commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Usage

```sh
make build                                        # native binary: build/kvstore
make ci                                           # check, native unit tests, build, end-to-end tests
make run ARGS="--file /tmp/demo.kv put city Paris"   # build, then run with ARGS
```

The data file comes from `--file FILE` or the `KVSTORE_FILE` environment
variable:

```text
$ export KVSTORE_FILE=demo.kv
$ build/kvstore put user:1 'Ann Lee'
$ build/kvstore put user:2 Bob
$ build/kvstore put motd $'Hello,\nworld: 100%'
$ build/kvstore get user:1
Ann Lee
$ build/kvstore scan user:
user:1	Ann Lee
user:2	Bob
$ build/kvstore del user:2
$ build/kvstore get user:2
kvstore: user:2: not found
$ build/kvstore put user:1 'Ann B. Lee'
$ cat demo.kv
KVSTORE 1
128105d1 P user:1 Ann%20Lee
17758304 P user:2 Bob
6c0dbd15 P motd Hello,%0Aworld:%20100%25
54261879 D user:2
f6ac04a9 P user:1 Ann%20B.%20Lee
$ build/kvstore stats
file:          demo.kv
size:          152 bytes
records:       5 (4 puts, 1 delete)
live keys:     2
stale records: 3
torn tail:     0 bytes
$ build/kvstore compact
compacted demo.kv: 5 records, 152 bytes -> 2 records, 84 bytes
$ cat demo.kv
KVSTORE 1
6c0dbd15 P motd Hello,%0Aworld:%20100%25
f6ac04a9 P user:1 Ann%20B.%20Lee
```

A crash in the middle of a write, simulated by cutting the end off the last
record:

```text
$ build/kvstore put user:3 Cy
$ head -c -6 demo.kv > t && mv t demo.kv
$ build/kvstore get user:3
kvstore: user:3: not found
$ build/kvstore stats
file:          demo.kv
size:          99 bytes
records:       2 (2 puts, 0 deletes)
live keys:     2
stale records: 0
torn tail:     15 bytes
$ build/kvstore put user:4 Dee
kvstore: demo.kv: dropped a torn tail of 15 bytes
$ build/kvstore scan
motd	Hello,
world: 100%
user:1	Ann B. Lee
user:4	Dee
```

## Commands and options

| Command | Meaning |
|---|---|
| `put KEY VALUE` | set KEY to VALUE |
| `get KEY` | print the value and a newline |
| `del KEY` | delete KEY |
| `scan [PREFIX]` | `KEY<TAB>VALUE` for every live key (starting with PREFIX), sorted |
| `compact` | rewrite the log with one record per live key |
| `stats` | size, record counts, live keys, stale records, torn tail |
| `help` | the help text |

Options: `-f FILE` / `--file FILE` / `--file=FILE` (else `$KVSTORE_FILE`),
`-h` / `--help`, `-V` / `--version`. Options may come anywhere before `--`;
a value that starts with `-` goes after it: `kvstore put -- temp -5`.

Keys are non-empty; keys and values may hold any text, including spaces,
newlines and non-ASCII characters. Reading a file that does not exist acts
on an empty store and does not create it. A file that does not start with
`KVSTORE 1` is refused and left untouched.

Exit status: `0` success, `1` key not found (`get`, `del`), `2` usage error or
store error (not a kvstore log, a failed write).

## The log format

```text
KVSTORE 1
<crc32> P <key> <value>
<crc32> D <key>
```

Every record is one line of printable ASCII: an 8-digit hexadecimal CRC-32 of
the payload, then the payload. Keys and values are percent-encoded (every
byte of their UTF-8 form outside `!`..`~`, and `%`, becomes `%XX`), so a
line has no spaces or newlines inside a field and its length in characters
is its length in bytes.

## Limits

- One process at a time: there is no file lock.
- The whole log is read and replayed on every run, and the index holds the
  values in memory; fine for thousands of keys, not for gigabytes.
- `compact` does not `fsync` the directory after `rename()`, so on some file
  systems a power failure right after compaction can bring back the old log
  (never a mix of both).
- A corrupt record in the middle of the log ends the replay there, like a
  torn tail: later records are ignored and cut off by the next write.
- Linux x86-64 only (libc flag values).

## Layout

```text
source/main.lphc              # entry point
source/appinfo.lphc           # name, version, exit statuses
source/cli/args.lphc          # options, data file, operand counts
source/cli/usage.lphc         # --help and --version text
source/cli/app.lphc           # run(): parse, dispatch, exit status
source/store/crc32.lphc       # CRC-32
source/store/codec.lphc       # percent-encoding, record lines
source/store/replay.lphc      # replay(): index, counters, torn tail
source/store/logfile.lphc     # libc calls; unique class LogFile
source/store/store.lphc       # unique class Store; compact(takes store)
source/commands/kv.lphc       # the commands and their output
tests/*_test.lphc             # native unit tests (make test)
tests/helpers.lphc            # expect_text(), empty_file()
tests/e2e.sh                  # end-to-end tests of build/kvstore (make e2e)
specs/kvstore/                # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every build and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
