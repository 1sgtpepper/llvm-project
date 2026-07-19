#!/usr/bin/env bash
set -u

LLVM_ROOT=$1
CSMITH_ROOT=$2
START_SEED=$3
CASE_COUNT=$4
RESULT_ROOT=$5

OPT="$LLVM_ROOT/bin/opt"
LLI="$LLVM_ROOT/bin/lli"
CSMITH="$CSMITH_ROOT/bin/csmith"
CSMITH_INCLUDE=$(find "$CSMITH_ROOT/include" -name csmith.h -printf '%h\n' -quit)

test -x "$OPT"
test -x "$LLI"
test -x "$CSMITH"
test -n "$CSMITH_INCLUDE"
command -v clang >/dev/null

mkdir -p "$RESULT_ROOT/candidate" "$RESULT_ROOT/work"
ulimit -c 0

status=no-mismatch
last_seed=$START_SEED

for ((offset = 0; offset < CASE_COUNT; offset++)); do
  seed=$((START_SEED + offset))
  last_seed=$seed
  rm -f "$RESULT_ROOT/work"/*

  if ! timeout 10 "$CSMITH" --seed "$seed" --no-packed-struct \
      --max-funcs 5 --max-block-depth 5 --max-expr-complexity 20 \
      --output "$RESULT_ROOT/work/test.c"; then
    continue
  fi

  if ! timeout 20 clang -std=c11 -w -O0 -Xclang -disable-O0-optnone \
      -emit-llvm -c -I "$CSMITH_INCLUDE" "$RESULT_ROOT/work/test.c" \
      -o "$RESULT_ROOT/work/input.bc" \
      >"$RESULT_ROOT/work/frontend.compile" 2>&1; then
    continue
  fi

  if ! timeout 5 "$LLI" "$RESULT_ROOT/work/input.bc" \
      >"$RESULT_ROOT/work/baseline.out" 2>&1; then
    continue
  fi

  if ! timeout 20 "$OPT" -passes='default<O2>' \
      "$RESULT_ROOT/work/input.bc" -o "$RESULT_ROOT/work/optimized.bc" \
      >"$RESULT_ROOT/work/opt-o2.log" 2>&1; then
    status=opt-o2-failure
  elif ! timeout 5 "$LLI" "$RESULT_ROOT/work/optimized.bc" \
      >"$RESULT_ROOT/work/optimized.out" 2>&1; then
    status=opt-o2-runtime-failure
  elif ! cmp -s "$RESULT_ROOT/work/baseline.out" \
      "$RESULT_ROOT/work/optimized.out"; then
    status=opt-o2-output-mismatch
  else
    continue
  fi

  cp "$RESULT_ROOT/work/test.c" "$RESULT_ROOT/candidate/"
  cp "$RESULT_ROOT/work/input.bc" "$RESULT_ROOT/candidate/"
  cp "$RESULT_ROOT/work/optimized.bc" "$RESULT_ROOT/candidate/" 2>/dev/null || true
  cp "$RESULT_ROOT/work"/*.out "$RESULT_ROOT/candidate/" 2>/dev/null || true
  cp "$RESULT_ROOT/work"/*.log "$RESULT_ROOT/candidate/" 2>/dev/null || true
  cp "$RESULT_ROOT/work"/*.compile "$RESULT_ROOT/candidate/" 2>/dev/null || true
  break
done

cat >"$RESULT_ROOT/summary.txt" <<EOF
status=$status
start_seed=$START_SEED
last_seed=$last_seed
case_count=$CASE_COUNT
llvm_revision=$(cat "$LLVM_ROOT/revision.txt")
frontend_version=$(clang --version | head -n 1)
csmith_revision=0cdc710315cfee9035e22ef4363ca479270d1934
EOF

printf '%s\n' "$status"
