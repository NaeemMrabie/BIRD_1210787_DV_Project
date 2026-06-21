// ============================================================
// ref_model.sv
// ------------------------------------------------------------
// Independent reference model, built ONLY from the functional
// specification (BIRD - Birzeit Integrated Router Design),
// NOT from the provided RTL. It intentionally does not look at
// (or try to mimic) any DUT implementation detail/bug.
//
// Responsibilities:
//  - Decide validity of each incoming fragment (Section 8.1)
//  - Classify local vs remote (cfg[0])
//  - Local: forward payload bytes [+ CRC bytes unchanged] when
//    legal (Section 6)
//  - Remote: accumulate fragments by SEQ_NUM, reorder by
//    FRAG_NUM, merge payload, regenerate CRC16, emit merged
//    32-bit-packed words + CRC word (Section 7)
//  - Maintain drop_cnt: +1 per dropped PACKET, not per fragment
//    (Section 8.2), modulo-2^16 wraparound
//  - Reset clears all state (Section 9)
//
// IMPORTANT SPEC READING NOTES (read carefully):
//  - Local traffic is a SINGLE fragment. FRAG_NUM must be 1.
//    SEQ_NUM identifies the packet but has NO functional impact
//    on local routing -> a local fragment with FRAG_NUM==1 and
//    ANY legal (nonzero, in-range) SEQ_NUM is valid. We do NOT
//    require SEQ_NUM==1 for local (unlike some RTL behavior).
//  - "Only one remote packet may be accumulated at a time."
//    A fragment with a SEQ_NUM different from the one currently
//    being accumulated causes the in-progress packet to be
//    dropped (Section 8.1, bullet 5).
//  - "A fragment with FRAG_NUM==1 arrives while a previous
//    packet with a different SEQ_NUM is still incomplete" is
//    ALSO an explicit drop condition (Section 8.1, bullet 7).
//    This is really the same scenario as bullet 5 phrased from
//    the "new packet start" angle; the model below treats any
//    mismatched-SEQ_NUM arrival (whatever its FRAG_NUM) while a
//    packet is active as a drop of the in-progress packet, then
//    evaluates whether the new fragment can legally start a new
//    packet (it can - remote fragments are not required to
//    start with FRAG_NUM==1; spec doesn't mandate that fragment
//    1 must arrive first, only that "fragments may arrive out
//    of order"). The replaced/dropped in-progress packet counts
//    as ONE dropped packet. The new fragment is then accepted
//    and starts a new accumulation context under its own
//    SEQ_NUM (subject to the same validity rules).
//  - "A required fragment for a packet is missing" -> this can
//    only be detected once we believe the packet is complete.
//    Since N (highest FRAG_NUM) is inferred from received
//    fragments and fragments may arrive out of order, this
//    model infers N as the maximum FRAG_NUM observed for the
//    active SEQ_NUM, and triggers reassembly check whenever a
//    fragment arrives whose FRAG_NUM does not exceed previously
//    seen ones is irrelevant - reassembly is attempted whenever
//    the set of fragments collected forms a contiguous 1..N
//    run for the current max FRAG_NUM seen. If a "gap" is later
//    proven impossible to fill (e.g. packet preempted by a new
//    SEQ_NUM), the missing-fragment drop fires at that point
//    (folded into the SEQ_NUM-mismatch drop above).
//  - CRC16 used for both (a) accepting input CRC: NOT checked
//    per spec ("Input CRC16... is not checked" - implied by
//    "BIRD does not signal errors" plus absence of any CRC
//    check in drop conditions) and (b) regenerating CRC16 for
//    the merged remote payload. This model uses CRC16-CCITT
//    (polynomial 0x1021, initial value 0xFFFF), the most common
//    convention in the absence of an explicit polynomial in the
//    spec. If your course staff specifies a different CRC16
//    variant, only the crc16() function below needs to change.
// ============================================================

`ifndef REF_MODEL_SV
`define REF_MODEL_SV

`include "transaction.sv"

// Output containers (mirrors monitor.sv definitions so the
// reference model can produce directly-comparable items)
class ref_local_byte;
  byte unsigned data;
  function new(byte unsigned d); data = d; endfunction
endclass

class ref_remote_word;
  bit [31:0] data;
  function new(bit [31:0] d); data = d; endfunction
endclass

class ref_model;

  // Expected output queues (consumed/compared by scoreboard)
  ref_local_byte  exp_local_q[$];
  bit [31:0]      exp_remote_words_q[$]; // raw words incl. final CRC word
  bit [15:0]      exp_drop_cnt;

  // ----------------------------------------------------------
  // Remote accumulation state (one active packet at a time)
  // ----------------------------------------------------------
  bit          active;
  bit [4:0]    active_seq;
  int unsigned active_max_frag;          // inferred N
  bit          frag_seen   [1:31];
  byte unsigned frag_payload[1:31][$];

  function new();
    reset();
  endfunction

  // ----------------------------------------------------------
  // Reset behavior (spec Section 9)
  // ----------------------------------------------------------
  function void reset();
    exp_local_q.delete();
    exp_remote_words_q.delete();
    exp_drop_cnt = 16'h0;
    clear_remote_state();
  endfunction

  function void clear_remote_state();
    active           = 0;
    active_seq       = 5'd0;
    active_max_frag  = 0;
    for (int f = 1; f <= 31; f++) begin
      frag_seen[f] = 0;
      frag_payload[f].delete();
    end
  endfunction

  // ----------------------------------------------------------
  // drop_cnt increment with modulo-2^16 wraparound (natural
  // wraparound of a 16-bit unsigned add)
  // ----------------------------------------------------------
  function void inc_drop();
    exp_drop_cnt = exp_drop_cnt + 16'd1;
  endfunction

  // Drop whatever remote packet is currently active (counts as
  // exactly one dropped packet), then clear state.
  function void drop_active_packet();
    if (active) inc_drop();
    clear_remote_state();
  endfunction

  // ----------------------------------------------------------
  // cfg-level validity check (Section 8.1, structural rules
  // that don't depend on accumulation state)
  // ----------------------------------------------------------
  function bit cfg_structurally_invalid(transaction t);
    bit inv;
    inv = 0;
    if (t.reserved_7_1   != 7'd0) inv = 1;
    if (t.reserved_23_21 != 3'd0) inv = 1;
    if (t.reserved_31_29 != 3'd0) inv = 1;
    if (t.payload_len == 8'd0)    inv = 1; // PAYLOAD_LEN outside 1-255
    if (t.seq_num == 5'd0)        inv = 1; // SEQ_NUM == 0
    if (t.frag_num == 5'd0)       inv = 1; // FRAG_NUM == 0
    return inv;
  endfunction

  // ----------------------------------------------------------
  // CRC16-CCITT (poly 0x1021, init 0xFFFF)
  // ----------------------------------------------------------
  function bit [15:0] crc16(byte unsigned bytes_q[$]);
    bit [15:0] crc;
    crc = 16'hFFFF;
    foreach (bytes_q[i]) begin
      crc ^= {bytes_q[i], 8'h00};
      for (int b = 0; b < 8; b++) begin
        if (crc[15]) crc = (crc << 1) ^ 16'h1021;
        else         crc = (crc << 1);
      end
    end
    return crc;
  endfunction

  // ----------------------------------------------------------
  // Pack a byte queue into little-endian 32-bit words (last
  // partial word zero-padded in upper, unused byte lanes - this
  // mirrors the natural way to pack a byte stream onto a 32-bit
  // bus; only full words are meaningful, but we model literally
  // "Merged Payload" packed 8 bits at a time onto a 32-bit word
  // stream the same way the DUT must, since spec doesn't show an
  // alternate framing).
  // ----------------------------------------------------------
  function void pack_words(byte unsigned bytes_q[$], ref bit [31:0] words_q[$]);
    int i;
    i = 0;
    while (i < bytes_q.size()) begin
      bit [31:0] w;
      w = 32'h0;
      for (int k = 0; k < 4; k++) begin
        if (i < bytes_q.size()) begin
          w[8*k +: 8] = bytes_q[i];
          i++;
        end
      end
      words_q.push_back(w);
    end
  endfunction

  // ----------------------------------------------------------
  // Check if fragments 1..n are ALL present
  // ----------------------------------------------------------
  function bit all_frags_present(int unsigned n);
    bit ok;
    ok = 1;
    for (int f = 1; f <= n; f++) begin
      if (!frag_seen[f]) ok = 0;
    end
    return ok;
  endfunction

  // ----------------------------------------------------------
  // Attempt reassembly: if fragments 1..active_max_frag are all
  // present, merge + regenerate CRC16 + emit. Called after every
  // accepted remote fragment.
  // ----------------------------------------------------------
  function void try_reassemble();
    byte unsigned merged[$];
    bit [15:0]    crc;
    bit [31:0]    words[$];

    if (active_max_frag == 0) return;
    if (!all_frags_present(active_max_frag)) return;

    merged.delete();
    for (int f = 1; f <= active_max_frag; f++) begin
      foreach (frag_payload[f][i]) merged.push_back(frag_payload[f][i]);
    end

    crc = crc16(merged);

    words.delete();
    pack_words(merged, words);
    foreach (words[i]) exp_remote_words_q.push_back(words[i]);
    exp_remote_words_q.push_back({16'h0000, crc});

    clear_remote_state(); // packet delivered, not a drop
  endfunction

  // ----------------------------------------------------------
  // Process ONE observed input fragment (transaction) and
  // update expected-output queues / drop_cnt accordingly.
  // This is the heart of the reference model and follows
  // sections 6, 7 and 8 of the spec literally.
  // ----------------------------------------------------------
  function void process_fragment(transaction t);

    // ---- Section 8.1: structural validity ----
    if (cfg_structurally_invalid(t)) begin
      inc_drop();
      // If this invalid remote fragment names the SEQ_NUM of an
      // in-progress packet, that in-progress packet is also lost
      // (it can never be completed correctly now). Per spec this
      // is still conceptually part of "the affected packet" being
      // discarded; we count only the ONE increment already applied
      // above for THIS fragment's packet. If an active packet with
      // the SAME seq_num is impacted, clear it without an extra
      // drop_cnt increment (the increment already accounts for the
      // dropped attempt; avoiding double counting matches "drop_cnt
      // increments once per dropped packet").
      if (t.traffic_type == 1'b1 && active && (t.seq_num == active_seq)) begin
        clear_remote_state();
      end
      return;
    end

    // ---- LOCAL traffic (cfg[0] == 0) ----
    if (t.traffic_type == 1'b0) begin
      // Section 6: FRAG_NUM must be 1 for local. SEQ_NUM has NO
      // functional impact on local routing (any legal nonzero
      // SEQ_NUM is fine - already guaranteed by the structural
      // check above which only requires seq_num != 0).
      if (t.frag_num != 5'd1) begin
        inc_drop();
        return;
      end
      // Valid local fragment: forward payload bytes + CRC bytes
      // unchanged onto the local output stream.
      foreach (t.payload[i]) begin
        ref_local_byte b;
        b = new(t.payload[i]);
        exp_local_q.push_back(b);
      end
      begin
        ref_local_byte c0, c1;
        c0 = new(t.crc_bytes[0]);
        c1 = new(t.crc_bytes[1]);
        exp_local_q.push_back(c0);
        exp_local_q.push_back(c1);
      end
      return;
    end

    // ---- REMOTE traffic (cfg[0] == 1) ----
    begin
      if (!active) begin
        // No packet currently being accumulated: this fragment
        // starts a new one under its own SEQ_NUM.
        active          = 1;
        active_seq      = t.seq_num;
        active_max_frag = 0;
        for (int f = 1; f <= 31; f++) begin
          frag_seen[f] = 0;
          frag_payload[f].delete();
        end
      end else if (t.seq_num != active_seq) begin
        // Section 8.1 bullet 5 / bullet 7: mismatched SEQ_NUM
        // while another packet is being accumulated -> drop the
        // IN-PROGRESS packet (one drop_cnt increment), then start
        // a fresh accumulation context for the new fragment.
        drop_active_packet();
        active          = 1;
        active_seq      = t.seq_num;
        active_max_frag = 0;
        for (int f = 1; f <= 31; f++) begin
          frag_seen[f] = 0;
          frag_payload[f].delete();
        end
      end
      // else: same SEQ_NUM as the packet currently being
      // accumulated -> just add this fragment below.

      // Store/replace this fragment's payload (if FRAG_NUM repeats,
      // last write wins; spec does not define duplicate-fragment
      // behavior explicitly beyond identifying by FRAG_NUM).
      frag_seen[t.frag_num] = 1;
      frag_payload[t.frag_num].delete();
      foreach (t.payload[i]) frag_payload[t.frag_num].push_back(t.payload[i]);

      if (t.frag_num > active_max_frag) active_max_frag = t.frag_num;

      // Attempt reassembly now that we may have a complete run
      try_reassemble();
    end
  endfunction

endclass

`endif // REF_MODEL_SV
