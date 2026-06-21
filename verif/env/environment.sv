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

  // Guard so persistent driver/monitor/scoreboard threads are launched only once.
  bit started;

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
    started = 0;
  endfunction

  // ----------------------------------------------------------
  // Apply reset (spec Section 9: active-low rst_n)
  // ----------------------------------------------------------
  task apply_reset(int unsigned cycles = 3);
    vif.rst_n = 1'b0;
    drv.reset_signals();
    sb.reset();
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
    if (!started) begin
      started = 1;
      agt.run();
      sb.run();
    end
  endtask

  // ----------------------------------------------------------
  // Convenience: wait until ALL real activity has drained -
  // not just "the generator mailbox is empty" (which only means
  // the driver has STARTED the last transfer, not finished it),
  // but every stage of the pipeline:
  //   1. generator -> driver mailbox empty (driver picked up the
  //      last transaction)
  //   2. the driver is not mid-fragment (num_sent stops changing -
  //      simplest robust signal is to also wait a few idle cycles
  //      on the bus itself: in_vld deasserted)
  //   3. monitor -> scoreboard input-fragment mailbox empty (the
  //      monitor has finished reconstructing and forwarding every
  //      fragment it saw)
  //   4. the reference model has no leftover expected local/remote
  //      bytes that the DUT hasn't produced yet AND no leftover
  //      observed bytes still in their mailboxes
  //   5. drop_cnt comparison is allowed to settle one more cycle
  //      after all of the above, since it is the last side-effect
  //      of processing a fragment.
  //
  // Each `wait` below is a real synchronization point (not a
  // fixed guess), so this is correct regardless of fragment size,
  // payload length, or how many fragments were queued.
  // ----------------------------------------------------------
  task wait_drain(int unsigned extra_cycles = 20);
    int unsigned guard;
    int unsigned max_wait_cycles;

    max_wait_cycles = (extra_cycles < 1000) ? 5000 : (extra_cycles + 5000);

    // 1) generator -> driver: wait until the driver has consumed
    //    every transaction the test pushed.
    guard = 0;
    while (gen2drv_mbx.num() != 0 && guard < max_wait_cycles) begin
      @(posedge vif.clk);
      guard++;
    end
    if (gen2drv_mbx.num() != 0) begin
      $error("[ENV][WAIT_DRAIN] Timeout waiting for gen2drv_mbx to drain; remaining=%0d",
             gen2drv_mbx.num());
      return;
    end

    // 2) the driver must not be mid-fragment: the bus must show
    //    an idle (deasserted) in_vld for at least one full cycle,
    //    which only happens once drive_one() has returned for the
    //    last queued fragment.
    guard = 0;
    @(posedge vif.clk);
    while (vif.in_vld && guard < max_wait_cycles) begin
      @(posedge vif.clk);
      guard++;
    end
    if (vif.in_vld) begin
      $error("[ENV][WAIT_DRAIN] Timeout waiting for input bus idle");
      return;
    end

    // 3) monitor -> scoreboard: every fragment fully observed on
    //    the wire must have been forwarded for reference-model
    //    processing.
    guard = 0;
    while (mon2sb_input_mbx.num() != 0 && guard < max_wait_cycles) begin
      @(posedge vif.clk);
      guard++;
    end
    if (mon2sb_input_mbx.num() != 0) begin
      $error("[ENV][WAIT_DRAIN] Timeout waiting for mon2sb_input_mbx to drain; remaining=%0d",
             mon2sb_input_mbx.num());
      return;
    end

    // 4) Wait until both observed-side mailboxes and expected-side
    //    queues are empty.  This is bounded so a real mismatch reports
    //    as an error instead of hanging the whole regression.
    guard = 0;
    while (!((mon2sb_local_mbx.num()  == 0) && (sb.rm.exp_local_q.size()        == 0) &&
             (mon2sb_remote_mbx.num() == 0) && (sb.rm.exp_remote_words_q.size() == 0)) &&
           guard < max_wait_cycles) begin
      @(posedge vif.clk);
      guard++;
    end
    if (!((mon2sb_local_mbx.num()  == 0) && (sb.rm.exp_local_q.size()        == 0) &&
          (mon2sb_remote_mbx.num() == 0) && (sb.rm.exp_remote_words_q.size() == 0))) begin
      $error("[ENV][WAIT_DRAIN] Timeout waiting for output/checker drain: local_obs=%0d local_exp=%0d remote_obs=%0d remote_exp=%0d",
             mon2sb_local_mbx.num(), sb.rm.exp_local_q.size(),
             mon2sb_remote_mbx.num(), sb.rm.exp_remote_words_q.size());
      return;
    end

    // 5) drop_cnt is the last side-effect of process_fragment() for
    //    a dropped packet; give it a couple of settle cycles plus
    //    whatever small margin the caller wants for test-specific
    //    follow-up checks (e.g. reading vif.drop_cnt directly).
    repeat (extra_cycles) @(posedge vif.clk);
  endtask

  function void report();
    sb.report();
  endfunction

endclass

`endif // ENVIRONMENT_SV
