# Safe Regression Fixes

This patch fixes the regression failures observed in `run_regression.sh` without using the broken timeout patch.

## Main fixes

1. **Race-safe scoreboard**
   - Replaced blocking local/remote checker behavior with observed queues.
   - Prevents stale observed items from one test being compared in the next test after reset.
   - Adds pending observed counts in the final report.

2. **Regression drain fix**
   - `environment.wait_drain()` now waits for:
     - generator mailbox empty
     - driver not busy
     - driver transaction count equal to generator transaction count
     - monitor mailboxes empty
     - scoreboard expected/observed queues empty

3. **Driver busy tracking**
   - Added `busy` flag to the driver.
   - Reset clears backpressure knobs and returns ready signals to idle.

4. **Output handshake fix in RTL**
   - `design/bird.sv` now pops output queues only on valid/ready handshake.
   - Output data is driven from queue heads to avoid duplicated/shifted remote words.
   - Output pop and input push are ordered in the same sequential block to reduce queue races.

5. **Remote fragment ordering**
   - Complete remote packets are generated high-to-low, so `FRAG_NUM==1` arrives last.
   - This matches the existing reference-model/DUT completion rule where the max fragment number defines the required set `1..N`.

6. **Remote sequence mismatch test**
   - Starts with an incomplete remote fragment (`FRAG_NUM=2`) before sending a different `SEQ_NUM`, so the test actually exercises the drop of an in-progress packet.

7. **Backpressure process cleanup**
   - Backpressure driver is launched once by the agent.
   - Sequences only change the percentage knobs; they no longer fork extra permanent backpressure threads.

## Files changed

- `design/bird.sv`
- `verif/env/scoreboard.sv`
- `verif/env/environment.sv`
- `verif/env/driver.sv`
- `verif/env/agent.sv`
- `verif/if/bird_if.sv`
- `verif/seq/generator.sv`
- `verif/seq/sequences.sv`
