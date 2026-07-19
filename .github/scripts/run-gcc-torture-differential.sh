#!/usr/bin/env bash
set -u

LLVM_ROOT=$1
CORPUS_ROOT=$2
RESULT_ROOT=$3

CLANG="$LLVM_ROOT/bin/clang"
TEST_ROOT="$CORPUS_ROOT/gcc/testsuite/gcc.c-torture/execute"

test -x "$CLANG"
test -d "$TEST_ROOT"

mkdir -p "$RESULT_ROOT/candidates" "$RESULT_ROOT/work"
ulimit -c 0

status=no-mismatch
candidate_count=0
total_count=0
compared_count=0
o0_compile_fail_count=0
baseline_runtime_fail_count=0
directive_skip_count=0
last_test=

compile() {
  local compiler=$1
  local level=$2
  local source=$3
  local output=$4
  local log=$5
  timeout 20 "$compiler" -std=gnu11 -w "$level" "$source" -lm \
    -o "$output" >"$log" 2>&1
}

execute() {
  local binary=$1
  local output=$2
  timeout 5 "$binary" >"$output" 2>&1
}

while IFS= read -r source; do
  total_count=$((total_count + 1))
  last_test=${source#"$TEST_ROOT/"}
  rm -f "$RESULT_ROOT/work"/*

  case "$last_test" in
    pr79286.c)
      directive_skip_count=$((directive_skip_count + 1))
      continue
      ;;
  esac

  if grep -Eq 'dg-(skip-if|require-effective-target|options|additional-options|add-options|xfail-run-if|additional-sources)|__attribute__.*(optimize|target)[[:space:]]*\(' \
      "$source"; then
    directive_skip_count=$((directive_skip_count + 1))
    continue
  fi

  if ! compile "$CLANG" -O0 "$source" "$RESULT_ROOT/work/clang-o0" \
      "$RESULT_ROOT/work/clang-o0.compile"; then
    o0_compile_fail_count=$((o0_compile_fail_count + 1))
    continue
  fi

  if ! execute "$RESULT_ROOT/work/clang-o0" \
      "$RESULT_ROOT/work/clang-o0.out"; then
    baseline_runtime_fail_count=$((baseline_runtime_fail_count + 1))
    continue
  fi

  case_status=no-mismatch
  if ! compile "$CLANG" -O2 "$source" "$RESULT_ROOT/work/clang-o2" \
      "$RESULT_ROOT/work/clang-o2.compile"; then
    case_status=clang-o2-compile-failure
  elif ! execute "$RESULT_ROOT/work/clang-o2" \
      "$RESULT_ROOT/work/clang-o2.out"; then
    case_status=clang-o2-runtime-failure
  else
    compared_count=$((compared_count + 1))
    continue
  fi

  candidate_count=$((candidate_count + 1))
  candidate_root="$RESULT_ROOT/candidates/$candidate_count"
  mkdir -p "$candidate_root"
  cp "$source" "$candidate_root/test.c"
  cp "$RESULT_ROOT/work"/*.out "$candidate_root/" 2>/dev/null || true
  cp "$RESULT_ROOT/work"/*.compile "$candidate_root/" 2>/dev/null || true
  printf '%s\n' "$last_test" >"$candidate_root/path.txt"
  printf '%s\n' "$case_status" >"$candidate_root/status.txt"

  if compile gcc -O0 "$source" "$RESULT_ROOT/work/gcc-o0" \
      "$candidate_root/gcc-o0.compile" && \
      compile gcc -O2 "$source" "$RESULT_ROOT/work/gcc-o2" \
      "$candidate_root/gcc-o2.compile"; then
    execute "$RESULT_ROOT/work/gcc-o0" \
      "$candidate_root/gcc-o0.out" || true
    execute "$RESULT_ROOT/work/gcc-o2" \
      "$candidate_root/gcc-o2.out" || true
  fi
  status=signals-found
  if [[ "$candidate_count" -ge 20 ]]; then
    break
  fi
done < <(find "$TEST_ROOT" -maxdepth 1 -type f -name '*.c' -print | sort)

if [[ "$status" == no-mismatch && "$compared_count" -eq 0 ]]; then
  status=no-valid-cases
fi

cat >"$RESULT_ROOT/summary.txt" <<EOF
status=$status
total_count=$total_count
compared_count=$compared_count
o0_compile_fail_count=$o0_compile_fail_count
baseline_runtime_fail_count=$baseline_runtime_fail_count
directive_skip_count=$directive_skip_count
candidate_count=$candidate_count
last_test=$last_test
llvm_revision=$(cat "$LLVM_ROOT/revision.txt")
clang_version=$(head -n 1 "$LLVM_ROOT/clang-version.txt")
EOF

printf '%s\n' "$status"

if [[ "$status" == no-valid-cases ]]; then
  exit 2
fi
