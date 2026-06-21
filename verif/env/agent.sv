// ============================================================
// agent.sv
// ------------------------------------------------------------
// Plain SystemVerilog agent. It groups the BIRD input driver
// and passive monitor. This is intentionally not UVM.
// ============================================================

`ifndef AGENT_SV
`define AGENT_SV

`include "transaction.sv"
`include "driver.sv"
`include "monitor.sv"

class bird_agent;

  driver  drv;
  monitor mon;

  function new(virtual bird_if vif,
               mailbox #(transaction)      gen2drv_mbx,
               mailbox #(transaction)      mon2sb_input_mbx,
               mailbox #(local_byte_obs)   mon2sb_local_mbx,
               mailbox #(remote_word_obs)  mon2sb_remote_mbx,
               mailbox #(bit [15:0])       mon2sb_dropcnt_mbx);
    drv = new(vif, gen2drv_mbx);
    mon = new(vif, mon2sb_input_mbx, mon2sb_local_mbx, mon2sb_remote_mbx, mon2sb_dropcnt_mbx);
  endfunction

  task run();
    fork
      drv.run();
      drv.drive_backpressure();
      mon.run();
    join_none
  endtask

endclass

`endif // AGENT_SV
