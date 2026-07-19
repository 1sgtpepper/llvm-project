#!/usr/bin/env bash
set -euo pipefail

LLVM_ROOT=$1
SOURCE=$2
RESULT_ROOT=$3
CLANG="$LLVM_ROOT/bin/clang"
SYSTEM_CLANG=$(command -v clang)
CROSS_GCC=aarch64-linux-gnu-gcc
QEMU=qemu-aarch64
DIRECTED_ROOT="$RESULT_ROOT/directed"

mkdir -p "$DIRECTED_ROOT"
test -x "$CLANG"
test -x "$SYSTEM_CLANG"
test -f "$SOURCE"
command -v gcc >/dev/null
command -v "$CROSS_GCC" >/dev/null
command -v "$QEMU" >/dev/null

compile_native() {
  local compiler=$1
  local level=$2
  local stem=$3
  timeout 45 "$compiler" -std=c11 -Wall -Wextra -Werror "$level" \
    "$SOURCE" -o "$DIRECTED_ROOT/$stem" \
    >"$DIRECTED_ROOT/$stem.compile" 2>&1
}

compile_cross_gcc() {
  local level=$1
  local stem=$2
  timeout 45 "$CROSS_GCC" -std=c11 -Wall -Wextra -Werror "$level" -static \
    "$SOURCE" -o "$DIRECTED_ROOT/$stem" \
    >"$DIRECTED_ROOT/$stem.compile" 2>&1
}

compile_cross_clang() {
  local level=$1
  local stem=$2
  timeout 45 "$CLANG" --target=aarch64-linux-gnu --gcc-toolchain=/usr \
    -std=c11 -Wall -Wextra -Werror "$level" -c "$SOURCE" \
    -o "$DIRECTED_ROOT/$stem.o" \
    >"$DIRECTED_ROOT/$stem.compile" 2>&1
  timeout 20 "$CROSS_GCC" -static "$DIRECTED_ROOT/$stem.o" \
    -o "$DIRECTED_ROOT/$stem" \
    >"$DIRECTED_ROOT/$stem.link" 2>&1
}

execute_native() {
  local stem=$1
  timeout 10 "$DIRECTED_ROOT/$stem" \
    >"$DIRECTED_ROOT/$stem.out" 2>"$DIRECTED_ROOT/$stem.err"
}

execute_aarch64() {
  local stem=$1
  timeout 15 "$QEMU" "$DIRECTED_ROOT/$stem" \
    >"$DIRECTED_ROOT/$stem.out" 2>"$DIRECTED_ROOT/$stem.err"
}

compile_native "$SYSTEM_CLANG" -O0 oracle-clang-o0
compile_native "$SYSTEM_CLANG" -O2 oracle-clang-o2
compile_native gcc -O0 native-gcc-o0
compile_native gcc -O2 native-gcc-o2
compile_native "$CLANG" -O0 current-clang-o0
compile_native "$CLANG" -O2 current-clang-o2
compile_cross_gcc -O0 aarch64-gcc-o0
compile_cross_gcc -O2 aarch64-gcc-o2
compile_cross_clang -O0 aarch64-clang-o0
compile_cross_clang -O2 aarch64-clang-o2

execute_native oracle-clang-o0
execute_native oracle-clang-o2
execute_native native-gcc-o0
execute_native native-gcc-o2
execute_native current-clang-o0
execute_native current-clang-o2
execute_aarch64 aarch64-gcc-o0
execute_aarch64 aarch64-gcc-o2
execute_aarch64 aarch64-clang-o0
execute_aarch64 aarch64-clang-o2

expected="$DIRECTED_ROOT/oracle-clang-o0.out"
status=all-oracles-agree
if test -s "$DIRECTED_ROOT/oracle-clang-o0.err"; then
  status=oracle-mismatch
fi
for stem in oracle-clang-o2 native-gcc-o0 native-gcc-o2 \
    current-clang-o0 current-clang-o2 \
    aarch64-gcc-o0 aarch64-gcc-o2 aarch64-clang-o0 aarch64-clang-o2; do
  if ! cmp -s "$expected" "$DIRECTED_ROOT/$stem.out" || \
      test -s "$DIRECTED_ROOT/$stem.err"; then
    status=oracle-mismatch
  fi
done

timeout 45 "$CLANG" --target=aarch64-linux-gnu --gcc-toolchain=/usr \
  -std=c11 -O2 -S -emit-llvm "$SOURCE" \
  -o "$DIRECTED_ROOT/aarch64-clang-o2.ll"
timeout 45 "$CLANG" --target=aarch64-linux-gnu --gcc-toolchain=/usr \
  -std=c11 -O2 -S "$SOURCE" -o "$DIRECTED_ROOT/aarch64-clang-o2.s"
timeout 45 "$CROSS_GCC" -std=c11 -O2 -S "$SOURCE" \
  -o "$DIRECTED_ROOT/aarch64-gcc-o2.s"

cp "$SOURCE" "$DIRECTED_ROOT/reproducer.c"
sha256sum "$DIRECTED_ROOT"/* >"$DIRECTED_ROOT/sha256sums.txt"
printf 'status=%s\nexpected_output=%s\n' \
  "$status" "$(tr -d '\n' <"$expected")" | tee "$DIRECTED_ROOT/summary.txt"

test "$status" = all-oracles-agree
