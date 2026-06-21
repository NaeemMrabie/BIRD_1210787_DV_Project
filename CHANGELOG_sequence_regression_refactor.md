# Sequence / Test / Regression Refactor

This update reorganizes the plain SystemVerilog verification environment without using UVM.

## New structure

- `verif/seq/sequences.sv`
  - Contains one sequence class per spec/test-plan function.
  - Directed sequences cover reset, local, remote, drop policy, drop counter, backpressure, boundary/max values.
  - Random sequences cover legal local, complete remote packets, invalid cfg, backpressure matrix, and broad mixed traffic.

- `verif/tests/test_directed.sv`
  - Contains one directed test class per directed function.
  - Each directed test uses the matching sequence.

- `verif/tests/test_random.sv`
  - Contains constrained-random test classes.
  - Each random test uses the matching random sequence.

- `verif/tests/regression.sv`
  - Owns a single shared environment.
  - Runs directed tests first, then random tests.
  - Prints a final cumulative functional coverage snapshot.

- `verif/env/coverage.sv`
  - Expanded coverage bins for boundary/max values.
  - Added drop_cnt many/pre-wrap/wrap bins.
  - Added explicit coverage for all local/remote backpressure combinations.

## TEST_ID map

- `0`: full regression
- `1`: directed suite only
- `2`: random suite only
- `3..17`: individual directed tests
- `18..22`: individual random tests

## Notes

The testbench remains spec-based. If a test fails, that may indicate an RTL/spec mismatch, not necessarily a testbench issue.
