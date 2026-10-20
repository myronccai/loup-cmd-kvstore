#!/usr/bin/env bash
# End-to-end tests: run the built binary against data files in a temporary
# directory and compare its standard output (or standard error), its exit
# status and the log file's bytes with the expected ones. The expected log
# lines were computed independently (Python's zlib.crc32).
#
# usage: tests/e2e.sh BINARY

set -u
BIN=$1
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0
unset KVSTORE_FILE

ok() { pass=$((pass + 1)); }
bad() {
    fail=$((fail + 1))
    echo "FAIL: $1"
    sed 's/^/    stdout: /' "$TMP/out" | head -5
    sed 's/^/    stderr: /' "$TMP/err" | head -5
}

# run ARGS...: runs BINARY with standard input from /dev/null; sets $status.
run() {
    "$BIN" "$@" < /dev/null > "$TMP/out" 2> "$TMP/err"
    status=$?
}

# check NAME STATUS EXPECTED_STDOUT [ARGS...]: exact standard output.
check() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    if [ "$status" -eq "$want_status" ] && cmp -s "$TMP/want" "$TMP/out"; then
        ok
    else
        bad "$name (exit $status, expected $want_status)"
        diff "$TMP/want" "$TMP/out" | sed 's/^/    /' | head -10
    fi
}

# check_err NAME STATUS EXPECTED_STDERR [ARGS...]: exact standard error, and
# nothing on standard output.
check_err() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    if [ "$status" -eq "$want_status" ] && cmp -s "$TMP/want" "$TMP/err" && [ ! -s "$TMP/out" ]; then
        ok
    else
        bad "$name (exit $status, expected $want_status)"
        diff "$TMP/want" "$TMP/err" | sed 's/^/    /' | head -10
    fi
}

# check_log NAME FILE EXPECTED: the file's exact bytes.
check_log() {
    printf '%s' "$3" > "$TMP/want"
    if cmp -s "$TMP/want" "$2"; then
        ok
    else
        fail=$((fail + 1))
        echo "FAIL: $1"
        diff "$TMP/want" "$2" | sed 's/^/    /' | head -10
    fi
}

# drop_bytes FILE N: cut the last N bytes off FILE, as a crash in the middle
# of a write would (portable: no `truncate -s -N`).
drop_bytes() {
    local size
    size=$(wc -c < "$1")
    head -c $((size - $2)) "$1" > "$1.cut" && mv "$1.cut" "$1"
}

try=$'Try \'kvstore --help\' for more information.\n'

# --- put, get, del, scan ---------------------------------------------------
DB=$TMP/data.kv
check "put"                0 ''                          -f "$DB" put user:1 'Ann Lee'
check "put 2"              0 ''                          -f "$DB" put user:2 Bob
check "put odd value"      0 ''                          -f "$DB" put note $'two words\n100% café'
check "get"                0 $'Ann Lee\n'                -f "$DB" get user:1
check "get odd value"      0 $'two words\n100% café\n'   -f "$DB" get note
check "scan all"           0 $'note\ttwo words\n100% café\nuser:1\tAnn Lee\nuser:2\tBob\n'  -f "$DB" scan
check "scan prefix"        0 $'user:1\tAnn Lee\nuser:2\tBob\n'   -f "$DB" scan user:
check "scan no match"      0 ''                          -f "$DB" scan zzz
check "del"                0 ''                          -f "$DB" del user:2
check_err "get deleted"    1 $'kvstore: user:2: not found\n'      -f "$DB" get user:2
check_err "del twice"      1 $'kvstore: user:2: not found\n'      -f "$DB" del user:2
check_log "log format" "$DB" 'KVSTORE 1
128105d1 P user:1 Ann%20Lee
17758304 P user:2 Bob
a9d52b1c P note two%20words%0A100%25%20caf%C3%A9
54261879 D user:2
'
check "--file= and option after command"  0 $'Ann Lee\n'  get user:1 --file="$DB"
check "value after --"     0 ''                          -f "$DB" put -- neg -5
check "get negative"       0 $'-5\n'                     -f "$DB" get neg
check "empty value"        0 ''                          -f "$DB" put empty ''
check "get empty value"    0 $'\n'                       -f "$DB" get empty

# --- stats and compact ----------------------------------------------------
check "stats" 0 "file:          $DB
size:          163 bytes
records:       6 (5 puts, 1 delete)
live keys:     4
stale records: 2
torn tail:     0 bytes
" -f "$DB" stats
check "compact" 0 "compacted $DB: 6 records, 163 bytes -> 4 records, 123 bytes
" -f "$DB" compact
# The empty value leaves a trailing space after the key.
check_log "compacted log" "$DB" $'KVSTORE 1\n3b76ba41 P empty \n74b094b2 P neg -5\na9d52b1c P note two%20words%0A100%25%20caf%C3%A9\n128105d1 P user:1 Ann%20Lee\n'
[ ! -e "$DB.compact" ] && ok || bad "no temporary file left behind"
check "get after compact"  0 $'Ann Lee\n'                -f "$DB" get user:1

# --- KVSTORE_FILE ----------------------------------------------------------
export KVSTORE_FILE=$DB
check "KVSTORE_FILE"       0 $'-5\n'                     get neg
check "--file wins"        1 ''                          -f "$TMP/other.kv" get neg
unset KVSTORE_FILE
check_err "no data file"   2 $'kvstore: no data file: use --file FILE or set KVSTORE_FILE\n'"$try"  get neg

# --- missing file ----------------------------------------------------------
NEW=$TMP/new.kv
check_err "get from a missing file"  1 $'kvstore: k: not found\n'  -f "$NEW" get k
check "scan a missing file"  0 ''                        -f "$NEW" scan
[ ! -e "$NEW" ] && ok || bad "reading does not create the file"
check "first put creates"  0 ''                          -f "$NEW" put a 1
check_log "new log" "$NEW" 'KVSTORE 1
d34c1267 P a 1
'

# --- crash safety: a torn last record ----------------------------------------
LOG=$TMP/torn.kv
for kv in "a 1" "b 2" "c 3"; do
    set -- $kv
    "$BIN" -f "$LOG" put "$1" "$2"
done
drop_bytes "$LOG" 4
check "torn record is invisible"    0 $'a\t1\nb\t2\n'    -f "$LOG" scan
check_err "torn key not found"      1 $'kvstore: c: not found\n'  -f "$LOG" get c
check "stats shows the torn tail" 0 "file:          $LOG
size:          51 bytes
records:       2 (2 puts, 0 deletes)
live keys:     2
stale records: 0
torn tail:     11 bytes
" -f "$LOG" stats
check_log "readers leave the file alone" "$LOG" $'KVSTORE 1\nd34c1267 P a 1\n4803fd84 P b 2\n3ec6a725 P '
check_err "a write cuts the torn tail"  0 "kvstore: $LOG: dropped a torn tail of 11 bytes
"  -f "$LOG" put d 4
check_log "repaired log" "$LOG" 'KVSTORE 1
d34c1267 P a 1
4803fd84 P b 2
a5ed2403 P d 4
'

# --- crash safety: a corrupt checksum and a record without its newline -------
sed 's/a5ed2403 P d 4/a5ed2403 P d 5/' "$LOG" > "$LOG.x" && mv "$LOG.x" "$LOG"
check "corrupt record is skipped"   0 $'a\t1\nb\t2\n'    -f "$LOG" scan
check_err "corrupt record cut"      0 "kvstore: $LOG: dropped a torn tail of 15 bytes
"  -f "$LOG" put e 5
drop_bytes "$LOG" 1
check_err "record without newline"  1 $'kvstore: e: not found\n'  -f "$LOG" get e

HDR=$TMP/header.kv
printf 'KVST' > "$HDR"
check_err "torn header"   0 "kvstore: $HDR: dropped a torn tail of 4 bytes
"  -f "$HDR" put a 1
check_log "header rewritten" "$HDR" 'KVSTORE 1
d34c1267 P a 1
'

# --- a file that is not a log is refused and left alone ----------------------
FOREIGN=$TMP/notes.txt
printf 'shopping list\nmilk\n' > "$FOREIGN"
cp "$FOREIGN" "$TMP/notes.orig"
check_err "foreign file: put"  2 "kvstore: $FOREIGN: not a kvstore log
"  -f "$FOREIGN" put a 1
check_err "foreign file: get"  2 "kvstore: $FOREIGN: not a kvstore log
"  -f "$FOREIGN" get a
cmp -s "$FOREIGN" "$TMP/notes.orig" && ok || bad "foreign file unchanged"

# --- command line ------------------------------------------------------------
check "version"   0 $'kvstore (loup-cmd-kvstore) 0.1.0\n'  --version
run --help
[ "$status" -eq 0 ] && [ "$(head -1 "$TMP/out")" = "usage: kvstore [OPTIONS] COMMAND [ARGS...]" ] && ok || bad "--help"
run help
[ "$status" -eq 0 ] && [ "$(head -1 "$TMP/out")" = "usage: kvstore [OPTIONS] COMMAND [ARGS...]" ] && ok || bad "help command"
check_err "no command"       2 $'kvstore: no command given\n'"$try"
check_err "unknown command"  2 $'kvstore: unknown command \'frob\'\n'"$try"          -f "$DB" frob
check_err "put needs value"  2 $'kvstore: \'put\' takes KEY VALUE\n'"$try"         -f "$DB" put k
check_err "get needs key"    2 $'kvstore: \'get\' takes KEY\n'"$try"               -f "$DB" get
check_err "stats operands"   2 $'kvstore: \'stats\' takes no operands\n'"$try"     -f "$DB" stats x
check_err "empty key"        2 $'kvstore: the key is empty\n'"$try"                -f "$DB" put '' v
check_err "unknown option"   2 $'kvstore: unrecognized option \'--bogus\'\n'"$try" --bogus get k
check_err "dash value"       2 $'kvstore: unrecognized option \'-5\'\n'"$try"      -f "$DB" put k -5
check_err "missing file"     2 $'kvstore: option \'--file\' requires an argument\n'"$try"  get k --file

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
