# Tasks: kvstore

- [x] 1. CRC-32 and the percent-encoding codec with UTF-8
  - _Requirements: 1.7, 3.1_
- [x] 2. Record encoding and line decoding with checksum checks
  - _Requirements: 3.1_
- [x] 3. Replay: header check, index, counters, torn-tail detection
  - _Requirements: 2.3, 3.3_
- [x] 4. `unique class LogFile` over libc `open`/`write`/`fsync`/`ftruncate`/`close`
  - _Requirements: 3.2, 3.4_
- [x] 5. `unique class Store`: open with repair, put, remove, compaction by rename
  - _Requirements: 1.1, 1.3, 1.5, 2.2, 3.4, 3.5_
- [x] 6. Commands `put`, `get`, `del`, `scan`, `compact`, `stats`
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_
- [x] 7. Options, data file resolution, help, version, usage errors
  - _Requirements: 2.1, 4.1, 4.2, 4.3, 4.4_
- [x] 8. Native unit tests and end-to-end tests with a truncated log
  - _Requirements: all_
