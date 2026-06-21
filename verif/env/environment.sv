// ============================================================
// environment.sv
// ------------------------------------------------------------
// Environment: instantiates and connects generator, driver,
// monitor and scoreboard. Owns all mailboxes and exposes a
// single run() entry point used by tests.
// ============================================================

`ifndef ENVIRONMENT_SV
`define ENVIRONMENT_SV

`include "transaction.sv"
`include "generator.sv"
`include "driver.sv"
`include "monitor.sv"
`include "agent.sv"
`include "scoreboard.sv"

class environment;

  // Components
  generator  gen;
  bird_agent agt;
  driver     drv; // alias to agt.drv for tests
  monitor    mon; // alias to agt.mon for tests
  scoreboard sb;

  // Mailboxes
  mailbox #(transaction)      gen2drv_mbx;
  mailbox #(transaction)      mon2sb_input_mbx;
  mailbox #(local_byte_obs)   mon2sb_local_mbx;
  mailbox #(remote_word_obs)  mon2sb_remote_mbx;
  mailbox #(bit [15:0])       mon2sb_dropcnt_mbx;

  virtual bird_if vif;

  function new(virtual bird_if vif);
    this.vif = vif;

    gen2drv_mbx         = new();
    mon2sb_input_mbx     = new();
    mon2sb_local_mbx     = new();
    mon2sb_remote_mbx    = new();
    mon2sb_dropcnt_mbx   = new();

    gen = new(gen2drv_mbx);
    agt = new(vif, gen2drv_mbx, mon2sb_input_mbx, mon2sb_local_mbx, mon2sb_remote_mbx, mon2sb_dropcnt_mbx);
    drv = agt.drv;
    mon = agt.mon;
    sb  = new(mon2sb_input_mbx, mon2sb_local_mbx, mon2sb_remote_mbx, mon2sb_dropcnt_mbx);
  endfunction

  // ----------------------------------------------------------
  // Apply reset (spec Section 9: active-low rst_n)
  // ----------------------------------------------------------
  task apply_reset(int unsigned cycles = 3);
    vif.rst_n = 1'b0;
    drv.reset_signals();
    repeat (cycles) @(posedge vif.clk);
    vif.rst_n = 1'b1;
    @(posedge vif.clk);
  endtask

  // ----------------------------------------------------------
  // Start all the persistent processes (driver run loop,
  // monitor watchers, scoreboard checkers). Generator is
  // driven explicitly by the test (directed scenarios) and/or
  // via gen.run() for randomized traffic.
  // ----------------------------------------------------------
  task run();
    agt.run();
    sb.run();
  endtask

  // ----------------------------------------------------------
  // Convenience: wait until generator mailbox AND driver have
  // drained, then a few extra cycles for outputs to flush.
  // ----------------------------------------------------------
  task wait_drain(int unsigned extra_cycles = 50);
    wait (gen2drv_mbx.num() == 0);
    repeat (extra_cycles) @(posedge vif.clk);
  endtask

  function void report();
    sb.report();
  endfunction

endclass

`endif // ENVIRONMENT_SV
