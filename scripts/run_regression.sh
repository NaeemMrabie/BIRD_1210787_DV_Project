#!/usr/bin/env bash
set -euo pipefail

# Runs all 15 tests individually and merges coverage.
# Requires design/bird.sv to be present and uncommented in vcs.f.

vcs -full64 -sverilog -debug_access+all -timescale=1ns/1ps \
    -cm line+cond+fsm+tgl+branch+assert \
    -f vcs.f -o simv

rm -rf coverage/work
mkdir -p coverage/work

for tid in $(seq 1 15); do
  echo "===== Running TEST_ID=${tid} ====="
  ./simv +TEST_ID=${tid} -cm line+cond+fsm+tgl+branch+assert \
        -cm_name TEST_${tid} | tee coverage/work/TEST_${tid}.log
  if grep -q "RESULT: FAIL" coverage/work/TEST_${tid}.log; then
    echo "TEST_ID=${tid} failed"
    exit 1
  fi
done

urg -dir simv.vdb -report coverage/code_coverage/urg_regression_report
