
`ifndef GENERATOR_SV
`define GENERATOR_SV

`include "transaction.sv"

class generator;

  mailbox #(transaction) gen2drv_mbx;  // generator -> driver
  event                   drv_done_ev; // optional: driver signals completion (for lock-step gen)

  int unsigned num_transactions; // how many random transactions to generate
  int unsigned txn_sent;

  function new(mailbox #(transaction) gen2drv_mbx, event drv_done_ev = null);
    this.gen2drv_mbx = gen2drv_mbx;
    this.drv_done_ev = drv_done_ev;
    this.num_transactions = 0;
    this.txn_sent = 0;
  endfunction

  function transaction gen_random_local(int unsigned seq = 0, int unsigned payload_len = 0);
    transaction t = new();
    if (!t.randomize() with {
          traffic_type == 1'b0;
          frag_num     == 5'd1;
          reserved_7_1   == 7'd0;
          reserved_23_21 == 3'd0;
          reserved_31_29 == 3'd0;
          seq_num inside {[1:31]};
        }) begin
      $error("[GEN] Randomization failed for random local txn");
    end
    if (seq != 0)         t.seq_num     = seq[4:0];
    if (payload_len != 0) begin
      t.payload_len = payload_len[7:0];
      t.payload     = new[payload_len];
      foreach (t.payload[i]) t.payload[i] = $urandom_range(0, 255);
    end
    return t;
  endfunction

  // ----------------------------------------------------------
  // Random remote fragment (legal ranges)
  // ----------------------------------------------------------
  function transaction gen_random_remote_frag(int unsigned seq, int unsigned frag,
                                                int unsigned payload_len = 0);
    transaction t = new();
    if (!t.randomize() with {
          traffic_type == 1'b1;
          reserved_7_1   == 7'd0;
          reserved_23_21 == 3'd0;
          reserved_31_29 == 3'd0;
        }) begin
      $error("[GEN] Randomization failed for random remote frag");
    end
    t.seq_num  = seq[4:0];
    t.frag_num = frag[4:0];
    if (payload_len == 0) payload_len = $urandom_range(1, 32);
    t.payload_len = payload_len[7:0];
    t.payload     = new[payload_len];
    foreach (t.payload[i]) t.payload[i] = $urandom_range(0, 255);
    return t;
  endfunction

  // ----------------------------------------------------------
  // Directed: build a complete legal remote packet (N fragments,
  // fragments returned IN ORDER 1..N - caller may shuffle order)
  // ----------------------------------------------------------
  function void gen_remote_packet_frags(int unsigned seq, int unsigned n_frags,
                                         output transaction frags[]);
    frags = new[n_frags];
    for (int f = 1; f <= n_frags; f++) begin
      frags[f-1] = gen_random_remote_frag(seq, f);
    end
  endfunction

  // ----------------------------------------------------------
  // Directed: malformed cfg generator helpers
  // ----------------------------------------------------------
  function transaction gen_bad_reserved_bits(bit remote = 0);
    transaction t = new();
    void'(t.randomize() with {
      traffic_type == remote;
      frag_num inside {[1:31]};
      seq_num  inside {[1:31]};
    });
    t.reserved_7_1 = 7'h1; // violate reserved-must-be-zero rule
    return t;
  endfunction

  function transaction gen_zero_seq(bit remote = 1);
    transaction t = new();
    void'(t.randomize() with {
      traffic_type == remote;
      frag_num inside {[1:31]};
      reserved_7_1   == 7'd0;
      reserved_23_21 == 3'd0;
      reserved_31_29 == 3'd0;
    });
    t.seq_num = 5'd0; // illegal
    return t;
  endfunction

  function transaction gen_zero_frag(bit remote = 1);
    transaction t = new();
    void'(t.randomize() with {
      traffic_type == remote;
      seq_num inside {[1:31]};
      reserved_7_1   == 7'd0;
      reserved_23_21 == 3'd0;
      reserved_31_29 == 3'd0;
    });
    t.frag_num = 5'd0; // illegal
    return t;
  endfunction

  function transaction gen_zero_payload_len(bit remote = 0);
    transaction t = new();
    t.traffic_type   = remote;
    t.frag_num       = 1;
    t.seq_num        = 1;
    t.reserved_7_1   = 0;
    t.reserved_23_21 = 0;
    t.reserved_31_29 = 0;
    t.payload_len    = 8'd0; // illegal (outside 1-255)
    t.payload        = new[0];
    return t;
  endfunction

  // ----------------------------------------------------------
  // Push a single transaction into the mailbox (blocking put)
  // ----------------------------------------------------------
  task send(transaction t);
    gen2drv_mbx.put(t);
    txn_sent++;
  endtask

  // ----------------------------------------------------------
  // Main random-traffic run loop (used by simple random tests)
  // ----------------------------------------------------------
  task run();
    transaction t;
    for (int i = 0; i < num_transactions; i++) begin
      if ($urandom_range(0, 1)) begin
        t = gen_random_local();
      end else begin
        t = gen_random_remote_frag($urandom_range(1, 31), $urandom_range(1, 31));
      end
      send(t);
    end
  endtask

endclass

`endif // GENERATOR_SV
