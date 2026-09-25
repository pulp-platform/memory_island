#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Run memory_island_core_perf_tb over all scenarios for NarrowExtraBF = 1 and 2.
# Usage: scripts/run_perf.sh [cycles] [sv_seed]
# Results: build/perf/results.txt (RESULT lines), per-run logs in build/perf/logs/.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/perf"
CYCLES="${1:-20000}"
SEED="${2:-1}"
VSIM="${VSIM:-questa-2023.4 vsim}"

mkdir -p "$BUILD/logs"
cd "$BUILD"

bender -d "$ROOT" script vsim -t test --vlog-arg="-svinputport=compat" > compile.tcl
echo "return 0" >> compile.tcl
rm -rf work
$VSIM -64 -c -do "vlib work; quit -code [source compile.tcl]" > logs/compile.log 2>&1 || {
  echo "compile failed, see $BUILD/logs/compile.log"; exit 1;
}

# name:plusargs
RUNS=(
  "s1:+SCENARIO=S1 +INJ=100"
  "s2:+SCENARIO=S2 +INJ=100"
  "s3_inj25:+SCENARIO=S3 +INJ=25"
  "s3_inj50:+SCENARIO=S3 +INJ=50"
  "s3_inj100:+SCENARIO=S3 +INJ=100"
  "s4_off32:+SCENARIO=S4 +OFFSET=32"
  "s4_off64:+SCENARIO=S4 +OFFSET=64"
)

: > results.txt
for bf in 1 2; do
  for run in "${RUNS[@]}"; do
    name="${run%%:*}"
    args="${run#*:}"
    log="logs/${name}_bf${bf}.log"
    # shellcheck disable=SC2086
    $VSIM -64 -c -sv_seed "$SEED" -GNarrowExtraBF="$bf" memory_island_core_perf_tb \
      $args +CYCLES="$CYCLES" -do "run -all; quit -f" > "$log" 2>&1
    grep -q "SANITY PASS" "$log" || { echo "FAILED: $log"; exit 1; }
    grep "^# RESULT" "$log" | sed 's/^# //' >> results.txt
    echo "done $name bf=$bf"
  done
done
