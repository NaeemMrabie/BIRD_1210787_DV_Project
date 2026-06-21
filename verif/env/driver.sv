// ============================================================
// driver.sv
// ------------------------------------------------------------
// Driver: pulls transactions from the generator mailbox and
// drives them onto the BIRD input interface, byte by byte,
// strictly following the spec's interface protocol:
//   - cfg is sampled by DUT on the SAME cycle as the first
//     payload byte of each fragment -> driver places cfg on
//     the bus together with the first payload byte.
//   - Transfer occurs when vld=1 AND rdy=1 on a rising edge.
//   - When vld=1 and rdy=0, data/control must remain STABLE
//     (handled naturally here since we only advance on rdy=1,
//     i.e. we hold values until accepted).
//   - Stream = payload bytes (payload_len) then 2 CRC bytes.
//
// Also drives local_rdy / remote_rdy (the TB acts as consumer
// on the output side too) according to a configurable
// backpressure mode, to verify the Stability Rule.
// ============================================================

`ifndef DRIVER_SV
`define DRIVER_SV

`include "transaction.sv"

class driver;

  virtual bird_if.DRV vif;
  mailbox #(transaction) gen2drv_mbx;  // generator -> driver
  mailbox #(transaction) drv2mon_mbx;  // OPTIONAL: driver can push "as-sent" txn for self-checking refs

  // Backpressure control knobs (randomized per-byte or fixed by test)
  int unsigned local_rdy_low_pct;   // % chance local_rdy deasserted each cycle (0 = always ready)
  int unsigned remote_rdy_low_pct;  // % chance remote_rdy deasserted each cycle
  int unsigned in_vld_gap_pct;      // % chance of inserting an idle (vld=0) cycle before a fragment

  int unsigned num_sent;

  function new(virtual bird_if.DRV vif,
               mailbox #(transaction) gen2drv_mbx,
               mailbox #(transaction) drv2mon_mbx = null);
    this.vif               = vif;
    this.gen2drv_mbx        = gen2drv_mbx;
    this.drv2mon_mbx        = drv2mon_mbx;
    this.local_rdy_low_pct  = 0;
    this.remote_rdy_low_pct = 0;
    this.in_vld_gap_pct     = 0;
    this.num_sent           = 0;
  endfunction

  // ----------------------------------------------------------
  // Reset the input-side signals to idle
  // ----------------------------------------------------------
  task reset_signals();
    vif.drv_cb.in_vld     <= 1'b0;
    vif.drv_cb.data_in    <= 8'h00;
    vif.drv_cb.cfg        <= 32'h0;
    vif.drv_cb.local_rdy  <= 1'b1;
    vif.drv_cb.remote_rdy <= 1'b1;
  endtask

  // ----------------------------------------------------------
  // Background process: randomly toggle local_rdy/remote_rdy
  // to exercise backpressure / stability rule. Run as a
  // separate fork in the environment/test if desired.
  // ----------------------------------------------------------
  task drive_backpressure();
    forever begin
      @(vif.drv_cb);
      if (local_rdy_low_pct > 0)
        vif.drv_cb.local_rdy <= ($urandom_range(0, 99) >= local_rdy_low_pct);
      if (remote_rdy_low_pct > 0)
        vif.drv_cb.remote_rdy <= ($urandom_range(0, 99) >= remote_rdy_low_pct);
    end
  endtask

  // ----------------------------------------------------------
  // Drive ONE fragment transaction onto data_in/cfg following
  // the exact handshake & sampling rules from the spec.
  // ----------------------------------------------------------
  task drive_one(transaction t);
    byte unsigned crc0, crc1;

    // Optional idle gap before this fragment to vary timing
    if (in_vld_gap_pct > 0 && $urandom_range(0, 99) < in_vld_gap_pct) begin
      vif.drv_cb.in_vld <= 1'b0;
      @(vif.drv_cb);
    end

    // ---- First payload byte: drive cfg + data_in together ----
    vif.drv_cb.cfg    <= t.get_cfg();
    vif.drv_cb.in_vld <= 1'b1;

    if (t.payload.size() > 0)
      vif.drv_cb.data_in <= t.payload[0];
    else
      vif.drv_cb.data_in <= 8'h00; // degenerate (illegal payload_len==0 case)

    // Wait for handshake acceptance of this byte (vld=1 & rdy=1),
    // holding values stable while rdy=0 (Stability Rule).
    do begin
      @(vif.drv_cb);
    end while (!vif.drv_cb.in_rdy);

    // ---- Remaining payload bytes [1 .. payload_len-1] ----
    for (int unsigned i = 1; i < t.payload.size(); i++) begin
      vif.drv_cb.data_in <= t.payload[i];
      // cfg is only required to be valid/stable during the fragment;
      // keep driving the same cfg value (harmless, mirrors spec note
      // that cfg "applies to" the fragment currently transferring).
      vif.drv_cb.cfg <= t.get_cfg();
      do begin
        @(vif.drv_cb);
      end while (!vif.drv_cb.in_rdy);
    end

    // ---- CRC bytes (2 bytes). Spec: input CRC is not checked. ----
    if (t.use_random_crc) begin
      crc0 = $urandom_range(0, 255);
      crc1 = $urandom_range(0, 255);
    end else begin
      crc0 = t.crc_bytes[0];
      crc1 = t.crc_bytes[1];
    end
    if (t.force_bad_crc) begin
      crc0 = ~crc0;
      crc1 = ~crc1;
    end
    t.crc_bytes[0] = crc0;
    t.crc_bytes[1] = crc1;

    vif.drv_cb.data_in <= crc0;
    do begin
      @(vif.drv_cb);
    end while (!vif.drv_cb.in_rdy);

    vif.drv_cb.data_in <= crc1;
    do begin
      @(vif.drv_cb);
    end while (!vif.drv_cb.in_rdy);

    // ---- Deassert vld between fragments ----
    vif.drv_cb.in_vld  <= 1'b0;
    vif.drv_cb.data_in <= 8'h00;
    vif.drv_cb.cfg     <= 32'h0;

    num_sent++;

    if (drv2mon_mbx != null) drv2mon_mbx.put(t.copy());
  endtask

  // ----------------------------------------------------------
  // Main run loop: forever pull from generator mailbox and
  // drive each fragment.
  // ----------------------------------------------------------
  task run();
    transaction t;
    forever begin
      gen2drv_mbx.get(t);
      drive_one(t);
    end
  endtask

endclass

`endif // DRIVER_SV
