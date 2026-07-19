#!/usr/bin/env bash
set -u

LLVM_ROOT=$1
START_SEED=$2
CASE_COUNT=$3
RESULT_ROOT=$4

OPT="$LLVM_ROOT/bin/opt"
LLC="$LLVM_ROOT/bin/llc"
STRESS="$LLVM_ROOT/bin/llvm-stress"

test -x "$OPT"
test -x "$LLC"
test -x "$STRESS"

mkdir -p "$RESULT_ROOT/candidate" "$RESULT_ROOT/work"
ulimit -c 0

status=no-failure
last_seed=$START_SEED
generated_count=0
verified_count=0
generation_fail_count=0
preverify_fail_count=0

for ((offset = 0; offset < CASE_COUNT; offset++)); do
  seed=$((START_SEED + offset))
  last_seed=$seed
  rm -f "$RESULT_ROOT/work"/*

  if ! timeout 5 "$STRESS" -seed="$seed" -size=250 \
      >"$RESULT_ROOT/work/test.ll" 2>"$RESULT_ROOT/work/stress.log"; then
    generation_fail_count=$((generation_fail_count + 1))
    continue
  fi
  generated_count=$((generated_count + 1))

  if ! timeout 5 "$OPT" -passes=verify -disable-output \
      "$RESULT_ROOT/work/test.ll" >"$RESULT_ROOT/work/verify.log" 2>&1; then
    preverify_fail_count=$((preverify_fail_count + 1))
    continue
  fi
  verified_count=$((verified_count + 1))

  timeout 15 "$LLC" -O2 -filetype=null -o /dev/null \
    "$RESULT_ROOT/work/test.ll" >"$RESULT_ROOT/work/llc.log" 2>&1
  llc_status=$?
  if [[ "$llc_status" -eq 0 ]]; then
    continue
  elif [[ "$llc_status" -eq 124 ]]; then
    status=llc-timeout
  else
    status=llc-failure
  fi

  cp "$RESULT_ROOT/work/test.ll" "$RESULT_ROOT/candidate/test.ll"
  cp "$RESULT_ROOT/work/stress.log" "$RESULT_ROOT/candidate/stress.log"
  cp "$RESULT_ROOT/work/verify.log" "$RESULT_ROOT/candidate/verify.log"
  cp "$RESULT_ROOT/work/llc.log" "$RESULT_ROOT/candidate/llc.log"
  break
done

if [[ "$status" == no-failure && "$verified_count" -eq 0 ]]; then
  status=no-valid-cases
fi

cat >"$RESULT_ROOT/summary.txt" <<EOF
status=$status
start_seed=$START_SEED
last_seed=$last_seed
case_count=$CASE_COUNT
generated_count=$generated_count
verified_count=$verified_count
generation_fail_count=$generation_fail_count
preverify_fail_count=$preverify_fail_count
llvm_revision=$(cat "$LLVM_ROOT/revision.txt")
llc_version=$(head -n 1 "$LLVM_ROOT/clang-version.txt")
EOF

printf '%s\n' "$status"

if [[ "$status" == no-valid-cases ]]; then
  exit 2
fi
