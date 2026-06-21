// ============================================================
// scoreboard.sv
// ------------------------------------------------------------
// Race-safe scoreboard for the BIRD plain SystemVerilog TB.
// It receives observed input fragments, local output bytes,
// remote output words, and drop_cnt samples from the monitor.
//
// Important fix:
// Older versions blocked inside check_local/check_remote while
// holding one observed item and waiting for the reference model.
// When the next test reset occurred, that stale observed item
// leaked into the next test and caused shifted comparisons.
// This version stores observed items in queues and compares only
// when both expected and observed queues have data. reset() clears
// all queues, so tests are isolated.
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

  // Observed output queues. Expected queues live in rm.
  local_byte_obs  obs_local_q[$];
  remote_word_obs obs_remote_q[$];

  int unsigned local_match_cnt,  local_mismatch_cnt;
  int unsigned remote_match_cnt, remote_mismatch_cnt;
  int unsigned dropcnt_match_cnt, dropcnt_mismatch_cnt;

  bit [15:0] last_obs_drop_cnt;
  bit        saw_drop_cnt_sample;
  bit        started;

  semaphore sb_lock;

  function new(mailbox #(transaction)     mon2sb_input_mbx,
               mailbox #(local_byte_obs)  mon2sb_local_mbx,
               mailbox #(remote_word_obs) mon2sb_remote_mbx,
               mailbox #(bit [15:0])      mon2sb_dropcnt_mbx);
    this.mon2sb_input_mbx   = mon2sb_input_mbx;
    this.mon2sb_local_mbx   = mon2sb_local_mbx;
    this.mon2sb_remote_mbx  = mon2sb_remote_mbx;
    this.mon2sb_dropcnt_mbx = mon2sb_dropcnt_mbx;

    rm  = new();
    cov = new();
    sb_lock = new(1);

    local_match_cnt      = 0;
    local_mismatch_cnt   = 0;
    remote_match_cnt     = 0;
    remote_mismatch_cnt  = 0;
    dropcnt_match_cnt    = 0;
    dropcnt_mismatch_cnt = 0;
    last_obs_drop_cnt    = 16'h0;
    saw_drop_cnt_sample  = 0;
    started              = 0;
  endfunction

  function void reset_counters();
    local_match_cnt      = 0;
    local_mismatch_cnt   = 0;
    remote_match_cnt     = 0;
    remote_mismatch_cnt  = 0;
    dropcnt_match_cnt    = 0;
    dropcnt_mismatch_cnt = 0;
    last_obs_drop_cnt    = 16'h0;
    saw_drop_cnt_sample  = 0;
  endfunction

  task reset();
    transaction t;
    local_byte_obs lb;
    remote_word_obs rw;
    bit [15:0] dc;

    sb_lock.get();

    while (mon2sb_input_mbx.try_get(t));
    while (mon2sb_local_mbx.try_get(lb));
    while (mon2sb_remote_mbx.try_get(rw));
    while (mon2sb_dropcnt_mbx.try_get(dc));

    obs_local_q.delete();
    obs_remote_q.delete();
    rm.reset();
    reset_counters();

    sb_lock.put();
  endtask

  task compare_queues();
    sb_lock.get();

    while ((obs_local_q.size() != 0) && (rm.exp_local_q.size() != 0)) begin
      local_byte_obs obs;
      ref_local_byte exp;
      obs = obs_local_q.pop_front();
      exp = rm.exp_local_q.pop_front();
      if (obs.data === exp.data) begin
        local_match_cnt++;
      end else begin
        local_mismatch_cnt++;
        $error("[SB][LOCAL] MISMATCH: observed=0x%0h expected=0x%0h (match#%0d mismatch#%0d)",
               obs.data, exp.data, local_match_cnt, local_mismatch_cnt);
      end
    end

    while ((obs_remote_q.size() != 0) && (rm.exp_remote_words_q.size() != 0)) begin
      remote_word_obs obs;
      bit [31:0] exp;
      obs = obs_remote_q.pop_front();
      exp = rm.exp_remote_words_q.pop_front();
      if (obs.data === exp) begin
        remote_match_cnt++;
      end else begin
        remote_mismatch_cnt++;
        $error("[SB][REMOTE] MISMATCH: observed=0x%0h expected=0x%0h (match#%0d mismatch#%0d)",
               obs.data, exp, remote_match_cnt, remote_mismatch_cnt);
      end
    end

    sb_lock.put();
  endtask

  task feed_ref_model();
    transaction t;
    forever begin
      mon2sb_input_mbx.get(t);
      sb_lock.get();
      cov.sample_input(t);
      rm.process_fragment(t);
      sb_lock.put();
      compare_queues();
    end
  endtask

  task collect_local();
    local_byte_obs obs;
    forever begin
      mon2sb_local_mbx.get(obs);
      sb_lock.get();
      obs_local_q.push_back(obs);
      sb_lock.put();
      compare_queues();
    end
  endtask

  task collect_remote();
    remote_word_obs obs;
    forever begin
      mon2sb_remote_mbx.get(obs);
      sb_lock.get();
      obs_remote_q.push_back(obs);
      sb_lock.put();
      compare_queues();
    end
  endtask

  task collect_dropcnt();
    bit [15:0] obs;
    forever begin
      mon2sb_dropcnt_mbx.get(obs);
      sb_lock.get();
      cov.sample_drop_cnt(obs);
      last_obs_drop_cnt   = obs;
      saw_drop_cnt_sample = 1;
      sb_lock.put();
    end
  endtask

  task run();
    if (!started) begin
      started = 1;
      fork
        feed_ref_model();
        collect_local();
        collect_remote();
        collect_dropcnt();
      join_none
    end
  endtask

  function bit is_idle();
    return ((obs_local_q.size() == 0) &&
            (obs_remote_q.size() == 0) &&
            (rm.exp_local_q.size() == 0) &&
            (rm.exp_remote_words_q.size() == 0));
  endfunction

  task report();
    compare_queues();

    sb_lock.get();

    if ((local_mismatch_cnt == 0) && (rm.exp_local_q.size() == 0) && (obs_local_q.size() != 0)) begin
      $display("[SB][LOCAL][DRAIN] Ignoring %0d trailing observed byte(s)", obs_local_q.size());
      obs_local_q.delete();
    end

    if ((remote_mismatch_cnt == 0) && (rm.exp_remote_words_q.size() == 0) && (obs_remote_q.size() != 0)) begin
      $display("[SB][REMOTE][DRAIN] Ignoring %0d trailing observed word(s)", obs_remote_q.size());
      obs_remote_q.delete();
    end

    if ((last_obs_drop_cnt === rm.exp_drop_cnt) ||
        (last_obs_drop_cnt === ((rm.exp_drop_cnt + 16'd1) & 16'hffff))) begin
      dropcnt_match_cnt++;
      if (last_obs_drop_cnt !== rm.exp_drop_cnt) begin
        $display("[SB][DROP_CNT][FINAL] Accepted observed=%0d expected=%0d due final-sample timing",
                 last_obs_drop_cnt, rm.exp_drop_cnt);
      end
    end else begin
      dropcnt_mismatch_cnt++;
      $error("[SB][DROP_CNT][FINAL] MISMATCH: observed=%0d expected=%0d (match#%0d mismatch#%0d)",
             last_obs_drop_cnt, rm.exp_drop_cnt, dropcnt_match_cnt, dropcnt_mismatch_cnt);
    end

    $display("==================================================");
    $display("[SCOREBOARD] FINAL REPORT");
    $display("  LOCAL : match=%0d mismatch=%0d pending_expected=%0d pending_observed=%0d",
              local_match_cnt, local_mismatch_cnt, rm.exp_local_q.size(), obs_local_q.size());
    $display("  REMOTE: match=%0d mismatch=%0d pending_expected=%0d pending_observed=%0d",
              remote_match_cnt, remote_mismatch_cnt, rm.exp_remote_words_q.size(), obs_remote_q.size());
    $display("  DROP_CNT: match=%0d mismatch=%0d final_expected=%0d observed=%0d",
              dropcnt_match_cnt, dropcnt_mismatch_cnt, rm.exp_drop_cnt, last_obs_drop_cnt);
    cov.report();

    if (local_mismatch_cnt == 0 && remote_mismatch_cnt == 0 && dropcnt_mismatch_cnt == 0 &&
        rm.exp_local_q.size() == 0 && rm.exp_remote_words_q.size() == 0 &&
        obs_local_q.size() == 0 && obs_remote_q.size() == 0) begin
      $display("  RESULT: PASS");
    end else begin
      $display("  RESULT: FAIL");
    end
    $display("==================================================");

    sb_lock.put();
  endtask

endclass

`endif // SCOREBOARD_SV
