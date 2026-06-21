// ============================================================
// bird_assertions.sv
// ------------------------------------------------------------
// SystemVerilog Assertions (SVA) for BIRD, kept in a separate
// file and `bind`-ed to the design module rather than embedded
// directly in design/bird.sv. This keeps the RTL clean while
// still giving every assertion direct, signal-level access to
// the DUT (same port list as BIRD, connected with `.*`).
//
// Each assertion below is traced to a specific spec rule in its
// comment. These run automatically in any simulation that
// elaborates design/bird.sv (via the `bind` statement at the
// bottom of this file) - no testbench wiring required.
// ============================================================

`ifndef BIRD_ASSERTIONS_SV
`define BIRD_ASSERTIONS_SV

module bird_assertions (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        in_vld,
  input  logic        in_rdy,
  input  logic [7:0]  data_in,
  input  logic [31:0] cfg,

  input  logic [15:0] drop_cnt,

  input  logic        local_vld,
  input  logic        local_rdy,
  input  logic [7:0]  data_local,

  input  logic        remote_vld,
  input  logic        remote_rdy,
  input  logic [31:0] data_remote
);

  // ----------------------------------------------------------
  // A1 - Reset behavior (spec Section 9):
  // "All valid outputs are deasserted" and "drop_cnt is cleared
  // to zero" while rst_n is low.
  // ----------------------------------------------------------
  property p_reset_deasserts_local_vld;
    @(posedge clk) (!rst_n) |-> (local_vld === 1'b0);
  endproperty
  assert property (p_reset_deasserts_local_vld)
    else $error("[SVA][A1a] local_vld not deasserted during reset");

  property p_reset_deasserts_remote_vld;
    @(posedge clk) (!rst_n) |-> (remote_vld === 1'b0);
  endproperty
  assert property (p_reset_deasserts_remote_vld)
    else $error("[SVA][A1b] remote_vld not deasserted during reset");

  property p_reset_clears_drop_cnt;
    @(posedge clk) (!rst_n) |-> (drop_cnt === 16'h0000);
  endproperty
  assert property (p_reset_clears_drop_cnt)
    else $error("[SVA][A1c] drop_cnt not cleared during reset");

  // ----------------------------------------------------------
  // A2 - Stability rule, extended to the output interfaces
  // (spec Section 3: "All interfaces use a valid/ready
  // handshake", Section 3.2: data/control must remain stable
  // while vld=1 and rdy=0). The textual example in the spec is
  // input-side, but the same handshake discipline is the only
  // sensible contract for the local/remote PRODUCER side too -
  // a consumer that stalls (rdy=0) must see the SAME word held
  // stable, not a new/different one, until it is accepted.
  // ----------------------------------------------------------
  property p_local_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
      (local_vld && !local_rdy) |=> (local_vld === $past(local_vld) &&
                                      data_local === $past(data_local));
  endproperty
  assert property (p_local_stable_when_stalled)
    else $error("[SVA][A2a] local_vld/data_local changed while stalled (local_rdy=0)");

  property p_remote_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
      (remote_vld && !remote_rdy) |=> (remote_vld === $past(remote_vld) &&
                                        data_remote === $past(data_remote));
  endproperty
  assert property (p_remote_stable_when_stalled)
    else $error("[SVA][A2b] remote_vld/data_remote changed while stalled (remote_rdy=0)");

  // ----------------------------------------------------------
  // A3 - Behavioral model assumption (file header, design/bird.sv):
  // "Behavioral: in_rdy always 1 (no input backpressure
  // modeling)." Guards against a future edit accidentally
  // breaking this documented assumption, which several
  // testbench timing calculations (e.g. driver byte-pump
  // cycle counts) implicitly rely on.
  // ----------------------------------------------------------
  property p_in_rdy_always_high;
    @(posedge clk) disable iff (!rst_n) (in_rdy === 1'b1);
  endproperty
  assert property (p_in_rdy_always_high)
    else $error("[SVA][A3] in_rdy deasserted - behavioral model assumption violated");

  // ----------------------------------------------------------
  // A4 - Drop counter behavior (spec Section 8.2): "drop_cnt
  // increments by one for each packet that is dropped" and "is
  // a modulo-2^16 counter". On any cycle where drop_cnt changes,
  // it must change by exactly +1 modulo 65536 - never by more
  // than one step, and never decrease except via the documented
  // wraparound (0xFFFF -> 0x0000).
  // ----------------------------------------------------------
  property p_drop_cnt_single_step;
    @(posedge clk) disable iff (!rst_n)
      (drop_cnt !== $past(drop_cnt)) |-> (drop_cnt === ($past(drop_cnt) + 16'd1));
  endproperty
  assert property (p_drop_cnt_single_step)
    else $error("[SVA][A4] drop_cnt changed by something other than +1 (mod 65536): was %0d now %0d",
                $past(drop_cnt), drop_cnt);

  // ----------------------------------------------------------
  // A5 - No unknown (X/Z) data on an asserted valid interface.
  // Basic sanity/X-propagation check: whenever a producer
  // asserts vld, the accompanying data must be fully known.
  // ----------------------------------------------------------
  property p_local_data_known_when_valid;
    @(posedge clk) disable iff (!rst_n) local_vld |-> !$isunknown(data_local);
  endproperty
  assert property (p_local_data_known_when_valid)
    else $error("[SVA][A5a] data_local contains X/Z while local_vld=1");

  property p_remote_data_known_when_valid;
    @(posedge clk) disable iff (!rst_n) remote_vld |-> !$isunknown(data_remote);
  endproperty
  assert property (p_remote_data_known_when_valid)
    else $error("[SVA][A5b] data_remote contains X/Z while remote_vld=1");

  // ----------------------------------------------------------
  // A6 - cfg/data_in must be known whenever in_vld is asserted
  // (spec Section 2.2/2.3: cfg is sampled with the first payload
  // byte and must be valid for the duration of the transfer).
  // ----------------------------------------------------------
  property p_input_known_when_valid;
    @(posedge clk) disable iff (!rst_n)
      in_vld |-> (!$isunknown(data_in) && !$isunknown(cfg));
  endproperty
  assert property (p_input_known_when_valid)
    else $error("[SVA][A6] data_in/cfg contains X/Z while in_vld=1");

endmodule

bind BIRD bird_assertions bird_sva_inst (.*);

`endif // BIRD_ASSERTIONS_SV
