#!/usr/bin/env bash
set -u

LLVM_ROOT=$1
CSMITH_ROOT=$2
START_SEED=$3
CASE_COUNT=$4
RESULT_ROOT=$5

CLANG="$LLVM_ROOT/bin/clang"
CSMITH="$CSMITH_ROOT/bin/csmith"
CSMITH_INCLUDE=$(find "$CSMITH_ROOT/include" -name csmith.h -printf '%h\n' -quit)
TARGET_FLAG=-march=x86-64-v3

test -x "$CLANG"
test -x "$CSMITH"
test -n "$CSMITH_INCLUDE"

mkdir -p "$RESULT_ROOT/candidate" "$RESULT_ROOT/work"
ulimit -c 0

status=no-mismatch
last_seed=$START_SEED
generated_count=0
compared_count=0
generation_fail_count=0
o0_compile_fail_count=0
baseline_runtime_fail_count=0

compile() {
  local compiler=$1
  local level=$2
  local output=$3
  local log=$4
  timeout 20 "$compiler" -std=c11 -w "$level" "$TARGET_FLAG" \
    -I "$CSMITH_INCLUDE" "$RESULT_ROOT/work/test.c" -o "$output" \
    >"$log" 2>&1
}

execute() {
  local binary=$1
  local output=$2
  timeout 5 "$binary" >"$output" 2>&1
}

for ((offset = 0; offset < CASE_COUNT; offset++)); do
  seed=$((START_SEED + offset))
  last_seed=$seed
  rm -f "$RESULT_ROOT/work"/*

  if ! timeout 10 "$CSMITH" --seed "$seed" --no-packed-struct \
      --max-funcs 5 --max-block-depth 5 --max-expr-complexity 20 \
      --output "$RESULT_ROOT/work/test.c"; then
    generation_fail_count=$((generation_fail_count + 1))
    continue
  fi
  generated_count=$((generated_count + 1))

  if ! compile "$CLANG" -O0 "$RESULT_ROOT/work/clang-o0" \
      "$RESULT_ROOT/work/clang-o0.compile"; then
    o0_compile_fail_count=$((o0_compile_fail_count + 1))
    continue
  fi

  if ! compile "$CLANG" -O2 "$RESULT_ROOT/work/clang-o2" \
      "$RESULT_ROOT/work/clang-o2.compile"; then
    status=clang-o2-compile-failure
  elif ! execute "$RESULT_ROOT/work/clang-o0" "$RESULT_ROOT/work/clang-o0.out"; then
    baseline_runtime_fail_count=$((baseline_runtime_fail_count + 1))
    continue
  elif ! execute "$RESULT_ROOT/work/clang-o2" "$RESULT_ROOT/work/clang-o2.out"; then
    status=clang-o2-runtime-failure
  elif ! cmp -s "$RESULT_ROOT/work/clang-o0.out" "$RESULT_ROOT/work/clang-o2.out"; then
    status=clang-o2-output-mismatch
  else
    compared_count=$((compared_count + 1))
    continue
  fi

  cp "$RESULT_ROOT/work/test.c" "$RESULT_ROOT/candidate/test.c"
  cp "$RESULT_ROOT/work"/*.out "$RESULT_ROOT/candidate/" 2>/dev/null || true
  cp "$RESULT_ROOT/work"/*.compile "$RESULT_ROOT/candidate/" 2>/dev/null || true

  if compile gcc -O0 "$RESULT_ROOT/work/gcc-o0" "$RESULT_ROOT/work/gcc-o0.compile" && \
      compile gcc -O2 "$RESULT_ROOT/work/gcc-o2" "$RESULT_ROOT/work/gcc-o2.compile"; then
    execute "$RESULT_ROOT/work/gcc-o0" "$RESULT_ROOT/candidate/gcc-o0.out" || true
    execute "$RESULT_ROOT/work/gcc-o2" "$RESULT_ROOT/candidate/gcc-o2.out" || true
  fi

  compile "$CLANG" -O1 "$RESULT_ROOT/work/clang-o1" \
    "$RESULT_ROOT/candidate/clang-o1.compile" || true
  compile "$CLANG" -O3 "$RESULT_ROOT/work/clang-o3" \
    "$RESULT_ROOT/candidate/clang-o3.compile" || true
  execute "$RESULT_ROOT/work/clang-o1" "$RESULT_ROOT/candidate/clang-o1.out" || true
  execute "$RESULT_ROOT/work/clang-o3" "$RESULT_ROOT/candidate/clang-o3.out" || true

  break
done

if [[ "$status" == no-mismatch && "$compared_count" -eq 0 ]]; then
  status=no-valid-cases
fi

cat >"$RESULT_ROOT/summary.txt" <<EOF
status=$status
target_flag=$TARGET_FLAG
start_seed=$START_SEED
last_seed=$last_seed
case_count=$CASE_COUNT
generated_count=$generated_count
compared_count=$compared_count
generation_fail_count=$generation_fail_count
o0_compile_fail_count=$o0_compile_fail_count
baseline_runtime_fail_count=$baseline_runtime_fail_count
llvm_revision=$(cat "$LLVM_ROOT/revision.txt")
clang_version=$(head -n 1 "$LLVM_ROOT/clang-version.txt")
EOF

printf '%s\n' "$status"

if [[ "$status" == no-valid-cases ]]; then
  exit 2
fi
