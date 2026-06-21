#!/usr/bin/env bash
set -euo pipefail

# Full BIRD regression: directed suite followed by random suite.
# Use +FULL_DROP_WRAP=1 manually if you want the long 65537-drop wrap test.

vcs -full64 -sverilog -debug_access+all -timescale=1ns/1ps \
    -cm line+cond+fsm+tgl+branch+assert \
    -f vcs.f -o simv

mkdir -p coverage/work coverage/functional_coverage coverage/code_coverage

./simv +TEST_ID=0 -cm line+cond+fsm+tgl+branch+assert \
      -cm_name FULL_REGRESSION | tee coverage/functional_coverage/functional_coverage_TEST_ID_0.log

urg -dir simv.vdb -report coverage/code_coverage/urg_regression_report
