// ============================================================
// coverage.sv
// ------------------------------------------------------------
// Functional coverage model for BIRD, derived from the project
// specification. Plain SystemVerilog covergroups; no UVM.
// Expanded to cover boundary/max values, drop_cnt many/wrap
// bins, and all local/remote backpressure combinations.
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
  bit [1:0]  cg_bp_mode;

  // ----------------------------------------------------------
  // Covers cfg fields, legal/illegal structural classes, and
  // important boundary values from the spec.
  // ----------------------------------------------------------
  covergroup cfg_cg;
    option.per_instance = 1;
    option.name = "bird_cfg_functional_coverage";

    traffic_type_cp: coverpoint cg_type {
      bins traffic_local  = {1'b0};
      bins traffic_remote = {1'b1};
    }

    payload_len_cp: coverpoint cg_len {
      bins len_zero_illegal = {8'd0};
      bins len_min          = {8'd1};
      bins len_2_to_8       = {[8'd2:8'd8]};
      bins len_9_to_64      = {[8'd9:8'd64]};
      bins len_65_to_254    = {[8'd65:8'd254]};
      bins len_max          = {8'd255};
    }

    frag_num_cp: coverpoint cg_frag {
      bins frag_zero_illegal = {5'd0};
      bins frag_first        = {5'd1};
      bins frag_middle       = {[5'd2:5'd30]};
      bins frag_max          = {5'd31};
    }

    seq_num_cp: coverpoint cg_seq {
      bins seq_zero_illegal = {5'd0};
      bins seq_min          = {5'd1};
      bins seq_middle       = {[5'd2:5'd30]};
      bins seq_max          = {5'd31};
    }

    reserved_clean_cp: coverpoint cg_reserved_clean {
      bins reserved_clean = {1'b1};
      bins reserved_dirty = {1'b0};
    }

    structural_valid_cp: coverpoint cg_structural_valid {
      bins cfg_legal_structural   = {1'b1};
      bins cfg_illegal_structural = {1'b0};
    }

    local_frag_ok_cp: coverpoint cg_local_frag_ok iff (cg_type == 1'b0) {
      bins local_frag_one = {1'b1};
      bins local_frag_bad = {1'b0};
    }

    traffic_x_len:      cross traffic_type_cp, payload_len_cp;
    traffic_x_frag:     cross traffic_type_cp, frag_num_cp;
    traffic_x_seq:      cross traffic_type_cp, seq_num_cp;
    traffic_x_reserved: cross traffic_type_cp, reserved_clean_cp;
    traffic_x_valid:    cross traffic_type_cp, structural_valid_cp;
  endgroup

  // ----------------------------------------------------------
  // Protocol coverage: output-side backpressure combinations
  // and drop_cnt boundary classes including many/wrap bins.
  // ----------------------------------------------------------
  covergroup protocol_cg;
    option.per_instance = 1;
    option.name = "bird_protocol_functional_coverage";

    local_backpressure_cp: coverpoint cg_local_bp {
      bins local_no_bp = {1'b0};
      bins local_bp    = {1'b1};
    }

    remote_backpressure_cp: coverpoint cg_remote_bp {
      bins remote_no_bp = {1'b0};
      bins remote_bp    = {1'b1};
    }

    bp_mode_cp: coverpoint cg_bp_mode {
      bins bp_none        = {2'b00};
      bins bp_remote_only = {2'b01};
      bins bp_local_only  = {2'b10};
      bins bp_both        = {2'b11};
    }

    drop_cnt_cp: coverpoint cg_drop_cnt {
      bins drop_zero       = {16'd0};
      bins drop_one        = {16'd1};
      bins drop_few        = {[16'd2:16'd20]};
      bins drop_many       = {[16'd21:16'd255]};
      bins drop_high       = {[16'd256:16'hfffd]};
      bins drop_pre_wrap   = {16'hfffe};
      bins drop_wrap_value = {16'hffff};
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
    cg_bp_mode   = {local_bp, remote_bp};
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
