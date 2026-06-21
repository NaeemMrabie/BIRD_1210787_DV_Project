# Fixes applied

This version was cleaned for common VCS/SystemVerilog compile and simulation issues.

## Main changes

1. Replaced modport-specific virtual interface handles in `driver.sv` and `monitor.sv` with `virtual bird_if` to avoid formal/actual virtual-interface type mismatch errors.
2. Removed the unused `event drv_done_ev = null` argument from `generator.sv`; the event was unused and can cause compatibility issues in some simulators.
3. Started `drive_backpressure()` once from `agent.run()` so single-test backpressure cases work correctly.
4. Removed the duplicate forever backpressure process from `seq_backpressure_stability` to avoid multiple writers fighting over `local_rdy` / `remote_rdy`.
5. Updated `drive_backpressure()` to actively drive ready high when backpressure is disabled.
6. Reset driver timing knobs after each test to prevent one test's backpressure settings from leaking into following tests.
7. Reworked `design/bird.sv` so output queue pop/push is handled in one sequential process instead of multiple always blocks. This avoids strict `always_ff` single-writer/race problems.
8. Removed noisy RTL debug `$display` messages from `design/bird.sv` while keeping normal testbench/report messages.
9. Added bounded waits in `environment.wait_drain()` so a real mismatch reports an error instead of hanging indefinitely.
10. Made `scripts/run_vcs.sh` and `scripts/run_regression.sh` executable.

## Note

I could not run VCS in this sandbox because no SystemVerilog simulator is installed here. Run the fixed project on your EDA/VCS machine with:

```bash
./scripts/run_vcs.sh
```

or a single test:

```bash
./scripts/run_vcs.sh 6
```
