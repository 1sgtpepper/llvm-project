#!/usr/bin/env bash
set -u

LLVM_ROOT=$1
YARPGEN_ROOT=$2
START_SEED=$3
CASE_COUNT=$4
RESULT_ROOT=$5

CLANG="$LLVM_ROOT/bin/clang"
SYSTEM_CLANG=$(command -v clang)
YARPGEN="$YARPGEN_ROOT/bin/yarpgen"
CROSS_GXX=aarch64-linux-gnu-g++
QEMU=qemu-aarch64

test -x "$CLANG"
test -x "$SYSTEM_CLANG"
test -x "$YARPGEN"
command -v g++ >/dev/null
command -v "$CROSS_GXX" >/dev/null
command -v "$QEMU" >/dev/null

mkdir -p "$RESULT_ROOT/candidate" "$RESULT_ROOT/work"
cp "$LLVM_ROOT/provenance.txt" "$RESULT_ROOT/llvm-provenance.txt"
cp "$LLVM_ROOT/clang-version.txt" "$RESULT_ROOT/clang-version.txt"
cp "$LLVM_ROOT/llc-version.txt" "$RESULT_ROOT/llc-version.txt"
cp "$YARPGEN_ROOT/provenance.txt" "$RESULT_ROOT/yarpgen-provenance.txt"
ulimit -c 0

status=no-mismatch
last_seed=$START_SEED
generated_count=0
compared_count=0
generation_fail_count=0
oversize_count=0
native_compile_reject_count=0
native_runtime_reject_count=0
native_oracle_disagreement_count=0
current_native_compile_failure_count=0
current_native_runtime_failure_count=0
current_native_output_mismatch_count=0
cross_gcc_compile_reject_count=0
cross_gcc_runtime_reject_count=0
cross_target_oracle_disagreement_count=0
clang_aarch64_compile_failure_count=0
clang_aarch64_link_failure_count=0
clang_aarch64_runtime_failure_count=0
clang_aarch64_output_mismatch_count=0

compile_native() {
  local compiler=$1
  local level=$2
  local stem=$3
  local driver_mode=()
  if [[ "$compiler" == "$CLANG" || "$compiler" == "$SYSTEM_CLANG" ]]; then
    driver_mode=(--driver-mode=g++)
  fi
  timeout 45 "$compiler" "${driver_mode[@]}" -std=c++17 -w "$level" \
    "$RESULT_ROOT/work/driver.cpp" "$RESULT_ROOT/work/func.cpp" \
    -o "$RESULT_ROOT/work/$stem" \
    >"$RESULT_ROOT/work/$stem.compile" 2>&1
}

compile_cross_gcc() {
  local level=$1
  local stem=$2
  timeout 45 "$CROSS_GXX" -std=c++17 -w "$level" -static \
    "$RESULT_ROOT/work/driver.cpp" "$RESULT_ROOT/work/func.cpp" \
    -o "$RESULT_ROOT/work/$stem" \
    >"$RESULT_ROOT/work/$stem.compile" 2>&1
}

compile_cross_clang() {
  local level=$1
  local stem=$2
  if ! timeout 45 "$CLANG" --driver-mode=g++ --target=aarch64-linux-gnu \
      --gcc-toolchain=/usr -std=c++17 -w "$level" \
      -c "$RESULT_ROOT/work/driver.cpp" \
      -o "$RESULT_ROOT/work/$stem-driver.o" \
      >"$RESULT_ROOT/work/$stem-driver.compile" 2>&1; then
    return 1
  fi
  if ! timeout 45 "$CLANG" --driver-mode=g++ --target=aarch64-linux-gnu \
      --gcc-toolchain=/usr -std=c++17 -w "$level" \
      -c "$RESULT_ROOT/work/func.cpp" \
      -o "$RESULT_ROOT/work/$stem-func.o" \
      >"$RESULT_ROOT/work/$stem-func.compile" 2>&1; then
    return 1
  fi
  if ! timeout 20 "$CROSS_GXX" -static \
      "$RESULT_ROOT/work/$stem-driver.o" \
      "$RESULT_ROOT/work/$stem-func.o" \
      -o "$RESULT_ROOT/work/$stem" \
      >"$RESULT_ROOT/work/$stem.link" 2>&1; then
    return 2
  fi
}

execute_native() {
  local stem=$1
  timeout 8 "$RESULT_ROOT/work/$stem" \
    >"$RESULT_ROOT/work/$stem.out" \
    2>"$RESULT_ROOT/work/$stem.err"
  local result=$?
  printf '%s\n' "$result" >"$RESULT_ROOT/work/$stem.status"
  return "$result"
}

execute_aarch64() {
  local stem=$1
  timeout 30 "$QEMU" "$RESULT_ROOT/work/$stem" \
    >"$RESULT_ROOT/work/$stem.out" \
    2>"$RESULT_ROOT/work/$stem.err"
  local result=$?
  printf '%s\n' "$result" >"$RESULT_ROOT/work/$stem.status"
  return "$result"
}

same_output() {
  local expected=$1
  local actual=$2
  test ! -s "$RESULT_ROOT/work/$expected.err" && \
    cmp -s "$RESULT_ROOT/work/$expected.out" "$RESULT_ROOT/work/$actual.out" && \
    test ! -s "$RESULT_ROOT/work/$actual.err"
}

preserve_candidate() {
  local seed=$1
  local reason=$2
  rm -rf "$RESULT_ROOT/candidate"
  mkdir -p "$RESULT_ROOT/candidate"
  cp "$RESULT_ROOT/work/init.h" "$RESULT_ROOT/candidate/"
  cp "$RESULT_ROOT/work/driver.cpp" "$RESULT_ROOT/candidate/"
  cp "$RESULT_ROOT/work/func.cpp" "$RESULT_ROOT/candidate/"
  cp "$RESULT_ROOT/work"/*.out "$RESULT_ROOT/candidate/" 2>/dev/null || true
  cp "$RESULT_ROOT/work"/*.err "$RESULT_ROOT/candidate/" 2>/dev/null || true
  cp "$RESULT_ROOT/work"/*.status "$RESULT_ROOT/candidate/" 2>/dev/null || true
  cp "$RESULT_ROOT/work"/*.compile "$RESULT_ROOT/candidate/" 2>/dev/null || true
  cp "$RESULT_ROOT/work"/*.link "$RESULT_ROOT/candidate/" 2>/dev/null || true
  cp "$RESULT_ROOT/generator.log" "$RESULT_ROOT/candidate/" 2>/dev/null || true
  printf 'seed=%s\nreason=%s\n' "$seed" "$reason" \
    >"$RESULT_ROOT/candidate/candidate.txt"

  timeout 45 "$CLANG" --driver-mode=g++ --target=aarch64-linux-gnu \
    --gcc-toolchain=/usr -std=c++17 -w -O0 -S -emit-llvm \
    "$RESULT_ROOT/work/func.cpp" -o "$RESULT_ROOT/candidate/func-o0.ll" \
    >"$RESULT_ROOT/candidate/func-o0-ir.log" 2>&1 || true
  timeout 45 "$CLANG" --driver-mode=g++ --target=aarch64-linux-gnu \
    --gcc-toolchain=/usr -std=c++17 -w -O2 -S -emit-llvm \
    "$RESULT_ROOT/work/func.cpp" -o "$RESULT_ROOT/candidate/func-o2.ll" \
    >"$RESULT_ROOT/candidate/func-o2-ir.log" 2>&1 || true
  timeout 45 "$CLANG" --driver-mode=g++ --target=aarch64-linux-gnu \
    --gcc-toolchain=/usr -std=c++17 -w -O2 -S \
    "$RESULT_ROOT/work/func.cpp" -o "$RESULT_ROOT/candidate/func-clang-o2.s" \
    >"$RESULT_ROOT/candidate/func-clang-o2-asm.log" 2>&1 || true
  timeout 45 "$CROSS_GXX" -std=c++17 -w -O2 -S \
    "$RESULT_ROOT/work/func.cpp" -o "$RESULT_ROOT/candidate/func-gcc-o2.s" \
    >"$RESULT_ROOT/candidate/func-gcc-o2-asm.log" 2>&1 || true
  sha256sum "$RESULT_ROOT/candidate"/* \
    >"$RESULT_ROOT/candidate/sha256sums.txt" 2>/dev/null || true
}

for ((offset = 0; offset < CASE_COUNT; offset++)); do
  seed=$((START_SEED + offset))
  last_seed=$seed
  rm -f "$RESULT_ROOT/work"/* "$RESULT_ROOT/generator.log"

  if ! timeout 20 "$YARPGEN" --seed="$seed" --std=c++ \
      --emit-align-attr=none --emit-pragmas=none \
      --out-dir="$RESULT_ROOT/work" \
      >"$RESULT_ROOT/generator.log" 2>&1; then
    generation_fail_count=$((generation_fail_count + 1))
    continue
  fi
  if [[ ! -f "$RESULT_ROOT/work/init.h" || \
        ! -f "$RESULT_ROOT/work/driver.cpp" || \
        ! -f "$RESULT_ROOT/work/func.cpp" ]]; then
    generation_fail_count=$((generation_fail_count + 1))
    continue
  fi
  generated_count=$((generated_count + 1))

  source_bytes=$(wc -c <"$RESULT_ROOT/work/init.h")
  source_bytes=$((source_bytes + $(wc -c <"$RESULT_ROOT/work/driver.cpp")))
  source_bytes=$((source_bytes + $(wc -c <"$RESULT_ROOT/work/func.cpp")))
  if [[ "$source_bytes" -gt 2000000 ]]; then
    oversize_count=$((oversize_count + 1))
    continue
  fi

  if ! compile_native "$SYSTEM_CLANG" -O0 oracle-clang-o0 || \
      ! compile_native "$SYSTEM_CLANG" -O2 oracle-clang-o2 || \
      ! compile_native g++ -O0 native-gcc-o0 || \
      ! compile_native g++ -O2 native-gcc-o2; then
    native_compile_reject_count=$((native_compile_reject_count + 1))
    continue
  fi
  if ! execute_native oracle-clang-o0 || \
      ! execute_native oracle-clang-o2 || \
      ! execute_native native-gcc-o0 || \
      ! execute_native native-gcc-o2; then
    native_runtime_reject_count=$((native_runtime_reject_count + 1))
    continue
  fi
  if ! same_output oracle-clang-o0 oracle-clang-o2 || \
      ! same_output oracle-clang-o0 native-gcc-o0 || \
      ! same_output oracle-clang-o0 native-gcc-o2; then
    native_oracle_disagreement_count=$((native_oracle_disagreement_count + 1))
    continue
  fi

  if ! compile_cross_gcc -O0 aarch64-gcc-o0 || \
      ! compile_cross_gcc -O2 aarch64-gcc-o2; then
    cross_gcc_compile_reject_count=$((cross_gcc_compile_reject_count + 1))
    continue
  fi
  if ! execute_aarch64 aarch64-gcc-o0 || \
      ! execute_aarch64 aarch64-gcc-o2; then
    cross_gcc_runtime_reject_count=$((cross_gcc_runtime_reject_count + 1))
    continue
  fi
  if ! same_output oracle-clang-o0 aarch64-gcc-o0 || \
      ! same_output oracle-clang-o0 aarch64-gcc-o2; then
    cross_target_oracle_disagreement_count=$((cross_target_oracle_disagreement_count + 1))
    continue
  fi

  if ! compile_native "$CLANG" -O0 current-clang-o0; then
    current_native_compile_failure_count=$((current_native_compile_failure_count + 1))
    status=current-clang-native-o0-compile-failure
    preserve_candidate "$seed" "$status"
    break
  fi
  if ! compile_native "$CLANG" -O2 current-clang-o2; then
    current_native_compile_failure_count=$((current_native_compile_failure_count + 1))
    status=current-clang-native-o2-compile-failure
    preserve_candidate "$seed" "$status"
    break
  fi
  if ! execute_native current-clang-o0; then
    current_native_runtime_failure_count=$((current_native_runtime_failure_count + 1))
    status=current-clang-native-o0-runtime-failure
    preserve_candidate "$seed" "$status"
    break
  fi
  if ! execute_native current-clang-o2; then
    current_native_runtime_failure_count=$((current_native_runtime_failure_count + 1))
    status=current-clang-native-o2-runtime-failure
    preserve_candidate "$seed" "$status"
    break
  fi
  if ! same_output oracle-clang-o0 current-clang-o0; then
    current_native_output_mismatch_count=$((current_native_output_mismatch_count + 1))
    status=current-clang-native-o0-output-mismatch
    preserve_candidate "$seed" "$status"
    break
  fi
  if ! same_output oracle-clang-o0 current-clang-o2; then
    current_native_output_mismatch_count=$((current_native_output_mismatch_count + 1))
    status=current-clang-native-o2-output-mismatch
    preserve_candidate "$seed" "$status"
    break
  fi

  compile_cross_clang -O0 aarch64-clang-o0
  clang_status=$?
  if [[ "$clang_status" -ne 0 ]]; then
    if [[ "$clang_status" -eq 1 ]]; then
      clang_aarch64_compile_failure_count=$((clang_aarch64_compile_failure_count + 1))
      status=clang-aarch64-o0-compile-failure
    else
      clang_aarch64_link_failure_count=$((clang_aarch64_link_failure_count + 1))
      status=clang-aarch64-o0-link-failure
    fi
    preserve_candidate "$seed" "$status"
    break
  fi
  compile_cross_clang -O2 aarch64-clang-o2
  clang_status=$?
  if [[ "$clang_status" -ne 0 ]]; then
    if [[ "$clang_status" -eq 1 ]]; then
      clang_aarch64_compile_failure_count=$((clang_aarch64_compile_failure_count + 1))
      status=clang-aarch64-o2-compile-failure
    else
      clang_aarch64_link_failure_count=$((clang_aarch64_link_failure_count + 1))
      status=clang-aarch64-o2-link-failure
    fi
    preserve_candidate "$seed" "$status"
    break
  fi

  if ! execute_aarch64 aarch64-clang-o0; then
    clang_aarch64_runtime_failure_count=$((clang_aarch64_runtime_failure_count + 1))
    status=clang-aarch64-o0-runtime-failure
    preserve_candidate "$seed" "$status"
    break
  fi
  if ! execute_aarch64 aarch64-clang-o2; then
    clang_aarch64_runtime_failure_count=$((clang_aarch64_runtime_failure_count + 1))
    status=clang-aarch64-o2-runtime-failure
    preserve_candidate "$seed" "$status"
    break
  fi
  if ! same_output oracle-clang-o0 aarch64-clang-o0; then
    clang_aarch64_output_mismatch_count=$((clang_aarch64_output_mismatch_count + 1))
    status=clang-aarch64-o0-output-mismatch
    preserve_candidate "$seed" "$status"
    break
  fi
  if ! same_output oracle-clang-o0 aarch64-clang-o2; then
    clang_aarch64_output_mismatch_count=$((clang_aarch64_output_mismatch_count + 1))
    status=clang-aarch64-o2-output-mismatch
    preserve_candidate "$seed" "$status"
    break
  fi

  compared_count=$((compared_count + 1))
done

if [[ "$status" == no-mismatch && "$compared_count" -eq 0 ]]; then
  status=no-valid-cases
fi

cat >"$RESULT_ROOT/summary.txt" <<EOF
status=$status
profile=aarch64-six-oracle-yarpgen-loop
start_seed=$START_SEED
last_seed=$last_seed
case_count=$CASE_COUNT
generated_count=$generated_count
compared_count=$compared_count
generation_fail_count=$generation_fail_count
oversize_count=$oversize_count
native_compile_reject_count=$native_compile_reject_count
native_runtime_reject_count=$native_runtime_reject_count
native_oracle_disagreement_count=$native_oracle_disagreement_count
current_native_compile_failure_count=$current_native_compile_failure_count
current_native_runtime_failure_count=$current_native_runtime_failure_count
current_native_output_mismatch_count=$current_native_output_mismatch_count
cross_gcc_compile_reject_count=$cross_gcc_compile_reject_count
cross_gcc_runtime_reject_count=$cross_gcc_runtime_reject_count
cross_target_oracle_disagreement_count=$cross_target_oracle_disagreement_count
clang_aarch64_compile_failure_count=$clang_aarch64_compile_failure_count
clang_aarch64_link_failure_count=$clang_aarch64_link_failure_count
clang_aarch64_runtime_failure_count=$clang_aarch64_runtime_failure_count
clang_aarch64_output_mismatch_count=$clang_aarch64_output_mismatch_count
clang_version=$($CLANG --version | head -n1)
oracle_clang_version=$($SYSTEM_CLANG --version | head -n1)
native_gcc_version=$(g++ --version | head -n1)
cross_gcc_version=$($CROSS_GXX --version | head -n1)
qemu_version=$($QEMU --version | head -n1)
yarpgen_binary_sha256=$(sha256sum "$YARPGEN" | cut -d' ' -f1)
EOF

rm -rf "$RESULT_ROOT/work" "$RESULT_ROOT/generator.log"
printf '%s\n' "$status"

if [[ "$status" == no-valid-cases ]]; then
  exit 2
fi
