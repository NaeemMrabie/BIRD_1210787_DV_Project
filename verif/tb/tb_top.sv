

`timescale 1ns/1ps

`include "transaction.sv"
`include "bird_if.sv"
`include "generator.sv"
`include "driver.sv"
`include "monitor.sv"
`include "agent.sv"
`include "ref_model.sv"
`include "coverage.sv"
`include "scoreboard.sv"
`include "environment.sv"
`include "test.sv"

module tb_top;

  // ----------------------------------------------------------
  // Clock generation
  // ----------------------------------------------------------
  logic clk = 0;
  always #5 clk = ~clk; // 100MHz, 10ns period

  // ----------------------------------------------------------
  // Interface instance
  // ----------------------------------------------------------
  bird_if dut_if (.clk(clk));


  BIRD dut (
    .clk         (clk),
    .rst_n       (dut_if.rst_n),

    .in_vld      (dut_if.in_vld),
    .in_rdy      (dut_if.in_rdy),
    .data_in     (dut_if.data_in),
    .cfg         (dut_if.cfg),

    .drop_cnt    (dut_if.drop_cnt),

    .local_vld   (dut_if.local_vld),
    .local_rdy   (dut_if.local_rdy),
    .data_local  (dut_if.data_local),

    .remote_vld  (dut_if.remote_vld),
    .remote_rdy  (dut_if.remote_rdy),
    .data_remote (dut_if.data_remote)
  );


  test t;
  int unsigned test_id;

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);

    if (!$value$plusargs("TEST_ID=%0d", test_id)) test_id = 0;
    $display("[TB_TOP] Running TEST_ID=%0d (0 means full suite)", test_id);

    t = new(dut_if);
    t.run_by_id(test_id);

    $display("==================================================");
    $display("[TB_TOP] All tests complete.");
    $finish;
  end


  initial begin
    #2_000_000; // 2ms simulated time ceiling
    $display("[TB_TOP][TIMEOUT] Global watchdog fired - forcing $finish");
    $finish;
  end

endmodule
