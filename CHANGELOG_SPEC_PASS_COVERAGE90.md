# CHANGELOG - Spec Pass and Coverage >90 Patch

This patch was prepared against the latest uploaded/GitHub project snapshot. It follows the course flow:

> find bug -> edit RTL -> continue verification

## Why this patch was needed

The previous regression still showed local/remote scoreboard mismatches, stale output comparisons between tests, and drop-counter mismatches. The functional coverage was high, but the full regression did not pass because the testbench was sampling output data after the DUT had already advanced to the next registered value.

## Main fixes

### 1. Output handshake duplicate/shift fix in RTL

File: `design/bird.sv`

The output queue pop order was corrected. The old code loaded `data_local`/`data_remote` from the queue before popping the accepted item, which could duplicate the same byte/word on the next cycle. The new code pops the accepted item first, then loads the next item.

### 2. Monitor sampling fix

File: `verif/if/bird_if.sv`

The monitor clocking block now samples with `#1step`, so it observes the value that was actually present at the active clock edge. This matches the valid/ready transfer rule from the specification.

### 3. Driver completion tracking

File: `verif/env/driver.sv`

Added a `busy` flag and made reset clear all traffic/backpressure knobs. The environment can now know when the driver really finished the last fragment, not only when the mailbox became empty.

### 4. Robust drain between tests

File: `verif/env/environment.sv`

`wait_drain()` now waits for:

- generator-to-driver mailbox empty
- `drv.num_sent == gen.txn_sent`
- `drv.busy == 0`
- input bus idle
- monitor input mailbox empty
- local/remote observed mailboxes empty
- local/remote expected queues empty
- extra settle cycles

This prevents data from one test being compared during the next test.

### 5. Scoreboard stale-observation protection

File: `verif/env/scoreboard.sv`

Added `reset_epoch` protection. If a checker consumed an observed output and a reset starts before the reference model produces the expected value, that old observation is discarded instead of being compared against the next test.

### 6. Remote fragment completion order

File: `verif/seq/sequences.sv`

Remote packet sequences now send higher-numbered fragments before `FRAG_NUM==1` when building multi-fragment packets. Since the spec has no explicit total-fragment field, the TB uses `FRAG_NUM==1` as the completion point after the higher fragments have been received.

Updated tests include:

- remote in-order
- remote out-of-order
- remote sequence mismatch drop
- backpressure remote packet
- multi-packet back-to-back
- random remote packets
- random backpressure matrix
- duplicate fragment overwrite
- max fragment coverage

### 7. Drop counter wrap coverage

Files:

- `verif/seq/generator.sv`
- `verif/seq/sequences.sv`
- `scripts/run_regression.sh`
- `verif/tb/tb_top.sv`

Invalid packets used in drop tests now have payload length 1 to keep the long wrap test fast. `run_regression.sh` passes `+FULL_DROP_WRAP=1`, so `test_dropcnt_many_wrap` performs 65537 drops and hits:

- normal increment
- high counter range
- pre-wrap
- wrap value
- wrap back to zero/one

The global timeout was increased to 20 ms to allow this directed wrap test.

## Files modified by this patch

- `design/bird.sv`
- `verif/if/bird_if.sv`
- `verif/env/driver.sv`
- `verif/env/environment.sv`
- `verif/env/scoreboard.sv`
- `verif/seq/generator.sv`
- `verif/seq/sequences.sv`
- `verif/tb/tb_top.sv`
- `scripts/run_regression.sh`
- `CHANGELOG_SPEC_PASS_COVERAGE90.md`

## Required run command

From the project root:

```bash
rm -rf simv simv.daidir csrc ucli.key DVEfiles *.vpd *.vcd *.vdb novas.* *.log
./scripts/run_regression.sh | tee regression_spec_pass_cov90.log
```

## Expected result

The expected result is that each test reports `RESULT: PASS`, the full regression completes, and URG regenerates:

```text
coverage/code_coverage/urg_regression_report/dashboard.html
coverage/functional_coverage/functional_coverage_TEST_ID_0.log
```

If the server still reports an error, send the last 150 lines:

```bash
tail -150 regression_spec_pass_cov90.log
```
