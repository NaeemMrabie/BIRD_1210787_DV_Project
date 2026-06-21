# wait_drain timing-race fix

## Problem

`sim_TEST_ID_0.log` showed a consistent off-by-one / off-by-N pattern across
nearly every test once more than one test ran back to back in the same
session:

```
[SB][LOCAL]  MISMATCH: observed=0x8c expected=0x9a (match#1 mismatch#1)
[SB][LOCAL]  MISMATCH: observed=0xb4 expected=0x9a (match#1 mismatch#2)
[SB][REMOTE] MISMATCH: observed=0xa7240f24 expected=0x3a1299bf (match#1 mismatch#1)
[SB][DROP_CNT][FINAL] MISMATCH: observed=1 expected=0 (match#0 mismatch#1)
[SB][DROP_CNT][FINAL] MISMATCH: observed=20 expected=19 (match#0 mismatch#1)
```

In every case `observed` at mismatch *N* equals `expected` at mismatch *N+1*
(or the final drop_cnt comparison is short by exactly the last fragment/drop):
the comparison logic and reference model were both correct, but the **report
was generated before the last in-flight fragment had finished being driven,
observed, and processed**.

## Root cause

`environment::wait_drain()` was:

```systemverilog
task wait_drain(int unsigned extra_cycles = 50);
  wait (gen2drv_mbx.num() == 0);
  repeat (extra_cycles) @(posedge vif.clk);
endtask
```

`gen2drv_mbx.num() == 0` becomes true the instant `driver::run()` calls
`gen2drv_mbx.get(t)` for the **last** queued transaction - i.e. the moment the
driver *starts* `drive_one()`, not when it *finishes* driving that fragment
onto the bus. Every `extra_cycles` value used by the various tests (50, 100,
200, 300, 400, 500, 600) was therefore a **guess** at "how many cycles the
last fragment + monitor + reference-model processing will take," and for
several tests (a single small local fragment, a 20-fragment drop burst, large
random batches) the guess was too small, so `report()` ran while the very
last fragment was still mid-flight on the bus or mid-processing in the
monitor/reference model.

## Fix

`verif/env/environment.sv`'s `wait_drain()` now waits on the actual pipeline
state instead of a fixed cycle count:

1. `gen2drv_mbx.num() == 0` - driver has picked up the last transaction.
2. `vif.in_vld` deasserted for a full cycle - the driver is no longer
   mid-fragment on the bus (this is the condition the old code was missing).
3. `mon2sb_input_mbx.num() == 0` - the monitor has finished reconstructing
   and forwarding every fragment it observed on the input side.
4. `mon2sb_local_mbx.num() == 0 && sb.rm.exp_local_q.size() == 0` **and**
   `mon2sb_remote_mbx.num() == 0 && sb.rm.exp_remote_words_q.size() == 0` -
   neither side of either comparison has anything left in flight.
5. `extra_cycles` (parameter kept, default lowered from 50 to 20 since it is
   now just a small settle margin, not the primary wait mechanism) for any
   test-specific follow-up checks that read `vif.drop_cnt` etc. directly.

This is correct for any payload length, any number of queued fragments, and
any backpressure setting (`local_rdy_low_pct` / `remote_rdy_low_pct`), since
none of the existing sequences ever leave a *complete* expected fragment
permanently unobserved - they either complete (and the matching `exp_*_q`
drains to empty) or are dropped (and never enter `exp_*_q` in the first
place). The various `post_test(N)` call sites' explicit cycle counts (100,
200, 300, ...) are now purely a small post-drain margin and no longer the
thing standing between PASS and FAIL.

## File changed

- `verif/env/environment.sv` - `wait_drain()` task body only. No other file
  was touched.
