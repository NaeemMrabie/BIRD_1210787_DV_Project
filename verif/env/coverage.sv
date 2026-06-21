// ============================================================
// coverage.sv
// ------------------------------------------------------------
// Functional coverage model for BIRD, derived from the project
// specification.  This is plain SystemVerilog covergroups; no
// UVM dependency is used.
// ============================================================

`ifndef COVERAGE_SV
`define COVERAGE_SV

`include "transaction.sv"

class bird_coverage;

  bit        cg_type;
  bit [7:0]  cg_len;
  bit [4:0]  cg_frag;
  bit [4:0]  cg_seq;
  bit        cg_reserved_clean;
  bit        cg_structural_valid;
  bit        cg_local_frag_ok;
  bit        cg_remote;
  bit [15:0] cg_drop_cnt;
  bit        cg_local_bp;
  bit        cg_remote_bp;

  // Covers the configuration word fields and legal/illegal classes.
  covergroup cfg_cg;
    option.per_instance = 1;
    option.name = "bird_cfg_functional_coverage";

   traffic_type_cp: coverpoint cg_type {
  bins local_traffic  = {1'b0};
  bins remote_traffic = {1'b1};
}

    payload_len_cp: coverpoint cg_len {
      bins zero_illegal = {8'd0};
      bins min_len      = {8'd1};
      bins len_small  = {[8'd2:8'd8]};
      bins len_medium = {[8'd9:8'd64]};
      bins len_large  = {[8'd65:8'd254]};
      bins max_len      = {8'd255};
    }

    frag_num_cp: coverpoint cg_frag {
      bins zero_illegal = {5'd0};
      bins first        = {5'd1};
      bins middle       = {[5'd2:5'd30]};
      bins max_frag     = {5'd31};
    }

    seq_num_cp: coverpoint cg_seq {
      bins zero_illegal = {5'd0};
      bins min_seq      = {5'd1};
      bins middle_seq   = {[5'd2:5'd30]};
      bins max_seq      = {5'd31};
    }

    reserved_clean_cp: coverpoint cg_reserved_clean {
      bins clean = {1'b1};
      bins dirty = {1'b0};
    }

    structural_valid_cp: coverpoint cg_structural_valid {
      bins legal_structural   = {1'b1};
      bins illegal_structural = {1'b0};
    }

    local_frag_ok_cp: coverpoint cg_local_frag_ok iff (cg_type == 1'b0) {
      bins ok  = {1'b1};
      bins bad = {1'b0};
    }

    traffic_x_len: cross traffic_type_cp, payload_len_cp;
    traffic_x_frag: cross traffic_type_cp, frag_num_cp;
    traffic_x_seq: cross traffic_type_cp, seq_num_cp;
    traffic_x_reserved: cross traffic_type_cp, reserved_clean_cp;
  endgroup

  // Covers ready backpressure and drop counter observations.
  covergroup protocol_cg;
    option.per_instance = 1;
    option.name = "bird_protocol_functional_coverage";

    local_backpressure_cp: coverpoint cg_local_bp {
      bins no_backpressure = {1'b0};
      bins backpressure    = {1'b1};
    }

    remote_backpressure_cp: coverpoint cg_remote_bp {
      bins no_backpressure = {1'b0};
      bins backpressure    = {1'b1};
    }

    drop_cnt_cp: coverpoint cg_drop_cnt {
      bins zero       = {16'd0};
      bins one        = {16'd1};
      bins few        = {[16'd2:16'd20]};
      bins many       = {[16'd21:16'hfffe]};
      bins wrap_value = {16'hffff};
    }

    bp_cross: cross local_backpressure_cp, remote_backpressure_cp;
  endgroup

  function new();
    cfg_cg = new();
    protocol_cg = new();
  endfunction

  function void sample_input(transaction t);
    cg_type = t.traffic_type;
    cg_len  = t.payload_len;
    cg_frag = t.frag_num;
    cg_seq  = t.seq_num;
    cg_reserved_clean = ((t.reserved_7_1 == 7'd0) &&
                         (t.reserved_23_21 == 3'd0) &&
                         (t.reserved_31_29 == 3'd0));
    cg_structural_valid = (cg_reserved_clean &&
                           (t.payload_len != 8'd0) &&
                           (t.seq_num     != 5'd0) &&
                           (t.frag_num    != 5'd0));
    cg_local_frag_ok = (t.frag_num == 5'd1);
    cfg_cg.sample();
  endfunction

  function void sample_backpressure(bit local_bp, bit remote_bp);
    cg_local_bp  = local_bp;
    cg_remote_bp = remote_bp;
    protocol_cg.sample();
  endfunction

  function void sample_drop_cnt(bit [15:0] drop_cnt);
    cg_drop_cnt = drop_cnt;
    protocol_cg.sample();
  endfunction

  function void report();
    $display("[COVERAGE] cfg_cg      = %0.2f%%", cfg_cg.get_coverage());
    $display("[COVERAGE] protocol_cg = %0.2f%%", protocol_cg.get_coverage());
    $display("[COVERAGE] overall     = %0.2f%%", $get_coverage());
  endfunction

endclass

`endif // COVERAGE_SV
