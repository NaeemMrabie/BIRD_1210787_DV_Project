// ============================================================
// scoreboard.sv
// ------------------------------------------------------------
// Scoreboard: receives observed input fragments from the
// monitor, feeds them into the independent reference model,
// and compares the reference model's expected outputs against
// the actually observed DUT outputs (local bytes, remote words,
// drop_cnt changes).
//
// Comparison strategy:
//  - Local: expected bytes queue (from ref model) vs observed
//    bytes queue (from monitor) - strict in-order byte compare.
//  - Remote: expected words queue (from ref model, includes the
//    final CRC word) vs observed words queue - strict in-order
//    32-bit word compare.
//  - drop_cnt: every time the monitor reports a NEW drop_cnt
//    value, it must match the reference model's expected value
//    at that point. Since the reference model updates drop_cnt
//    synchronously as soon as it processes a fragment (which is
//    itself reported by the monitor right after the fragment's
//    last CRC byte is transferred), the comparison is effectively
//    same-fragment, not "eventually consistent" - mismatches are
//    flagged with the actual vs expected pair for debug.
// ============================================================

`ifndef SCOREBOARD_SV
`define SCOREBOARD_SV

`include "transaction.sv"
`include "monitor.sv"
`include "ref_model.sv"
`include "coverage.sv"

class scoreboard;

  mailbox #(transaction)      mon2sb_input_mbx;
  mailbox #(local_byte_obs)   mon2sb_local_mbx;
  mailbox #(remote_word_obs)  mon2sb_remote_mbx;
  mailbox #(bit [15:0])       mon2sb_dropcnt_mbx;

  ref_model rm;
  bird_coverage cov;

  // Pass/fail bookkeeping
  int unsigned local_match_cnt,  local_mismatch_cnt;
  int unsigned remote_match_cnt, remote_mismatch_cnt;
  int unsigned dropcnt_match_cnt, dropcnt_mismatch_cnt;

  function new(mailbox #(transaction)     mon2sb_input_mbx,
               mailbox #(local_byte_obs)  mon2sb_local_mbx,
               mailbox #(remote_word_obs) mon2sb_remote_mbx,
               mailbox #(bit [15:0])      mon2sb_dropcnt_mbx);
    this.mon2sb_input_mbx   = mon2sb_input_mbx;
    this.mon2sb_local_mbx   = mon2sb_local_mbx;
    this.mon2sb_remote_mbx  = mon2sb_remote_mbx;
    this.mon2sb_dropcnt_mbx = mon2sb_dropcnt_mbx;
    this.rm = new();
    this.cov = new();
    local_match_cnt       = 0;
    local_mismatch_cnt    = 0;
    remote_match_cnt      = 0;
    remote_mismatch_cnt   = 0;
    dropcnt_match_cnt     = 0;
    dropcnt_mismatch_cnt  = 0;
  endfunction

  // ----------------------------------------------------------
  // Feed every observed input fragment into the reference model
  // ----------------------------------------------------------
  task feed_ref_model();
    transaction t;
    forever begin
      mon2sb_input_mbx.get(t);
      cov.sample_input(t);
      rm.process_fragment(t);
    end
  endtask

  // ----------------------------------------------------------
  // Compare LOCAL output bytes against the reference model's
  // expected local-byte queue, one at a time, in order.
  // ----------------------------------------------------------
  task check_local();
    local_byte_obs obs;
    forever begin
      mon2sb_local_mbx.get(obs);
      // Wait until the ref model has produced at least one
      // expected byte (it is fed synchronously by feed_ref_model,
      // which runs concurrently; a short wait protects against
      // any scheduling race in the same time step).
      wait (rm.exp_local_q.size() > 0);
      begin
        ref_local_byte exp;
        exp = rm.exp_local_q.pop_front();
        if (obs.data === exp.data) begin
          local_match_cnt++;
        end else begin
          local_mismatch_cnt++;
          $error("[SB][LOCAL] MISMATCH: observed=0x%0h expected=0x%0h (match#%0d mismatch#%0d)",
                 obs.data, exp.data, local_match_cnt, local_mismatch_cnt);
        end
      end
    end
  endtask

  // ----------------------------------------------------------
  // Compare REMOTE output words against the reference model's
  // expected remote-word queue, one at a time, in order.
  // ----------------------------------------------------------
  task check_remote();
    remote_word_obs obs;
    forever begin
      mon2sb_remote_mbx.get(obs);
      wait (rm.exp_remote_words_q.size() > 0);
      begin
        bit [31:0] exp;
        exp = rm.exp_remote_words_q.pop_front();
        if (obs.data === exp) begin
          remote_match_cnt++;
        end else begin
          remote_mismatch_cnt++;
          $error("[SB][REMOTE] MISMATCH: observed=0x%0h expected=0x%0h (match#%0d mismatch#%0d)",
                 obs.data, exp, remote_match_cnt, remote_mismatch_cnt);
        end
      end
    end
  endtask

  // ----------------------------------------------------------
  // Compare drop_cnt changes against the reference model value
  // ----------------------------------------------------------
  task check_dropcnt();
    bit [15:0] obs;
    forever begin
      mon2sb_dropcnt_mbx.get(obs);
      cov.sample_drop_cnt(obs);
      if (obs === rm.exp_drop_cnt) begin
        dropcnt_match_cnt++;
      end else begin
        dropcnt_mismatch_cnt++;
        $error("[SB][DROP_CNT] MISMATCH: observed=%0d expected=%0d (match#%0d mismatch#%0d)",
               obs, rm.exp_drop_cnt, dropcnt_match_cnt, dropcnt_mismatch_cnt);
      end
    end
  endtask

  // ----------------------------------------------------------
  // Launch all scoreboard processes concurrently
  // ----------------------------------------------------------
  task run();
    fork
      feed_ref_model();
      check_local();
      check_remote();
      check_dropcnt();
    join_none
  endtask

  // ----------------------------------------------------------
  // Final report (call at end of test)
  // ----------------------------------------------------------
  function void report();
    $display("==================================================");
    $display("[SCOREBOARD] FINAL REPORT");
    $display("  LOCAL : match=%0d mismatch=%0d pending_expected=%0d",
              local_match_cnt, local_mismatch_cnt, rm.exp_local_q.size());
    $display("  REMOTE: match=%0d mismatch=%0d pending_expected=%0d",
              remote_match_cnt, remote_mismatch_cnt, rm.exp_remote_words_q.size());
    $display("  DROP_CNT: match=%0d mismatch=%0d final_expected=%0d",
              dropcnt_match_cnt, dropcnt_mismatch_cnt, rm.exp_drop_cnt);
    cov.report();
    if (local_mismatch_cnt == 0 && remote_mismatch_cnt == 0 && dropcnt_mismatch_cnt == 0 &&
        rm.exp_local_q.size() == 0 && rm.exp_remote_words_q.size() == 0) begin
      $display("  RESULT: PASS");
    end else begin
      $display("  RESULT: FAIL");
    end
    $display("==================================================");
  endfunction

endclass

`endif // SCOREBOARD_SV
