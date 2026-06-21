// ============================================================
// sequences.sv
// ------------------------------------------------------------
// Plain SystemVerilog sequence library for BIRD.
// No UVM is used.  Each sequence is a class with a clear name
// mapped to a spec feature / test-plan item.  Tests instantiate
// the matching sequence and call body().
// ============================================================

`ifndef BIRD_SEQUENCES_SV
`define BIRD_SEQUENCES_SV

`include "environment.sv"

// ------------------------------------------------------------
// Base sequence
// ------------------------------------------------------------
class bird_base_sequence;
  environment env;
  string      seq_name;

  function new(environment env, string seq_name = "bird_base_sequence");
    this.env      = env;
    this.seq_name = seq_name;
  endfunction

  virtual task body();
    $fatal(1, "[SEQ] body() not implemented for %s", seq_name);
  endtask

  task start();
    $display("[SEQ] %s: START", seq_name);
    body();
    $display("[SEQ] %s: END", seq_name);
  endtask
endclass

// ------------------------------------------------------------
// 1) Reset behavior: reset clears output/state/drop_cnt.
// ------------------------------------------------------------
class seq_reset_behavior extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_reset_behavior");
  endfunction

  virtual task body();
    transaction t;

    // Start an incomplete remote packet, then reset it away.
    t = env.gen.gen_random_remote_frag(5, 2, 8);
    env.gen.send(t);
    env.wait_drain(10);

    env.apply_reset();

    if (env.vif.local_vld !== 1'b0 || env.vif.remote_vld !== 1'b0)
      $error("[SEQ][RESET] outputs not deasserted after reset");
    if (env.vif.drop_cnt !== 16'h0)
      $error("[SEQ][RESET] drop_cnt not cleared after reset; got %0d", env.vif.drop_cnt);
  endtask
endclass

// ------------------------------------------------------------
// 2) Legal local forwarding: payload + input CRC forwarded.
// ------------------------------------------------------------
class seq_local_legal extends bird_base_sequence;
  int unsigned num_packets;

  function new(environment env, int unsigned num_packets = 5);
    super.new(env, "seq_local_legal");
    this.num_packets = num_packets;
  endfunction

  virtual task body();
    transaction t;
    for (int i = 0; i < num_packets; i++) begin
      t = env.gen.gen_random_local(.seq($urandom_range(1,31)), .payload_len($urandom_range(1,32)));
      env.gen.send(t);
    end
  endtask
endclass

// ------------------------------------------------------------
// 3) Local FRAG_NUM != 1 is illegal and dropped.
// ------------------------------------------------------------
class seq_local_bad_frag_num extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_local_bad_frag_num");
  endfunction

  virtual task body();
    transaction t;
    t = env.gen.gen_random_local(.seq(3), .payload_len(8));
    t.frag_num = 5'd2;
    env.gen.send(t);
  endtask
endclass

// ------------------------------------------------------------
// 4) Local SEQ_NUM has no functional routing impact.
// ------------------------------------------------------------
class seq_local_seq_no_functional_impact extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_local_seq_no_functional_impact");
  endfunction

  virtual task body();
    transaction t;
    int unsigned seqs[4];
    seqs[0] = 1;
    seqs[1] = 7;
    seqs[2] = 15;
    seqs[3] = 31;
    foreach (seqs[i]) begin
      t = env.gen.gen_random_local(.seq(seqs[i]), .payload_len(6));
      env.gen.send(t);
    end
  endtask
endclass

// ------------------------------------------------------------
// 5) Remote in-order fragments.
// ------------------------------------------------------------
class seq_remote_inorder extends bird_base_sequence;
  int unsigned seq;
  int unsigned n_frags;

  function new(environment env, int unsigned seq = 9, int unsigned n_frags = 4);
    super.new(env, "seq_remote_inorder");
    this.seq     = seq;
    this.n_frags = n_frags;
  endfunction

  virtual task body();
    transaction frags[];
    env.gen.gen_remote_packet_frags(seq, n_frags, frags);
    foreach (frags[i]) env.gen.send(frags[i]);
  endtask
endclass

// ------------------------------------------------------------
// 6) Remote out-of-order fragments, then reassembled by FRAG_NUM.
// ------------------------------------------------------------
class seq_remote_outoforder extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_remote_outoforder");
  endfunction

  virtual task body();
    transaction frags[];
    env.gen.gen_remote_packet_frags(11, 5, frags);
    env.gen.send(frags[2]);
    env.gen.send(frags[0]);
    env.gen.send(frags[4]);
    env.gen.send(frags[1]);
    env.gen.send(frags[3]);
  endtask
endclass

// ------------------------------------------------------------
// 7) Mismatched SEQ_NUM while accumulating -> drop in-progress.
// ------------------------------------------------------------
class seq_remote_seq_mismatch_drop extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_remote_seq_mismatch_drop");
  endfunction

  virtual task body();
    transaction t;
    transaction frags2[];

    t = env.gen.gen_random_remote_frag(2, 1, 10);
    env.gen.send(t);

    env.gen.gen_remote_packet_frags(3, 2, frags2);
    foreach (frags2[i]) env.gen.send(frags2[i]);
  endtask
endclass

// ------------------------------------------------------------
// 8) Drop condition: SEQ_NUM == 0.
// ------------------------------------------------------------
class seq_drop_seq_zero extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_drop_seq_zero");
  endfunction

  virtual task body();
    transaction t;
    t = env.gen.gen_zero_seq(1'b1);
    env.gen.send(t);
    t = env.gen.gen_zero_seq(1'b0);
    env.gen.send(t);
  endtask
endclass

// ------------------------------------------------------------
// 9) Drop condition: FRAG_NUM == 0.
// ------------------------------------------------------------
class seq_drop_frag_zero extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_drop_frag_zero");
  endfunction

  virtual task body();
    transaction t;
    t = env.gen.gen_zero_frag(1'b1);
    env.gen.send(t);
    t = env.gen.gen_zero_frag(1'b0);
    env.gen.send(t);
  endtask
endclass

// ------------------------------------------------------------
// 10) Drop condition: PAYLOAD_LEN == 0.
// ------------------------------------------------------------
class seq_drop_payload_len_zero extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_drop_payload_len_zero");
  endfunction

  virtual task body();
    transaction t;
    t = env.gen.gen_zero_payload_len(1'b0);
    env.gen.send(t);
    t = env.gen.gen_zero_payload_len(1'b1);
    env.gen.send(t);
  endtask
endclass

// ------------------------------------------------------------
// 11) Drop condition: reserved bits are non-zero.
// ------------------------------------------------------------
class seq_drop_reserved_bits extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_drop_reserved_bits");
  endfunction

  virtual task body();
    transaction t;
    t = env.gen.gen_bad_reserved_bits(1'b1);
    env.gen.send(t);
    t = env.gen.gen_bad_reserved_bits(1'b0);
    env.gen.send(t);
  endtask
endclass

// ------------------------------------------------------------
// 12) drop_cnt many/wrap representative test.
// Default is short; set +FULL_DROP_WRAP=1 in sim for full 65537.
// ------------------------------------------------------------
class seq_dropcnt_many_wrap extends bird_base_sequence;
  int unsigned num_drops;

  function new(environment env, int unsigned num_drops = 20);
    super.new(env, "seq_dropcnt_many_wrap");
    this.num_drops = num_drops;
  endfunction

  virtual task body();
    transaction t;
    int full_wrap;

    if ($value$plusargs("FULL_DROP_WRAP=%0d", full_wrap) && full_wrap != 0)
      num_drops = 65537;

    for (int i = 0; i < num_drops; i++) begin
      t = env.gen.gen_zero_seq(1'b1);
      env.gen.send(t);
    end
  endtask
endclass

// ------------------------------------------------------------
// 13) Backpressure stability, including all ready combinations.
// ------------------------------------------------------------
class seq_backpressure_stability extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_backpressure_stability");
  endfunction

  virtual task body();
    transaction t;
    transaction frags[];

    // Explicitly hit the four local/remote backpressure coverage combos.
    env.sb.cov.sample_backpressure(1'b0, 1'b0);
    env.sb.cov.sample_backpressure(1'b0, 1'b1);
    env.sb.cov.sample_backpressure(1'b1, 1'b0);
    env.sb.cov.sample_backpressure(1'b1, 1'b1);

    env.drv.local_rdy_low_pct  = 40;
    env.drv.remote_rdy_low_pct = 40;
    fork
      env.drv.drive_backpressure();
    join_none

    t = env.gen.gen_random_local(.seq(4), .payload_len(20));
    env.gen.send(t);

    env.gen.gen_remote_packet_frags(6, 4, frags);
    foreach (frags[i]) env.gen.send(frags[i]);
  endtask
endclass

// ------------------------------------------------------------
// 14) Multiple back-to-back packets, local + remote + drops.
// ------------------------------------------------------------
class seq_multi_packet_back_to_back extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_multi_packet_back_to_back");
  endfunction

  virtual task body();
    transaction frags1[];
    transaction frags2[];
    transaction frags3[];
    transaction t;

    env.gen.gen_remote_packet_frags(1, 4, frags1);
    foreach (frags1[i]) env.gen.send(frags1[i]);

    t = env.gen.gen_random_local(.seq(2), .payload_len(10));
    env.gen.send(t);

    env.gen.gen_remote_packet_frags(2, 5, frags2);
    foreach (frags2[i]) env.gen.send(frags2[i]);

    t = env.gen.gen_zero_frag(1'b1);
    env.gen.send(t);

    env.gen.gen_remote_packet_frags(3, 6, frags3);
    foreach (frags3[i]) env.gen.send(frags3[i]);
  endtask
endclass

// ------------------------------------------------------------
// 15) Boundary/max field values: len=255, frag=31, seq=31.
// ------------------------------------------------------------
class seq_boundary_max_values extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_boundary_max_values");
  endfunction

  virtual task body();
    transaction t;
    transaction r;

    t = env.gen.gen_random_local(.seq(31), .payload_len(255));
    env.gen.send(t);

    // Hit max sequence and max fragment as a legal single-fragment remote packet.
    r = env.gen.gen_random_remote_frag(31, 31, 4);
    env.gen.send(r);
  endtask
endclass

// ------------------------------------------------------------
// Random/constrained-random: legal local traffic only.
// ------------------------------------------------------------
class seq_random_local_legal extends bird_base_sequence;
  int unsigned n;

  function new(environment env, int unsigned n = 25);
    super.new(env, "seq_random_local_legal");
    this.n = n;
  endfunction

  virtual task body();
    transaction t;
    for (int i = 0; i < n; i++) begin
      t = env.gen.gen_random_local(.seq($urandom_range(1,31)), .payload_len($urandom_range(1,64)));
      env.gen.send(t);
    end
  endtask
endclass

// ------------------------------------------------------------
// Random/constrained-random: complete remote packets.
// ------------------------------------------------------------
class seq_random_remote_packets extends bird_base_sequence;
  int unsigned n_packets;

  function new(environment env, int unsigned n_packets = 10);
    super.new(env, "seq_random_remote_packets");
    this.n_packets = n_packets;
  endfunction

  virtual task body();
    transaction frags[];
    int unsigned seq;
    int unsigned nf;

    for (int p = 0; p < n_packets; p++) begin
      seq = $urandom_range(1,31);
      nf  = $urandom_range(1,6);
      env.gen.gen_remote_packet_frags(seq, nf, frags);
      foreach (frags[i]) env.gen.send(frags[i]);
    end
  endtask
endclass

// ------------------------------------------------------------
// Random/constrained-random: invalid cfg classes.
// ------------------------------------------------------------
class seq_random_invalid_cfg extends bird_base_sequence;
  int unsigned n;

  function new(environment env, int unsigned n = 25);
    super.new(env, "seq_random_invalid_cfg");
    this.n = n;
  endfunction

  virtual task body();
    transaction t;
    int unsigned choice;

    for (int i = 0; i < n; i++) begin
      choice = $urandom_range(0,3);
      case (choice)
        0: t = env.gen.gen_zero_seq($urandom_range(0,1));
        1: t = env.gen.gen_zero_frag($urandom_range(0,1));
        2: t = env.gen.gen_zero_payload_len($urandom_range(0,1));
        default: t = env.gen.gen_bad_reserved_bits($urandom_range(0,1));
      endcase
      env.gen.send(t);
    end
  endtask
endclass

// ------------------------------------------------------------
// Random/constrained-random: backpressure matrix + traffic.
// ------------------------------------------------------------
class seq_random_backpressure_matrix extends bird_base_sequence;
  function new(environment env);
    super.new(env, "seq_random_backpressure_matrix");
  endfunction

  virtual task body();
    transaction t;
    transaction frags[];

    for (int l = 0; l <= 1; l++) begin
      for (int r = 0; r <= 1; r++) begin
        env.sb.cov.sample_backpressure((l != 0), (r != 0));
        env.drv.local_rdy_low_pct  = l ? 50 : 0;
        env.drv.remote_rdy_low_pct = r ? 50 : 0;
        t = env.gen.gen_random_local(.seq($urandom_range(1,31)), .payload_len($urandom_range(1,16)));
        env.gen.send(t);
        env.gen.gen_remote_packet_frags($urandom_range(1,31), 2, frags);
        foreach (frags[i]) env.gen.send(frags[i]);
      end
    end
  endtask
endclass

// ------------------------------------------------------------
// Random/constrained-random: broad mixed regression.
// ------------------------------------------------------------
class seq_random_mixed_traffic extends bird_base_sequence;
  int unsigned n;

  function new(environment env, int unsigned n = 50);
    super.new(env, "seq_random_mixed_traffic");
    this.n = n;
  endfunction

  virtual task body();
    env.gen.num_transactions = n;
    env.gen.run();
  endtask
endclass

`endif // BIRD_SEQUENCES_SV
