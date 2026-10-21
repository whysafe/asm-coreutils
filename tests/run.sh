#!/usr/bin/env bash
# Integration tests: every case runs twice, once with bin/ first in PATH (our
# tools) and once with the system tools (GNU coreutils, util-linux), and the
# outputs must match byte for byte.
set -u
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin"
DATA="$ROOT/tests/data"
GEN=$(mktemp -d)
export GEN
trap 'rm -rf "$GEN"' EXIT

pass=0
fail=0

# Generated inputs: binary data, repeated lines, buffer-boundary sizes.
printf '\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f' > "$GEN/b16"
for hi in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do
    for lo in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do
        printf "\\x$hi$lo"
    done
done > "$GEN/all256.bin"
head -c 100 /dev/zero > "$GEN/zeros100.bin"
head -c 64 /dev/zero | tr '\0' 'A' > "$GEN/a64.bin"
{ head -c 48 /dev/zero; printf 'tail'; head -c 32 /dev/zero; printf 'end'; } > "$GEN/dups.bin"
head -c 150000 /dev/urandom > "$GEN/random.bin"
seq 1 40000 > "$GEN/big.txt"
seq -s, 1 60000 > "$GEN/longline.txt"
printf '  \t lead  and trail \t \n\n\v\f word\r\nlast' > "$GEN/spaces.txt"

# run NAME CMD [stderr]: compares stdout and exit status (and stderr if asked)
run() {
    local name=$1 cmd=$2 check_err=${3:-}
    (cd "$DATA" && PATH="$BIN:$PATH" bash -c "$cmd") > "$GEN/our.out" 2> "$GEN/our.err"
    local our_status=$?
    (cd "$DATA" && bash -c "$cmd") > "$GEN/ref.out" 2> "$GEN/ref.err"
    local ref_status=$?
    local ok=1
    cmp -s "$GEN/our.out" "$GEN/ref.out" || ok=0
    [ "$our_status" -eq "$ref_status" ] || ok=0
    if [ -n "$check_err" ]; then
        cmp -s "$GEN/our.err" "$GEN/ref.err" || ok=0
    fi
    if [ $ok -eq 1 ]; then
        pass=$((pass + 1))
        echo "ok    $name"
    else
        fail=$((fail + 1))
        echo "FAIL  $name   ($cmd)"
        echo "      status: ours=$our_status reference=$ref_status"
        diff <(od -c "$GEN/ref.out") <(od -c "$GEN/our.out") | head -20 | sed 's/^/      /'
        if [ -n "$check_err" ]; then
            diff "$GEN/ref.err" "$GEN/our.err" | sed 's/^/      /'
        fi
    fi
}

# The binaries must be static and free of libc.
for prog in cat wc hexdump rev; do
    if readelf -l "$BIN/$prog" | grep -q INTERP || readelf -d "$BIN/$prog" 2>/dev/null | grep -q NEEDED; then
        fail=$((fail + 1)); echo "FAIL  $prog is dynamically linked"
    else
        pass=$((pass + 1)); echo "ok    $prog is static, no libc"
    fi
done

run "cat one file"          'cat hello.txt'
run "cat several files"     'cat hello.txt poem.txt nonl.txt hello.txt'
run "cat empty file"        'cat empty.txt'
run "cat stdin redirect"    'cat < poem.txt'
run "cat stdin dash"        'printf "piped\nno newline" | cat hello.txt - nonl.txt'
run "cat binary"            'cat "$GEN/all256.bin" "$GEN/random.bin"'
run "cat big file"          'cat "$GEN/big.txt"'
run "cat -n"                'cat -n poem.txt'
run "cat -n across files"   'cat -n nonl.txt hello.txt poem.txt'
run "cat -n big file"       'cat -n "$GEN/big.txt"'
run "cat missing file"      'cat hello.txt nosuch.txt poem.txt' stderr

run "wc one file"           'wc poem.txt'
run "wc several files"      'wc poem.txt hello.txt nonl.txt empty.txt'
run "wc -l"                 'wc -l poem.txt'
run "wc -w"                 'wc -w poem.txt'
run "wc -c"                 'wc -c poem.txt'
run "wc -lw"                'wc -lw poem.txt'
run "wc -c -l many"         'wc -c -l poem.txt nonl.txt'
run "wc empty file"         'wc empty.txt'
run "wc stdin redirect"     'wc < poem.txt'
run "wc -l stdin"           'wc -l < poem.txt'
run "wc stdin pipe"         'printf "one two\nthree" | wc'
run "wc -w stdin pipe"      'printf "  a  b\tc\n" | wc -w'
run "wc dash and file"      'wc - hello.txt < poem.txt'
run "wc whitespace kinds"   'wc "$GEN/spaces.txt"'
run "wc big files"          'wc "$GEN/big.txt" "$GEN/longline.txt" poem.txt'
run "wc -- end of options"  'wc -- poem.txt'
run "wc missing file"       'wc hello.txt nosuch.txt' stderr

run "hexdump text"          'hexdump -C hello.txt'
run "hexdump poem"          'hexdump -C poem.txt'
run "hexdump no newline"    'hexdump -C nonl.txt'
run "hexdump empty"         'hexdump -C empty.txt'
run "hexdump 16 bytes"      'hexdump -C "$GEN/b16"'
run "hexdump all bytes"     'hexdump -C "$GEN/all256.bin"'
run "hexdump zero run"      'hexdump -C "$GEN/zeros100.bin"'
run "hexdump repeat tail"   'hexdump -C "$GEN/a64.bin"'
run "hexdump repeat runs"   'hexdump -C "$GEN/dups.bin"'
run "hexdump random 150K"   'hexdump -C "$GEN/random.bin"'
run "hexdump many files"    'hexdump -C hello.txt nonl.txt poem.txt'
run "hexdump stdin"         'hexdump -C < poem.txt'
run "hexdump empty stdin"   'printf "" | hexdump -C'
run "hexdump missing file"  'hexdump -C hello.txt nosuch.txt'

run "rev one file"          'rev poem.txt'
run "rev no newline"        'rev nonl.txt'
run "rev empty"             'rev empty.txt'
run "rev several files"     'rev hello.txt nonl.txt poem.txt'
run "rev stdin"             'printf "abc\n\nxyz" | rev'
run "rev big file"          'rev "$GEN/big.txt"'
run "rev long line"         'rev "$GEN/longline.txt"'
run "rev missing file"      'rev hello.txt nosuch.txt'

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
