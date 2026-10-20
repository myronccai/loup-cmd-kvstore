# AGENTS.md

This repository is `kvstore`, an embedded key-value store written in the Loup
programming language, as part of the loup-cmd series of example
applications. It is a `host.native` project: every source file is `.lphc`,
a `unique class` owns the log's POSIX file descriptor, and libc is called
through `extern native`, so the program only runs as a native binary.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` before writing or changing any Loup code
in this repository. It links to detailed references under
`skills/loup-programmer/references/` for syntax, types and ownership
(`unique`, `edits`, `takes`), execution modes and projects, errors and
diagnostics, the standard library, and common mistakes. Load those only as
needed.

## Code layout

```text
.
├── package.lppkg                # Loup manifest: name, version, toolchain, [build] entry, [test] pattern
├── Makefile                     # run, check, test, build, e2e, ci, clean
├── source/                      # all Loup code; modules import each other by path from here
│   ├── main.lphc                # entry point: func main() calls run(runtime.args())
│   ├── appinfo.lphc             # APP_NAME, APP_VERSION, exit statuses, FILE_ENV
│   ├── cli/
│   │   ├── args.lphc            # struct Options, parse_args(), resolve_file(), check_command()
│   │   ├── usage.lphc           # usage(), version_line()
│   │   └── app.lphc             # run(), run_with_env(): parse, help/version, dispatch, statuses
│   ├── store/
│   │   ├── crc32.lphc           # crc32_ascii(), crc32_bytes()
│   │   ├── codec.lphc           # escape(), unescape(), encode_record(), decode_line()
│   │   ├── replay.lphc          # struct Replay, replay(): index, counters, torn tail
│   │   ├── logfile.lphc         # extern native libc; unique class LogFile; StoreError
│   │   └── store.lphc           # read_store(); unique class Store; compact(takes store)
│   └── commands/
│       └── kv.lphc              # run_command(), cmd_*(), render_scan/stats/compact()
├── tests/
│   ├── *_test.lphc              # native unit tests: func test_*(): void
│   ├── helpers.lphc             # expect_text(), empty_file()
│   └── e2e.sh                   # end-to-end tests of the native binary
├── specs/kvstore/               # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
├── .github/workflows/ci.yml     # installs Loup and runs `make ci`
└── build/                       # build output (git-ignored)
```

## Build, run and test

Prerequisites: Linux x86-64, Loup 1.26.0 (`loup` and `loup-bootstrap` on
`PATH`), `make`, and `clang` 17 or later.

| Task | Command | Notes |
|------|---------|-------|
| Run | `make run ARGS="--file /tmp/demo.kv put k v"` | builds `build/kvstore`, then runs it: `loup run` cannot call libc |
| Type-check | `make check` | checks `source/main.lphc` and every module it imports; tests are not checked |
| Run all tests | `make test` | every `tests/*_test.lphc`, each test built as a native binary (about 1 s each) |
| Run matching tests | `make test TEST_ARGS="--filter torn"` | tests whose name contains `torn` |
| Run one test file | `make test TEST_ARGS="--file tests/replay_test.lphc"` | |
| Build | `make build` | native binary at `build/kvstore` |
| End-to-end tests | `make e2e` | runs `tests/e2e.sh build/kvstore`: output, statuses and the log's exact bytes |
| Everything CI runs | `make ci` | check, test, build, e2e, then `build/kvstore --version` |
| Clean | `make clean` | removes `build/`, `.temp/` and `.loup-cache/` |

Run `make ci` before reporting a change as done.

The Makefile uses `loup-bootstrap` (Stage0) for every step: the self-hosted
`loup` refuses `check`, and Stage0 runs `host.native` test files through the
native AOT pipeline in a temporary package outside the repository. That is
why `LOUPPATH` is absolute (`$(CURDIR)/source:$(CURDIR)/tests`). Each test
binary runs in that temporary directory, so tests that need files use
relative names (`empty_file("x.kv")`).

## Making a change

1. Update the spec in `specs/kvstore/` (see [specs/README.md](specs/README.md)).
2. Change the code under `source/`.
3. Add or update unit tests in `tests/` and cases in `tests/e2e.sh`.
4. Run `make ci`.
5. Tick the finished tasks in `specs/kvstore/tasks.md`.

Keep file-format logic pure (`replay`, `decode_line`, `encode_record`) and
all writes inside `LogFile`. Only the `cmd_*` functions and `run_command`
print.

## Conventions

- Every source file is `@mode(host.native)` with the `.lphc` extension. Only
  `source/main.lphc` has a `main()`.
- Never change the record format without bumping the header (`KVSTORE 1`):
  old logs must be refused, not misread.
- Modules import each other by path from `source/`:
  `from store.codec import (escape);`. Tests import them the same way. Do not
  use relative imports.
- Struct fields read from another module must be `pub`; fields assigned
  after construction must be `var`.
- Loup 1.26.0 native-lane pitfalls this code works around:
  - `match` on a `string` always takes the `_` arm in Stage0 native code: use
    `if (s == "x") ... else if` chains (see `run_command`).
  - `io.fs.rename` aborts a native binary: `rename` is declared from libc.
  - `expectEq` on two equal strings fails in native tests: use
    `expect_text(actual, expected, context)` from `tests/helpers.lphc`.
  - A test file that does not compile (a reserved word such as `del` or
    `where` as a binding is enough) is skipped silently. A full `make test`
    therefore fails unless it ran every `test_` function; find the broken
    file with `LOUPPATH=source:tests loup-bootstrap run tests/FILE`.
- Keep `APP_VERSION` in `source/appinfo.lphc` equal to `version` in
  `package.lppkg`.
- The skill documents toolchain 1.25.1; this project targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
