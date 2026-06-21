// ============================================================
// bird_if.sv
// ------------------------------------------------------------
// SystemVerilog interface wrapping all BIRD DUT signals.
// Provides separate clocking blocks for:
//   - driver  (drives input side, samples in_rdy)
//   - monitor (passively samples everything)
// This keeps driver/monitor decoupled from raw signal timing
// and avoids race conditions around the clock edge.
// ============================================================

`ifndef BIRD_IF_SV
`define BIRD_IF_SV

interface bird_if (input logic clk);

  logic        rst_n;

  // Input interface (Producer -> BIRD)
  logic        in_vld;
  logic        in_rdy;
  logic [7:0]  data_in;
  logic [31:0] cfg;

  // Status output
  logic [15:0] drop_cnt;

  // Local output interface
  logic        local_vld;
  logic        local_rdy;
  logic [7:0]  data_local;

  // Remote output interface
  logic        remote_vld;
  logic        remote_rdy;
  logic [31:0] data_remote;

  // ----------------------------------------------------------
  // Driver clocking block
  // Driver drives in_vld/data_in/cfg, and local_rdy/remote_rdy
  // (rdy on the consumer sides is also driven by TB since BIRD
  // is the DUT producing on those interfaces).
  // Driver samples in_rdy to know if its transfer was accepted.
  // ----------------------------------------------------------
  clocking drv_cb @(posedge clk);
    output in_vld;
    output data_in;
    output cfg;
    output local_rdy;
    output remote_rdy;
    input  in_rdy;
  endclocking

  // ----------------------------------------------------------
  // Monitor clocking block
  // Purely passive: samples everything one cycle "settled"
  // after the active edge, so it always sees post-edge values.
  // ----------------------------------------------------------
  clocking mon_cb @(posedge clk);
    default input #1step;
    input in_vld;
    input in_rdy;
    input data_in;
    input cfg;
    input drop_cnt;
    input local_vld;
    input local_rdy;
    input data_local;
    input remote_vld;
    input remote_rdy;
    input data_remote;
  endclocking

  // Modports (used if blocks/modules want a restricted view)
  modport DRV (clocking drv_cb, input rst_n);
  modport MON (clocking mon_cb, input rst_n);

endinterface

`endif // BIRD_IF_SV
