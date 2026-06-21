// ============================================================
// test.sv
// ------------------------------------------------------------
// Compatibility wrapper.  The project is now organized as:
//   test_directed.sv -> directed tests
//   test_random.sv   -> constrained-random tests
//   regression.sv    -> directed then random regression controller
// tb_top.sv includes regression.sv directly.
// ============================================================

`ifndef TEST_SV
`define TEST_SV

`include "regression.sv"

`endif // TEST_SV
