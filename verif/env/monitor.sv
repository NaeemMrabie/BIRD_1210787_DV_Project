// ============================================================
// monitor.sv
// ------------------------------------------------------------
// Monitor: passively observes the bird_if and reconstructs:
//   1. Input fragments  (cfg + full payload, as seen on the
//      wire) -> pushed to scoreboard for reference-model feed.
//   2. Local output byte stream -> pushed to scoreboard.
//   3. Remote output word stream -> pushed to scoreboard.
//   4. drop_cnt value changes -> pushed to scoreboard.
//
// All sampling is done strictly via the monitor clocking block
// (mon_cb), which already provides settled post-edge values.
// ============================================================

`ifndef MONITOR_SV
`define MONITOR_SV

`include "transaction.sv"

// Simple container for an observed local-output byte
class local_byte_obs;
  byte unsigned data;
  function new(byte unsigned d);
    data = d;
  endfunction
endclass

// Simple container for an observed remote-output word
class remote_word_obs;
  bit [31:0] data;
  function new(bit [31:0] d);
    data = d;
  endfunction
endclass

class monitor;

  virtual bird_if.MON vif;

  mailbox #(transaction)      mon2sb_input_mbx;   // input fragment observed -> scoreboard
  mailbox #(local_byte_obs)   mon2sb_local_mbx;   // local output byte -> scoreboard
  mailbox #(remote_word_obs)  mon2sb_remote_mbx;  // remote output word -> scoreboard
  mailbox #(bit [15:0])       mon2sb_dropcnt_mbx; // drop_cnt sample -> scoreboard

  function new(virtual bird_if.MON vif,
               mailbox #(transaction)     mon2sb_input_mbx,
               mailbox #(local_byte_obs)  mon2sb_local_mbx,
               mailbox #(remote_word_obs) mon2sb_remote_mbx,
               mailbox #(bit [15:0])      mon2sb_dropcnt_mbx);
    this.vif                 = vif;
    this.mon2sb_input_mbx    = mon2sb_input_mbx;
    this.mon2sb_local_mbx    = mon2sb_local_mbx;
    this.mon2sb_remote_mbx   = mon2sb_remote_mbx;
    this.mon2sb_dropcnt_mbx  = mon2sb_dropcnt_mbx;
  endfunction

  // ----------------------------------------------------------
  // Watch the INPUT side: reconstruct each fragment exactly as
  // transferred (cfg sampled with first payload byte; spec
  // section 2.3), and forward the reconstructed fragment
  // (transaction) to the scoreboard's reference model feed.
  // ----------------------------------------------------------
  task watch_input();
    typedef enum {W_IDLE, W_PAYLOAD, W_CRC} wst_e;
    wst_e        st;
    transaction  cur;
    int unsigned payload_left;
    int unsigned crc_left;

    st = W_IDLE;

    forever begin
      @(vif.mon_cb);
      if (!vif.rst_n) begin
        st = W_IDLE;
        continue;
      end

      if (vif.mon_cb.in_vld && vif.mon_cb.in_rdy) begin
        case (st)
          W_IDLE: begin
            cur = new();
            cur.set_from_cfg(vif.mon_cb.cfg);
            cur.payload = new[cur.payload_len];
            if (cur.payload_len > 0) cur.payload[0] = vif.mon_cb.data_in;

            payload_left = (cur.payload_len > 0) ? (cur.payload_len - 1) : 0;
            crc_left     = 2;

            if (payload_left == 0) st = W_CRC;
            else                   st = W_PAYLOAD;
          end

          W_PAYLOAD: begin
            int unsigned idx;
            idx = cur.payload_len - payload_left;
            if (idx < cur.payload.size()) cur.payload[idx] = vif.mon_cb.data_in;
            payload_left--;
            if (payload_left == 0) st = W_CRC;
          end

          W_CRC: begin
            if (crc_left == 2) cur.crc_bytes[0] = vif.mon_cb.data_in;
            else                cur.crc_bytes[1] = vif.mon_cb.data_in;
            crc_left--;
            if (crc_left == 0) begin
              // Fragment fully observed -> ship to scoreboard
              mon2sb_input_mbx.put(cur);
              st = W_IDLE;
            end
          end
        endcase
      end
    end
  endtask

  // ----------------------------------------------------------
  // Watch the LOCAL output stream (byte at a time)
  // ----------------------------------------------------------
  task watch_local();
    forever begin
      @(vif.mon_cb);
      if (!vif.rst_n) continue;
      if (vif.mon_cb.local_vld && vif.mon_cb.local_rdy) begin
        local_byte_obs b = new(vif.mon_cb.data_local);
        mon2sb_local_mbx.put(b);
      end
    end
  endtask

  // ----------------------------------------------------------
  // Watch the REMOTE output stream (word at a time)
  // ----------------------------------------------------------
  task watch_remote();
    forever begin
      @(vif.mon_cb);
      if (!vif.rst_n) continue;
      if (vif.mon_cb.remote_vld && vif.mon_cb.remote_rdy) begin
        remote_word_obs w = new(vif.mon_cb.data_remote);
        mon2sb_remote_mbx.put(w);
      end
    end
  endtask

  // ----------------------------------------------------------
  // Watch drop_cnt for changes and forward every sampled value
  // (scoreboard tracks the running count and compares deltas)
  // ----------------------------------------------------------
  task watch_dropcnt();
    bit [15:0] prev;
    prev = 16'h0;
    forever begin
      @(vif.mon_cb);
      if (!vif.rst_n) begin
        prev = 16'h0;
        continue;
      end
      if (vif.mon_cb.drop_cnt !== prev) begin
        mon2sb_dropcnt_mbx.put(vif.mon_cb.drop_cnt);
        prev = vif.mon_cb.drop_cnt;
      end
    end
  endtask

  // ----------------------------------------------------------
  // Launch all monitor processes concurrently
  // ----------------------------------------------------------
  task run();
    fork
      watch_input();
      watch_local();
      watch_remote();
      watch_dropcnt();
    join_none
  endtask

endclass

`endif // MONITOR_SV
