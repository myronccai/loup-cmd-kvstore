# template Loup commandline application

A GitHub template for a command-line application written in
[Loup](https://code-craft.ai/references/loup). It includes argument parsing,
command dispatch, a sample `hello` command, tests, a native build and a CI
workflow.

After creating a repository from this template, work through
[REPOSITORY_TODOS.md](REPOSITORY_TODOS.md).

## Requirements

- Loup 1.26.0 or later:

  ```sh
  curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
  loup --version
  ```

- `make`
- `clang` 17 or later for native builds. Native builds are supported on Linux
  x86-64 and arm64, and are a preview on macOS and Windows.

## Usage

```sh
make run ARGS="--help"            # run from source
make run ARGS="hello Ann --shout"
make check                        # type-check the program
make test                         # run the tests in tests/
make build                        # native binary: build/myapp
make ci                           # check, test, build and smoke-test the binary
make clean
```

```text
$ build/myapp --help
usage: myapp [OPTIONS] COMMAND [ARGS...]

A command-line application written in Loup.

Commands:
  hello [NAME]          Print a greeting (NAME defaults to 'world')
  help                  Show this help

Options:
  -g, --greeting TEXT   Greeting used by 'hello' (default: Hello)
      --shout           Print the greeting in upper case
  -v, --verbose         Print diagnostic messages to stderr
  -h, --help            Show this help and exit
  -V, --version         Show the version and exit
```

Exit status: `0` success, `1` runtime failure, `2` usage error.

## Layout

```text
package.lppkg            # Loup manifest
Makefile                 # run, check, test, build, ci, clean
source/                  # the application's Loup code
├── main.loup            # entry point
├── cli/                 # argument parsing, help text, command dispatch
└── commands/            # one module per command
tests/                   # *_test.loup files
specs/                   # feature specs: requirements, design, tasks
skills/loup-programmer/  # agent skill for writing Loup
```

[AGENTS.md](AGENTS.md) has the full layout, every build and test command, and
the steps for adding a command.

## Notes on the toolchain

- On Linux x86-64, `loup` is the self-hosted driver and `loup-bootstrap` is
  Stage0. `check` and `test` use `loup-bootstrap`; on other platforms both
  names run the same tool. The Makefile handles this.
- Modules import each other by their path under `source/`
  (`from cli.args import (Options);`). Tests import them the same way, which
  is why `make test` puts `source/` on `LOUPPATH`.
- The Wasm build (`loup-bootstrap build`) is experimental: modules that use
  `i"..."` interpolation build but trap at run time, so this template builds
  native binaries.
