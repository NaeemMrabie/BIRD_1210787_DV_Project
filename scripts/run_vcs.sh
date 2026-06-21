#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/run_vcs.sh          # run all tests
#   ./scripts/run_vcs.sh 6        # run TEST_ID=6 only

TEST_ID="${1:-0}"

vcs -full64 -sverilog -debug_access+all -timescale=1ns/1ps \
    -cm line+cond+fsm+tgl+branch+assert \
    -f vcs.f -o simv

./simv +TEST_ID=${TEST_ID} -cm line+cond+fsm+tgl+branch+assert | tee sim_TEST_ID_${TEST_ID}.log

urg -dir simv.vdb -report coverage/code_coverage/urg_report_TEST_ID_${TEST_ID}
