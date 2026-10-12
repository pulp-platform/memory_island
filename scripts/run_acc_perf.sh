#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Run axi_memory_island_perf_tb over the accumulation scenarios for one configuration.
#
# Usage: scripts/run_acc_perf.sh <config> [cycles] [sv_seed]
#   config  base   no ATOP support, one plain sub-word write per event
#           basew  no ATOP support, one plain word write per 4 events: the write-bandwidth
#                  ceiling that config a approaches
#           a      per-bank saturating adder on the sensor port, a whole word per AXI write
#
# Results: build/perf/results_<config>_seed<seed>.txt, logs in build/perf/logs/.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/perf"
CONFIG="${1:?config: base | basew | a}"
CYCLES="${2:-20000}"
SEED="${3:-1}"
VSIM="${VSIM:-questa-2023.4 vsim}"

case "$CONFIG" in
  base)  GPARAMS=(-GAccumEnabled=0); ARGS="+MERGE=0" ;;
  basew) GPARAMS=(-GAccumEnabled=0); ARGS="+MERGE=1" ;;
  a)     GPARAMS=(-GAccumEnabled=1); ARGS="+MERGE=1" ;;
  *)     echo "unknown config '$CONFIG' (base | basew | a)"; exit 1 ;;
esac

mkdir -p "$BUILD/logs"
cd "$BUILD"

bender -d "$ROOT" script vsim -t test --vlog-arg="-svinputport=compat" > compile.tcl
echo "return 0" >> compile.tcl
rm -rf work
$VSIM -64 -c -do "vlib work; quit -code [source compile.tcl]" > "logs/compile_${CONFIG}.log" 2>&1 || {
  echo "compile failed, see $BUILD/logs/compile_${CONFIG}.log"; exit 1;
}

RESULTS="results_${CONFIG}_seed${SEED}.txt"
: > "$RESULTS"

for scen in P1 P2 P3 P4; do
  log="logs/${scen}_${CONFIG}_seed${SEED}.log"
  # P3 injects one event cluster every 1500 cycles (10 M events/s at 1 GHz), so it needs a longer
  # window than the saturated scenarios to collect a usable number of sensor samples.
  if [ "$scen" = "P3" ]; then scen_cycles=$((CYCLES * 5)); else scen_cycles="$CYCLES"; fi
  # shellcheck disable=SC2086
  $VSIM -64 -c -sv_seed "$SEED" "${GPARAMS[@]}" axi_memory_island_perf_tb \
    +SCENARIO=$scen $ARGS +CYCLES="$scen_cycles" -do "run -all; quit -f" > "$log" 2>&1 || true
  if ! grep -q "SANITY PASS" "$log"; then
    echo "FAILED: $log"
    grep -E "Error|Fatal|mismatch|directed" "$log" | head -10
    exit 1
  fi
  grep "^# RESULT" "$log" | sed 's/^# //' >> "$RESULTS"
  echo "done $scen config=$CONFIG"
done

echo "results in $BUILD/$RESULTS"
