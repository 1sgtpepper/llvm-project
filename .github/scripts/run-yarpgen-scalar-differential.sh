#!/usr/bin/env bash
set -u

LLVM_ROOT=$1
YARPGEN_ROOT=$2
START_SEED=$3
CASE_COUNT=$4
RESULT_ROOT=$5

CLANG="$LLVM_ROOT/bin/clang"
YARPGEN="$YARPGEN_ROOT/bin/yarpgen"

test -x "$CLANG"
test -x "$YARPGEN"

mkdir -p "$RESULT_ROOT/candidate" "$RESULT_ROOT/work"
ulimit -c 0

status=no-mismatch
last_seed=$START_SEED
generated_count=0
compared_count=0
generation_fail_count=0
o0_compile_fail_count=0
baseline_runtime_fail_count=0
oversize_count=0
o2_compile_timeout_count=0

compile() {
  local compiler=$1
  local level=$2
  local output=$3
  local log=$4
  shift 4
  timeout 30 "$compiler" "$@" -std=c++17 -w "$level" \
    "$RESULT_ROOT/work/driver.cpp" "$RESULT_ROOT/work/func.cpp" \
    -o "$output" >"$log" 2>&1
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

  if ! timeout 20 "$YARPGEN" --seed="$seed" --std=c++17 \
      --out-dir="$RESULT_ROOT/work"; then
    generation_fail_count=$((generation_fail_count + 1))
    continue
  fi
  generated_count=$((generated_count + 1))

  source_bytes=$(wc -c "$RESULT_ROOT/work/driver.cpp" \
    "$RESULT_ROOT/work/func.cpp" "$RESULT_ROOT/work/init.h" | \
    awk 'END { print $1 }')
  if [[ "$source_bytes" -gt 2000000 ]]; then
    oversize_count=$((oversize_count + 1))
    continue
  fi

  if ! compile "$CLANG" -O0 "$RESULT_ROOT/work/clang-o0" \
      "$RESULT_ROOT/work/clang-o0.compile" --driver-mode=g++; then
    o0_compile_fail_count=$((o0_compile_fail_count + 1))
    continue
  fi

  compile "$CLANG" -O2 "$RESULT_ROOT/work/clang-o2" \
    "$RESULT_ROOT/work/clang-o2.compile" --driver-mode=g++
  o2_compile_status=$?
  if [[ "$o2_compile_status" -eq 124 ]]; then
    o2_compile_timeout_count=$((o2_compile_timeout_count + 1))
    continue
  elif [[ "$o2_compile_status" -ne 0 ]]; then
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

  cp "$RESULT_ROOT/work/init.h" "$RESULT_ROOT/candidate/"
  cp "$RESULT_ROOT/work/driver.cpp" "$RESULT_ROOT/candidate/"
  cp "$RESULT_ROOT/work/func.cpp" "$RESULT_ROOT/candidate/"
  cp "$RESULT_ROOT/work"/*.out "$RESULT_ROOT/candidate/" 2>/dev/null || true
  cp "$RESULT_ROOT/work"/*.compile "$RESULT_ROOT/candidate/" 2>/dev/null || true

  if compile g++ -O0 "$RESULT_ROOT/work/gcc-o0" \
      "$RESULT_ROOT/work/gcc-o0.compile" && \
      compile g++ -O2 "$RESULT_ROOT/work/gcc-o2" \
      "$RESULT_ROOT/work/gcc-o2.compile"; then
    execute "$RESULT_ROOT/work/gcc-o0" "$RESULT_ROOT/candidate/gcc-o0.out" || true
    execute "$RESULT_ROOT/work/gcc-o2" "$RESULT_ROOT/candidate/gcc-o2.out" || true
  fi

  compile "$CLANG" -O1 "$RESULT_ROOT/work/clang-o1" \
    "$RESULT_ROOT/candidate/clang-o1.compile" --driver-mode=g++ || true
  compile "$CLANG" -O3 "$RESULT_ROOT/work/clang-o3" \
    "$RESULT_ROOT/candidate/clang-o3.compile" --driver-mode=g++ || true
  execute "$RESULT_ROOT/work/clang-o1" "$RESULT_ROOT/candidate/clang-o1.out" || true
  execute "$RESULT_ROOT/work/clang-o3" "$RESULT_ROOT/candidate/clang-o3.out" || true
  break
done

if [[ "$status" == no-mismatch && "$compared_count" -eq 0 ]]; then
  status=no-valid-cases
fi

cat >"$RESULT_ROOT/summary.txt" <<EOF
status=$status
start_seed=$START_SEED
last_seed=$last_seed
case_count=$CASE_COUNT
generated_count=$generated_count
compared_count=$compared_count
generation_fail_count=$generation_fail_count
o0_compile_fail_count=$o0_compile_fail_count
baseline_runtime_fail_count=$baseline_runtime_fail_count
oversize_count=$oversize_count
o2_compile_timeout_count=$o2_compile_timeout_count
llvm_revision=$(cat "$LLVM_ROOT/revision.txt")
clang_version=$(head -n 1 "$LLVM_ROOT/clang-version.txt")
yarpgen_revision=$(cat "$YARPGEN_ROOT/revision.txt")
EOF

printf '%s\n' "$status"

if [[ "$status" == no-valid-cases ]]; then
  exit 2
fi
