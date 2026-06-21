// ============================================================
// transaction.sv
// ------------------------------------------------------------
// Transaction object: represents ONE fragment to be driven on
// the input interface of BIRD (cfg + payload bytes).
// Used by: generator -> driver (via mailbox)
//          monitor   -> scoreboard (captured fragments / outputs)
//
// NOTE: This class only carries fields. All packing/unpacking
// (payload bytes, CRC bytes, cfg fields) is interpreted by the
// driver/monitor/reference model according to the BIRD spec.
// ============================================================

`ifndef TRANSACTION_SV
`define TRANSACTION_SV

class transaction;

  // ----------------------------------------------------------
  // cfg sub-fields (spec section 5 - Configuration Word Format)
  // ----------------------------------------------------------
  rand bit         traffic_type;   // cfg[0]    : 0 = local, 1 = remote
  rand bit [6:0]   reserved_7_1;   // cfg[7:1]  : must be 0 (kept randomizable for negative tests)
  rand bit [7:0]   payload_len;    // cfg[15:8] : payload length in bytes (1-255 nominal)
  rand bit [4:0]   frag_num;       // cfg[20:16]: fragment number (1-31 nominal)
  rand bit [2:0]   reserved_23_21; // cfg[23:21]: must be 0
  rand bit [4:0]   seq_num;        // cfg[28:24]: sequence number (1-31 nominal, 0 invalid)
  rand bit [2:0]   reserved_31_29; // cfg[31:29]: must be 0

  // ----------------------------------------------------------
  // Payload bytes (queue, sized dynamically by payload_len)
  // CRC bytes are generated/forwarded separately
  // ----------------------------------------------------------
  rand byte unsigned payload[];    // payload_len bytes
  byte unsigned       crc_bytes[2]; // 2 CRC bytes appended after payload on the wire

  // Control knobs for directed/error injection tests
  bit force_bad_crc;     // if 1, crc_bytes will be corrupted by the generator/driver intentionally
  bit use_random_crc;    // if 1, crc_bytes are random garbage (spec says input CRC is not checked)

  // Bookkeeping / debug
  static int unsigned id_counter = 0;
  int unsigned         id;

  function new();
    id = id_counter++;
    force_bad_crc  = 0;
    use_random_crc = 1; // by default put random garbage in input CRC (DUT must not check it)
  endfunction

  // ----------------------------------------------------------
  // Constraints
  // ----------------------------------------------------------

  // Default: payload_len in legal range, payload array sized to match
  constraint c_payload_len_legal {
    payload_len inside {[1:255]};
  }

  constraint c_payload_size_matches_len {
    payload.size() == payload_len;
  }

  // Default: reserved bits are 0 (legal transaction). Override for negative tests.
  constraint c_reserved_zero {
    reserved_7_1   == 7'd0;
    reserved_23_21 == 3'd0;
    reserved_31_29 == 3'd0;
  }

  // Default: frag_num / seq_num in legal nominal range (1-31). Override for negative tests.
  constraint c_frag_seq_legal {
    frag_num inside {[1:31]};
    seq_num  inside {[1:31]};
  }

  // ----------------------------------------------------------
  // Build cfg word from sub-fields
  // ----------------------------------------------------------
  function bit [31:0] get_cfg();
    bit [31:0] c;
    c = 32'h0;
    c[0]       = traffic_type;
    c[7:1]     = reserved_7_1;
    c[15:8]    = payload_len;
    c[20:16]   = frag_num;
    c[23:21]   = reserved_23_21;
    c[28:24]   = seq_num;
    c[31:29]   = reserved_31_29;
    return c;
  endfunction

  // ----------------------------------------------------------
  // Load sub-fields from a cfg word (used by monitor when it
  // samples cfg directly from the interface)
  // ----------------------------------------------------------
  function void set_from_cfg(bit [31:0] c);
    traffic_type   = c[0];
    reserved_7_1   = c[7:1];
    payload_len    = c[15:8];
    frag_num       = c[20:16];
    reserved_23_21 = c[23:21];
    seq_num        = c[28:24];
    reserved_31_29 = c[31:29];
  endfunction

  // ----------------------------------------------------------
  // Deep copy
  // ----------------------------------------------------------
  function transaction copy();
    transaction t = new();
    t.traffic_type   = this.traffic_type;
    t.reserved_7_1   = this.reserved_7_1;
    t.payload_len    = this.payload_len;
    t.frag_num       = this.frag_num;
    t.reserved_23_21 = this.reserved_23_21;
    t.seq_num        = this.seq_num;
    t.reserved_31_29 = this.reserved_31_29;
    t.payload         = this.payload;
    t.crc_bytes[0]     = this.crc_bytes[0];
    t.crc_bytes[1]     = this.crc_bytes[1];
    t.force_bad_crc    = this.force_bad_crc;
    t.use_random_crc   = this.use_random_crc;
    return t;
  endfunction

  // ----------------------------------------------------------
  // Pretty print
  // ----------------------------------------------------------
  function string sprint();
    string s;
    s = $sformatf("TXN#%0d type=%s payload_len=%0d frag_num=%0d seq_num=%0d resv(%0d,%0d,%0d) payload_size=%0d",
                   id, traffic_type ? "REMOTE" : "LOCAL",
                   payload_len, frag_num, seq_num,
                   reserved_7_1, reserved_23_21, reserved_31_29,
                   payload.size());
    return s;
  endfunction

endclass

`endif // TRANSACTION_SV
