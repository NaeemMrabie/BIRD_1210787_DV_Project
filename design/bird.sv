// ============================================================
// BIRD Behavioral SystemVerilog Model (NON-synthesizable)
// ============================================================
// Spec rule:
//  - For LOCAL traffic (cfg[0]==0):
//      SEQ_NUM must be non-zero and FRAG_NUM must be 1.
//      SEQ_NUM has no functional impact on local routing.
//  - For REMOTE traffic (cfg[0]==1):
//      SEQ_NUM must be non-zero and FRAG_NUM must be non-zero.
//
// Other key points:
//  - cfg is SIDE-BAND (NOT part of stream)
//  - cfg sampled on SAME cycle as FIRST payload byte of each fragment (RX_IDLE)
//  - Each fragment: PAYLOAD_LEN bytes then 2 CRC bytes
//  - Local (when valid): forward payload bytes and forward the 2 CRC bytes unchanged on local stream
//  - Remote: one packet at a time (by SEQ_NUM), fragments by FRAG_NUM; N inferred as max FRAG_NUM seen
//           output packed 32-bit words + CRC word {16'h0000, crc16}
//  - drop_cnt: 16-bit wrap-around counter, increments ONCE per dropped packet
//
// cfg format (32-bit):
//  [0]      TRAFFIC_TYPE (0=local, 1=remote)
//  [7:1]    reserved (must be 0)
//  [15:8]   PAYLOAD_LEN (1..255)
//  [20:16]  FRAG_NUM
//  [23:21]  reserved (must be 0)
//  [28:24]  SEQ_NUM
//  [31:29]  reserved (must be 0)
//
// Notes:
//  - Behavioral: in_rdy always 1 (no input backpressure modeling).
//  - Input CRC is NOT checked.
// ============================================================

module BIRD  (
  input  logic        clk,
  input  logic        rst_n,

  // Input interface
  input  logic        in_vld,
  output logic        in_rdy,
  input  logic [7:0]  data_in,
  input  logic [31:0] cfg,

  // Status output
  output logic [15:0] drop_cnt,

  // Local output interface
  output logic        local_vld,
  input  logic        local_rdy,
  output logic [7:0]  data_local,

  // Remote output interface
  output logic        remote_vld,
  input  logic        remote_rdy,
  output logic [31:0] data_remote
);

  // ----------------------------
  // Types
  // ----------------------------
  typedef byte unsigned u8_t;

  // ============================================================
  // Drop counter helper (wrap-around by natural 16-bit overflow)
  // ============================================================
  task automatic inc_drop_cnt();
    drop_cnt <= drop_cnt + 16'd1;
  endtask

  // ----------------------------
  // cfg validity (per latest rules)
  // ----------------------------
  function automatic bit cfg_invalid(input logic [31:0] c);
    bit inv;
    inv = 0;

    // Reserved bits must be 0
    if (c[7:1]   != 7'd0) inv = 1;
    if (c[23:21] != 3'd0) inv = 1;
    if (c[31:29] != 3'd0) inv = 1;

    // PAYLOAD_LEN must be 1..255 (0 invalid)
    if (c[15:8] == 8'd0) inv = 1;

    // SEQ_NUM == 0 is a drop condition for ALL traffic, local and
    // remote alike (spec Section 8.1, first bullet - not scoped to
    // remote only).
    if (c[28:24] == 5'd0) inv = 1;

    if (c[0] == 1'b0) begin
      // LOCAL: FRAG_NUM must be 1 (spec Section 6). SEQ_NUM identifies
      // the packet but has NO functional impact on local routing - its
      // only requirement is the general non-zero check above.
      if (c[20:16] != 5'd1) inv = 1;
    end else begin
      // REMOTE: FRAG_NUM must be non-zero (SEQ_NUM==0 already covered above)
      if (c[20:16] == 5'd0) inv = 1;
    end

    return inv;
  endfunction

  // ----------------------------
  // CRC16-CCITT (poly 0x1021, init 0xFFFF) over byte queue
  // ----------------------------
  function automatic logic [15:0] crc16_ccitt_bytes(input u8_t bytes[$]);
    logic [15:0] crc;
    crc = 16'hFFFF;
    foreach (bytes[i]) begin
      crc ^= {bytes[i], 8'h00};
      for (int b = 0; b < 8; b++) begin
        if (crc[15]) crc = (crc << 1) ^ 16'h1021;
        else         crc = (crc << 1);
      end
    end
    return crc;
  endfunction

  // ----------------------------
  // Pack bytes into 32-bit words (little-endian within word)
  // ----------------------------
  function automatic void pack_bytes_to_words(input u8_t bytes[$], inout logic [31:0] wq[$]);
    int i;
    i = 0;
    while (i < bytes.size()) begin
      logic [31:0] w;
      w = 32'h0;
      for (int k = 0; k < 4; k++) begin
        if (i < bytes.size()) begin
          w[8*k +: 8] = bytes[i];
          i++;
        end
      end
      wq.push_back(w);
    end
   endfunction

  // ----------------------------
  // Input ready (behavioral model is always ready)
  // ----------------------------
  always_comb begin
    in_rdy = 1'b1;
  end

  // ----------------------------
  // Output queues (hold stable under backpressure by not popping)
  // ----------------------------
  u8_t         local_q[$];
  logic [31:0] remote_wq[$];

  // Output registers are driven from local_q / remote_wq in the main
  // sequential block below. Keeping queue push/pop in one process avoids
  // multiple procedural writers and strict always_ff single-writer errors.

  // ============================================================
  // Remote accumulation state (one packet at a time)
  // ============================================================
  bit          remote_active;
  int unsigned active_seq;                 // 1..31 (packet identifier)
  int unsigned active_max_frag;            // inferred N: max FRAG_NUM seen so far (1..31)
  bit          frag_seen   [1:31];
  u8_t         frag_payload[1:31][$];

  task automatic clear_remote_state();
    remote_active    = 0;
    active_seq       = 0;
    active_max_frag  = 0;
    for (int f = 1; f <= 31; f++) begin
      frag_seen[f] = 0;
      frag_payload[f].delete();
    end
  endtask

  task automatic drop_remote_packet_counted();
    // Drop currently-accumulated remote packet (if any) and count it as one dropped packet.
    if (remote_active) begin
      inc_drop_cnt();
    end
    clear_remote_state();
  endtask

  function automatic bit all_frags_ready(input int unsigned n);
    bit ok;
    ok = 1;
    for (int f = 1; f <= 31; f++) begin
      if (f <= n) begin
        if (!frag_seen[f]) ok = 0;
      end
    end
    return ok;
  endfunction

  task automatic build_and_queue_remote_output();
    u8_t merged[$];
    logic [15:0] crc;

    merged.delete();

    // Merge in order 1..N; if missing any => drop packet
    for (int f = 1; f <= active_max_frag; f++) begin
      if (!frag_seen[f]) begin
        drop_remote_packet_counted();
        return;
      end
      foreach (frag_payload[f][i]) merged.push_back(frag_payload[f][i]);
    end

    // Regenerate CRC over merged payload (cfg is not part of stream)
    crc = crc16_ccitt_bytes(merged);

    // Queue merged payload packed into 32-bit words, then CRC word
    pack_bytes_to_words(merged, remote_wq);
    remote_wq.push_back({16'h0000, crc});

    // Clear current remote packet state after queuing output (NOT a drop)
    clear_remote_state();
  endtask

    // ============================================================
    // RX fragment FSM
    // ============================================================
    typedef enum logic [1:0] {RX_IDLE, RX_PAYLOAD, RX_CRC} rx_state_e;
    rx_state_e rx_st;

    // Latched at start-of-fragment (first payload byte)
    bit          rx_is_remote;
    bit          rx_drop;

    int unsigned rx_seq;       // SEQ_NUM (packet id) [28:24]
    int unsigned rx_len;       // PAYLOAD_LEN [15:8]
    int unsigned rx_frag;      // FRAG_NUM [20:16]

    // Counters for the remainder of the fragment AFTER consuming the first payload byte
    int unsigned payload_left;  // remaining payload bytes after first byte
    int unsigned crc_left;      // remaining CRC bytes (2)

    // Temporary capture for current remote fragment payload
    u8_t cur_frag_payload[$];

    // ============================================================
    // Main sequential behavior
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_st <= RX_IDLE;

            local_q.delete();
            remote_wq.delete();
            cur_frag_payload.delete();

            local_vld   <= 1'b0;
            data_local  <= 8'h00;
            remote_vld  <= 1'b0;
            data_remote <= 32'h0000_0000;
            drop_cnt    <= 16'd0;

            clear_remote_state();

        end else begin
            // Registered output side.  Values are held stable while ready is low,
            // and queue entries are popped only on a valid/ready handshake.
            if (local_q.size() != 0) begin
                local_vld  <= 1'b1;
                data_local <= local_q[0];
                if (local_rdy) void'(local_q.pop_front());
            end else begin
                local_vld  <= 1'b0;
                data_local <= 8'h00;
            end

            if (remote_wq.size() != 0) begin
                remote_vld  <= 1'b1;
                data_remote <= remote_wq[0];
                if (remote_rdy) void'(remote_wq.pop_front());
            end else begin
                remote_vld  <= 1'b0;
                data_remote <= 32'h0000_0000;
            end

        if (in_vld && in_rdy) begin
            unique case (rx_st)

                // ----------------------------------------------------
                // RX_IDLE: first payload byte of a fragment arrives here
                // cfg sampled in SAME cycle as first payload byte.
                // ----------------------------------------------------
                RX_IDLE: begin
                    rx_drop      = cfg_invalid(cfg);
                    rx_is_remote = cfg[0];
                    rx_len       = cfg[15:8];
                    rx_frag      = cfg[20:16];
                    rx_seq       = cfg[28:24];

                    cur_frag_payload.delete();

                    // Consuming FIRST payload byte now; remaining payload bytes = PAYLOAD_LEN - 1
                    payload_left = (cfg[15:8] > 0) ? (cfg[15:8] - 1) : 0;
                    crc_left     = 2;

                    // If cfg invalid: count one dropped packet; consume bytes but do not forward/store
                    if (rx_drop) begin
                        inc_drop_cnt();

                        // If this is a remote fragment for the active packet, drop that active packet too
                        if (cfg[0] == 1'b1 && remote_active && (cfg[28:24] == active_seq)) begin
                            clear_remote_state();
                        end  
                    end else begin
                        // Valid cfg: handle local vs remote
                        if (!rx_is_remote) begin
                            // LOCAL valid: forward first payload byte
                            local_q.push_back(data_in);
                        end else begin
                            // REMOTE valid
                            if (!remote_active) begin
                                // Start a new remote packet using the incoming SEQ_NUM.
                                // Fragments may arrive out of order, so the first received
                                // fragment does not have to be FRAG_NUM==1.
                                remote_active   = 1;
                                active_seq      = rx_seq;
                                active_max_frag = 0;
                                for (int f = 1; f <= 31; f++) begin
                                    frag_seen[f] = 0;
                                    frag_payload[f].delete();
                                end
                                cur_frag_payload.push_back(data_in);
                            end else begin
                                // Active packet exists
                                if (rx_seq != active_seq) begin
                                    // Mismatched SEQ while accumulating => drop current packet,
                                    // then start accumulating the incoming packet.
                                    drop_remote_packet_counted();
                                    remote_active   = 1;
                                    active_seq      = rx_seq;
                                    active_max_frag = 0;
                                    for (int f = 1; f <= 31; f++) begin
                                        frag_seen[f] = 0;
                                        frag_payload[f].delete();
                                    end
                                    cur_frag_payload.push_back(data_in);
                                end else begin
                                    // Same SEQ as active: accept payload
                                    cur_frag_payload.push_back(data_in);
                                end
                            end
                        end
                    end

                    // Next state
                    if (((cfg[15:8] > 0) ? (cfg[15:8] - 1) : 0) == 0) begin
                        rx_st <= RX_CRC;
                    end else begin
                        rx_st <= RX_PAYLOAD;
                    end
                
                end

                // ----------------------------------------------------
                // RX_PAYLOAD: remaining payload bytes
                // ----------------------------------------------------
                RX_PAYLOAD: begin
                    rx_drop      = cfg_invalid(cfg);
                    if (!rx_drop) begin
                        if (!rx_is_remote) begin
                            // Local: forward payload bytes
                            local_q.push_back(data_in);
                        end else begin
                            // Remote: only keep collecting if active context matches rx_seq
                            if (remote_active && (rx_seq == active_seq)) begin
                                cur_frag_payload.push_back(data_in);
                            end
                        end
                    end

                    if (payload_left > 0) payload_left <= payload_left - 1;

                    // After consuming the last remaining payload byte, move to CRC
                    if (payload_left == 1) begin
                        rx_st <= RX_CRC;
                    end
                    
                end

                // ----------------------------------------------------
                // RX_CRC: consume exactly 2 CRC bytes (not checked)
                // Local: forward CRC bytes unchanged on the local stream.
                // ----------------------------------------------------
                RX_CRC: begin
                    if (crc_left > 0) crc_left <= crc_left - 1;

                    // Forward CRC bytes to local output only (if not dropped)
                    if (!rx_drop && !rx_is_remote) begin
                        local_q.push_back(data_in);
                    end

                    // End-of-fragment on the second CRC byte
                    if (crc_left == 1) begin
                        if (!rx_drop && rx_is_remote) begin
                            // Commit remote fragment payload if active and SEQ matches
                            if (!(remote_active && (rx_seq == active_seq))) begin
                                // Remote fragment without valid active context => drop packet
                                inc_drop_cnt();
                            end else begin
                                // rx_frag is guaranteed non-zero by cfg_invalid() for remote
                                //if (rx_frag < 1 || rx_frag > 31) begin
                                if (rx_frag < 1 || rx_frag > 31) begin
                                    drop_remote_packet_counted();
                                end else begin
                                    //frag_seen[rx_frag] = 1;
                                    //frag_payload[rx_frag].delete();
                                    frag_seen[rx_frag] = 1;
                                    frag_payload[rx_frag].delete();
                                    //foreach (cur_frag_payload[i]) frag_payload[rx_frag].push_back(cur_frag_payload[i]);
                                    
                                    foreach (cur_frag_payload[i]) begin
                                        frag_payload[rx_frag].push_back(cur_frag_payload[i]);
                                    end

                                    // Infer N as max FRAG_NUM seen so far
                                    if (rx_frag > active_max_frag) active_max_frag = rx_frag;

                                    // If we now have all fragments 1..N, build output
                                    if (all_frags_ready(active_max_frag)) begin
                                        build_and_queue_remote_output();
                                    end
                                end
                            end
                        end

                        // Ready for next fragment
                        rx_st <= RX_IDLE;
                    end
                end

                default: rx_st <= RX_IDLE;

            endcase
        end
        end
    end

endmodule
