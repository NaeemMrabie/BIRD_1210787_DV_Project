# Design Review + Verification Hardening (this round)

This document lists **every file changed or added** in this round, with exact
locations for the RTL change as requested. It follows the same
"find bug → document → fix" convention as the project's other CHANGELOG_*.md
files.

---

## 1) `design/bird.sv` — RTL change (the only RTL edit this round)

### Location
Lines 159–164, inside the output-drive `always_ff @(posedge clk or negedge rst_n)`
block.

### Before
```systemverilog
end else begin
  local_vld  = (local_q.size() != 0);
  data_local = (local_q.size() != 0) ? local_q[0] : 8'h00;
  if (local_vld && local_rdy) begin
    void'(local_q.pop_front());
  end

  remote_vld  <= (remote_wq.size() != 0);
  data_remote <= (remote_wq.size() != 0) ? remote_wq[0] : 32'h0;
  if (remote_vld && remote_rdy) begin
    void'(remote_wq.pop_front());
  end
end
```

### After
```systemverilog
end else begin
  local_vld  <= (local_q.size() != 0);
  data_local <= (local_q.size() != 0) ? local_q[0] : 8'h00;
  if (local_vld && local_rdy) begin
    void'(local_q.pop_front());
  end

  remote_vld  <= (remote_wq.size() != 0);
  data_remote <= (remote_wq.size() != 0) ? remote_wq[0] : 32'h0;
  if (remote_vld && remote_rdy) begin
    void'(remote_wq.pop_front());
  end
end
```

### Why
`local_vld`/`data_local` used **blocking** assignment (`=`) while
`remote_vld`/`data_remote` used **non-blocking** assignment (`<=`) for the
exact same kind of registered output. With blocking assignment, the `if
(local_vld && local_rdy)` pop decision on the very same line reads the
**just-computed, same-cycle** value of `local_vld` (derived from
`local_q.size()` evaluated *this* clock edge) — effectively giving the local
path near-zero, "wire-like" latency inside a clocked block. The remote path,
using non-blocking assignment, correctly bases its pop decision on the
**previous cycle's** registered `remote_vld` value, which is the standard,
deterministic valid/ready-FIFO pattern.

This asymmetry meant local and remote outputs did not have consistent,
comparable timing characteristics, and made the local path's behavior depend
on exactly how each simulator schedules processes that touch the same shared
queue (`local_q`) within a single clock edge — a portability/determinism risk
even where current results happen to be correct on the project's target
simulator (VCS).

The fix makes both output channels behave identically: proper one-cycle
registered outputs, with the pop decision always based on the previous
cycle's `*_vld`, matching the remote path's (already-correct) pattern.

### What this does NOT change
Nothing else in `design/bird.sv` was touched. In particular, the
already-fixed rules from earlier rounds remain exactly as they were:
- `cfg_invalid()` (local SEQ_NUM has no functional impact; FRAG_NUM must be 1).
- The `payload_left == 1` payload→CRC transition condition.
- Remote fragment storage/indexing keyed by `rx_frag` (FRAG_NUM), with
  `rx_seq` (SEQ_NUM) only used to confirm fragments belong to the same packet.
- Out-of-order reassembly (a new packet may start on ANY FRAG_NUM, not just 1).

---

## 2) `design/bird_assertions.sv` — **new file**, SVA bound to BIRD

Kept separate from `design/bird.sv` (clean RTL, no embedded assertions) and
connected via a single `bind BIRD bird_assertions bird_sva_inst (.*);`
statement at the bottom of the file. Compiled automatically by `vcs.f`
whenever the DUT is compiled — no testbench wiring required.

| ID | Property | Spec rule encoded |
|----|----------|--------------------|
| A1a/b | `local_vld`/`remote_vld` deasserted while `!rst_n` | Section 9: "All valid outputs are deasserted" |
| A1c | `drop_cnt == 0` while `!rst_n` | Section 9: "drop_cnt is cleared to zero" |
| A2a/b | `*_vld`/`data_*` held stable for one cycle after a stall (`vld=1, rdy=0`) | Section 3 / 3.2 Stability Rule, applied to the producer side of the local/remote interfaces |
| A3 | `in_rdy` always `1` | File header comment: "Behavioral: in_rdy always 1" — guards the documented assumption several driver timing calculations rely on |
| A4 | `drop_cnt` only ever changes by exactly `+1` (mod 65536) | Section 8.2: "increments by one... wraps around on overflow" |
| A5a/b | `data_local`/`data_remote` never X/Z while the matching `*_vld` is asserted | Basic X-propagation sanity |
| A6 | `data_in`/`cfg` never X/Z while `in_vld` is asserted | Section 2.2/2.3: cfg sampled with first payload byte, must be valid for the transfer |

These run automatically in any simulation and will `$error` immediately if a
future code change violates one of these documented contracts.

---

## 3) `vcs.f` — added `design/bird_assertions.sv` to the compile file list
(immediately after `design/bird.sv`, since the `bind` statement must be
compiled alongside the DUT).

---

## 4) `verif/env/transaction.sv` — randomization / constraints

Added two new **soft** `dist` constraints (soft so any directed
`randomize() with {...}` override, or an explicit field assignment after
`randomize()`, still wins outright — no conflict with existing directed
sequences):

- `c_payload_len_dist`: biases `payload_len` toward the boundary values
  (1, 255) and small/medium lengths, instead of pure uniform 1..255. Improves
  both realism (most real traffic isn't max-size) and coverage-closure speed
  for `payload_len_cp` (`coverage.sv`).
- `c_frag_seq_dist`: biases `frag_num`/`seq_num` toward the boundary values
  (1, 31), since boundary/off-by-one values are exactly the class of value
  most likely to expose indexing bugs (the same class as the
  FRAG_NUM-vs-SEQ_NUM indexing bug fixed in an earlier round).

Both use `:/ ` (not `:=`) for the multi-value ranges, so the named bucket's
weight is divided across the range rather than applied to every individual
value in it (using `:=` on a 56-value range, for example, would have made
that bucket dominate the distribution by accident).

---

## 5) `verif/env/ref_model.sv` — completion-event hook (new, additive only)

Added two fields (`completed_event`, `completed_frag_count`) and set them in
`try_reassemble()` right before it clears state on a successful reassembly.
Initialized in `reset()`. This lets the scoreboard sample **how many
fragments a just-completed packet actually had** — a coverage dimension that
was previously invisible (the existing `frag_num_cp` only sees individual
fragment field values, not completed-packet sizes). No existing behavior was
changed; this is a pure additive observability hook.

---

## 6) `verif/env/scoreboard.sv` — wire the new hook

`feed_ref_model()` now polls-and-clears `rm.completed_event` after every
`process_fragment()` call and forwards `rm.completed_frag_count` to
`cov.sample_remote_packet_size()`.

---

## 7) `verif/env/coverage.sv` — new coverpoint

Added `remote_pkt_size_cp` to `protocol_cg` (bins: 1, 2-5, 6-15, 16-30, 31
fragments) plus `sample_remote_packet_size()`. The `pkt_max_frags` (31) bin is
specifically closed by the new `seq_remote_full_max_fragments` sequence
below — no existing sequence ever completes a 31-fragment packet.

---

## 8) `verif/seq/sequences.sv` — 3 new sequences

| Sequence | What it exercises |
|---|---|
| `seq_remote_full_max_fragments` | A complete 31-fragment remote packet, sent in a Fisher-Yates-shuffled (non-sequential) order, that successfully reassembles. Closes the `pkt_max_frags` coverage bin and exercises the full `frag_payload[1:31]` storage / `all_frags_ready()` range / largest CRC+packing pass in one directed test. |
| `seq_remote_duplicate_fragment_overwrite` | Sends FRAG_NUM==2 once, then resends FRAG_NUM==2 with *different* payload before the packet completes, then completes it. Makes the design's (and reference model's) "last write wins" duplicate-fragment behavior an explicit, regression-protected test rather than an implicit side effect. |
| `seq_boundary_min_values` | Local `payload_len==1` and a single-fragment remote packet at `FRAG_NUM==1`/`SEQ_NUM==1`/`payload_len==1`, both completing successfully. Pairs with the existing `seq_boundary_max_values` (which intentionally stays incomplete at the maximum end) by covering the *minimum* end with a fully-completed path. |

---

## 9) `verif/tests/test_directed.sv` — 3 new test classes

`test_remote_full_max_fragments`, `test_remote_duplicate_fragment_overwrite`,
`test_boundary_min_values` — thin wrappers calling the matching sequence,
following the existing `bird_directed_test_base` pattern exactly.

---

## 10) `verif/tests/regression.sv` — wire the 3 new tests

- `print_test_id_map()`: added IDs 23, 24, 25.
- `run_directed()`: added the 3 new tests to the directed suite (and
  therefore to `TEST_ID=0`/`TEST_ID=1`).
- `run_by_id()`: added declarations + `case` branches for IDs 23/24/25 so
  each can also be run individually
  (`./scripts/run_vcs.sh 23`, `24`, `25`).

---

## Verification of this round's changes

Every file above was checked with `slang` (a standards-compliant
SystemVerilog front-end) against the full project file list from `vcs.f`,
including `design/bird.sv` + `design/bird_assertions.sv` + the complete
`verif/` tree, with `--top tb_top`: **0 errors, 0 warnings**.

No simulator (VCS/Xcelium/Questa) was available in this environment to run
the regression and capture an actual coverage percentage or assertion-firing
report — please rerun `./scripts/run_regression.sh` (or
`./scripts/run_vcs.sh 0`) on the project server to confirm PASS and capture
the updated coverage numbers.
