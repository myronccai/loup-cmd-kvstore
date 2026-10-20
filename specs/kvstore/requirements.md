# Requirements: kvstore

## Introduction

`kvstore` is a small embedded key-value store with a command-line front end.
Data lives in one append-only log file: every `put` and `del` appends a
checksummed record, an in-memory index is rebuilt by replaying the log, and
`compact` rewrites the log with only the live records. A crash can leave a
partly written record at the end of the file; the store detects it by its
checksum or missing terminator, ignores it, and cuts it off before the next
write. It is the second host-compiled (`host.native`) project in the
loup-cmd series: a `unique class` owns the POSIX file descriptor, and the
ownership verbs `edits` and `takes` show who may change or consume the store.

## Requirements

### Requirement 1: Commands

**User Story:** As a script author, I want to store and read strings by key
from the shell so that small tools can keep state.

#### Acceptance Criteria

1. WHEN `put KEY VALUE` is run, THE program SHALL append a record and print
   nothing; a later `get KEY` SHALL print VALUE and a newline.
2. WHEN `get KEY` or `del KEY` names a key that is not live, THE program
   SHALL print `kvstore: KEY: not found` on standard error and exit with
   status 1; `del` SHALL then append nothing.
3. WHEN `del KEY` names a live key, THE program SHALL append a delete record,
   after which `get KEY` reports it missing.
4. WHEN `scan [PREFIX]` is run, THE program SHALL print `KEY<TAB>VALUE` for
   every live key that starts with PREFIX (all keys without one), sorted by
   key.
5. WHEN `compact` is run, THE program SHALL rewrite the log with one record
   per live key and print
   `compacted FILE: N records, B bytes -> M records, C bytes`.
6. WHEN `stats` is run, THE program SHALL print the file name, its size, the
   record counts (puts and deletes), the live keys, the stale records and
   the size of any torn tail.
7. Keys SHALL be non-empty; keys and values MAY contain any characters,
   including spaces, newlines, `%` and non-ASCII text.

### Requirement 2: The data file

**User Story:** As a user, I want to choose where the data lives.

#### Acceptance Criteria

1. THE program SHALL use the file given by `-f FILE` / `--file FILE` /
   `--file=FILE`, else the `KVSTORE_FILE` environment variable; with neither
   it SHALL report a usage error.
2. WHEN the file does not exist, read commands SHALL behave as on an empty
   store without creating it; `put`, `del` and `compact` SHALL create it.
3. WHEN the file exists and does not start with the header `KVSTORE 1`, THE
   program SHALL refuse it (`kvstore: FILE: not a kvstore log`, status 2)
   and SHALL NOT change it.

### Requirement 3: Log format and crash safety

**User Story:** As a user, I want a crash in the middle of a write to cost at
most that write.

#### Acceptance Criteria

1. THE log SHALL be ASCII text: the line `KVSTORE 1`, then one line per
   record: an 8-digit hexadecimal CRC-32 of the payload, a space, and the
   payload `P KEY VALUE` or `D KEY`, with KEY and VALUE percent-encoded
   (every byte outside `!`..`~`, and `%`, as `%XX` of its UTF-8 bytes).
2. THE program SHALL write each record with a single `write` call on a file
   opened with `O_APPEND`, then `fsync` it.
3. WHEN replaying, THE program SHALL stop at the first line that is
   unterminated, malformed, or fails its checksum, and treat it and
   everything after it as a torn tail: no command SHALL report data from it.
4. WHEN a command that writes finds a torn tail, THE program SHALL truncate
   the file to the last good record (`ftruncate`) before appending, and
   print `kvstore: FILE: dropped a torn tail of N bytes` on standard error.
5. `compact` SHALL write the new log to `FILE.compact`, `fsync` it and
   `rename` it over FILE, so that a crash leaves either the old or the new
   log.

### Requirement 4: Command line

**User Story:** As a shell user, I want the usual conventions.

#### Acceptance Criteria

1. WHEN `-h` / `--help` or the command `help` is given, THE program SHALL
   print the help text; `-V` / `--version` SHALL print
   `kvstore (loup-cmd-kvstore) 0.1.0`; both exit with status 0.
2. WHEN the command is missing or unknown, an option is unknown, a value is
   missing, a command has the wrong number of operands, or the key is empty,
   THE program SHALL print `kvstore: MESSAGE` and
   `Try 'kvstore --help' for more information.` on standard error and exit
   with status 2.
3. Options MAY appear anywhere before `--`; everything after `--` is an
   operand, so values that start with `-` can be stored.
4. Exit statuses: 0 success, 1 key not found, 2 usage error or store error
   (unreadable file, not a kvstore log, failed write).
