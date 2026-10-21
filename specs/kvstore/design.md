# Design: kvstore

## Overview

`main()` passes `runtime.args()` to `cli.app.run`, which parses the global
options and the command, resolves the data file, and dispatches to
`commands.kv`. Reading the log is a pure function, `replay(text)`, that
returns the index and the counters; read commands (`get`, `scan`, `stats`)
use it directly and never open the file for writing. Write commands open a
`Store`, a `unique class` that owns a `LogFile`, another `unique class` that
owns the POSIX file descriptor.

All sources are `@mode(host.native)` `.lphc` files. `unique class` is
accepted only in `host.native` (and `freestanding`), and the `extern native`
calls to libc run only in a native binary.

## Modules

| Module | Contents |
|---|---|
| `source/main.lphc` | entry point: `run(runtime.args())` |
| `source/appinfo.lphc` | name, version, summary, exit statuses |
| `source/cli/args.lphc` | `Options`, `parse_args`, `resolve_file` |
| `source/cli/usage.lphc` | `usage()`, `version_line()` |
| `source/cli/app.lphc` | `run()`: parse, help/version, dispatch, map errors to statuses |
| `source/store/crc32.lphc` | table-driven CRC-32 (IEEE) over ASCII text |
| `source/store/codec.lphc` | percent-encoding with UTF-8, `encode_record`, `decode_line` |
| `source/store/replay.lphc` | `Replay`, `replay(text)`: rebuild the index, find the torn tail |
| `source/store/logfile.lphc` | libc declarations; `unique class LogFile` |
| `source/store/store.lphc` | `unique class Store`; `open_store`, `read_store`, `compact` |
| `source/commands/kv.lphc` | one function per command, plus pure `render_scan`, `render_stats` |

### Ownership

```loup
unique class LogFile {            # one file descriptor, closed exactly once
    let fd: int32;
    pub modifier func append(line: string): void   # write + fsync
    pub modifier func cut(size: int): void         # ftruncate
    func finalize(): void                          # close
}

unique class Store {              # the writer: log handle + index
    unique var log: LogFile;
    var state: Replay;
    pub modifier func put(key: string, value: string): void
    pub modifier func remove(key: string): bool
}

func apply_put(edits store: Store, key: string, value: string): void
func compact(takes store: Store): CompactResult
```

- A `unique class` has exactly one owner, so there is never a second
  reference through which the descriptor could be used after `close`, and
  calling a `modifier` method needs no `safe { }` block.
- `edits` lets a command change the caller's store without taking it.
- `compact` takes the store: it writes the new log, `del`s the old store
  (which runs `LogFile.finalize` and closes the descriptor at that point),
  renames the new file into place, fsyncs the directory so the rename is
  durable, and returns the counts. Using the store
  after `compact(takes: store)` is a compile error (`E_USE_AFTER_TAKE`).

### Records

```text
KVSTORE 1
128105d1 P user:1 Ann%20Lee
cd2f49c3 D user:1
```

`encode_record` escapes the key and value, builds the payload, and prefixes
its CRC-32. `decode_line` splits a line into checksum and payload, checks
the checksum, and returns `Some(Record)` or `None`. A record is ASCII, so its
length in characters is its length in bytes, which makes byte offsets
(needed for `ftruncate`) easy to keep.

### Replay

`replay(text)` checks the header (an empty file, or a prefix of the header,
is an empty store whose prefix is torn), then walks the records with a
`RecordReader`, an `Iterator[Record]` over the lines that advances
`good_bytes` past each good record. Each record updates
`index: dict[string, string]` and the counters. The first bad or
unterminated line ends the iteration; the file size minus `good_bytes` is
the torn tail.

## Error handling

`StoreError` (an `Exception` with the file in `path`) reports file
problems: open, write, truncate, rename or directory-sync failures; its
subclass `NotAStoreError` reports a file that is not a kvstore log. The
message is `PATH: what`. `run` maps any of them to `kvstore: message` and
status 2. If writing the compacted log fails, `compact` removes the partial
`PATH.compact` and rethrows, so the old log stays as it was. A missing key
is status 1. Usage errors (from `parse_args`, `check_command` and
`resolve_file`, each a `Result`) are status 2 with the `Try` line.

## Testing

All tests are `@mode(host.native)` and run through the native AOT pipeline
(`loup-bootstrap test --native`), which is also the only way to run the
libc calls.

- `tests/crc32_test.lphc`: the CRC-32 check value and a few known strings.
- `tests/codec_test.lphc`: escaping round trips (spaces, `%`, newlines,
  non-ASCII), records, rejected lines.
- `tests/replay_test.lphc`: puts, overwrites, deletes, header handling, every
  kind of torn tail.
- `tests/store_test.lphc`: a real file in a temporary directory: put, delete,
  reopen, repair of a torn tail, compaction.
- `tests/args_test.lphc`, `tests/app_test.lphc`: options, statuses.
- `tests/e2e.sh`: the binary, including a log truncated in the middle of its
  last record (`truncate -s -N`), a corrupted checksum, a foreign file that
  must be left alone, values that start with `-`, and `KVSTORE_FILE`.
