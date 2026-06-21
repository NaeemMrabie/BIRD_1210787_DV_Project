
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


  clocking drv_cb @(posedge clk);
    output in_vld;
    output data_in;
    output cfg;
    output local_rdy;
    output remote_rdy;
    input  in_rdy;
  endclocking


  clocking mon_cb @(posedge clk);
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


  modport DRV (clocking drv_cb, input rst_n);
  modport MON (clocking mon_cb, input rst_n);

endinterface

`endif // BIRD_IF_SV
