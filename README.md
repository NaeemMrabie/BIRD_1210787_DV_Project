# BIRD_1210787 — Plain SystemVerilog Verification Project

Student ID: **1210787**

This project is a **classic SystemVerilog** verification environment for BIRD (Birzeit Integrated Router Design). It is intentionally **not UVM**. The reference model, scoreboard, tests, and coverage are written from the **functional specification**, not from the RTL implementation.

## Repository structure

```text
design/          Put the provided DUT RTL here as bird.sv
verif/if/        BIRD interface and clocking blocks
verif/env/       transaction, driver, monitor, agent, ref model, scoreboard, coverage, env
verif/cfg/       spec constants package
verif/seq/       generator.sv + sequences.sv (one sequence class per spec function)
verif/tests/     test_directed.sv, test_random.sv, regression.sv
verif/tb/        top-level testbench
coverage/        code and functional coverage report locations
scripts/         VCS compile/regression scripts
testplan/        BIRD test plan Excel file
vcs.f            VCS file list
```

This follows the same high-level structure as the class example repository: `design/`, `verif/if/`, `verif/env/`, `verif/cfg/`, `verif/seq/`, `verif/tests/`, `verif/tb/`, and `vcs.f`.

## Important setup step

I could open the EDA Playground page, but the actual `design.sv` source is loaded dynamically in the browser and was not extractable from the page text here. Copy the DUT from the provided playground into:

```text
design/bird.sv
```

Then open `vcs.f` and uncomment:

```text
design/bird.sv
```

The verification code itself is already organized and ready.

## Build and run

From the project root:

```bash
./scripts/run_vcs.sh
```

Run a single test:

```bash
./scripts/run_vcs.sh 6
```

Run full regression and generate coverage:

```bash
./scripts/run_regression.sh
```

## Test ID mapping

| TEST_ID | Test name | Main focus |
|---:|---|---|
| 0 | full regression | Directed suite first, then random suite |
| 1 | directed suite only | All directed tests |
| 2 | random suite only | All constrained-random tests |
| 3 | test_reset_behavior | Active-low reset clears outputs, buffers, drop counter |
| 4 | test_basic_local_legal | Legal local packet forwarding |
| 5 | test_local_bad_frag_num | Local packet with FRAG_NUM != 1 drops |
| 6 | test_local_seq_no_functional_impact | Local SEQ_NUM does not affect routing |
| 7 | test_basic_remote_inorder | Remote reassembly path |
| 8 | test_remote_outoforder | Out-of-order fragment reordering |
| 9 | test_remote_seq_mismatch_drop | Mismatched SEQ_NUM while accumulating |
| 10 | test_drop_seq_zero | SEQ_NUM == 0 silent drop |
| 11 | test_drop_frag_zero | FRAG_NUM == 0 silent drop |
| 12 | test_drop_payload_len_zero | PAYLOAD_LEN == 0 silent drop |
| 13 | test_drop_reserved_bits | Reserved cfg bits non-zero silent drop |
| 14 | test_dropcnt_many_wrap | drop_cnt many/wrap representative test |
| 15 | test_backpressure_stability | valid/ready backpressure stability |
| 16 | test_multi_packet_back_to_back | Mixed local, remote, and drops |
| 17 | test_boundary_max_values | max payload_len, max seq, max frag coverage |
| 18 | test_random_local_legal | constrained-random legal local traffic |
| 19 | test_random_remote_packets | constrained-random complete remote packets |
| 20 | test_random_invalid_cfg | constrained-random illegal cfg cases |
| 21 | test_random_backpressure_matrix | all local/remote backpressure combinations |
| 22 | test_random_mixed_traffic | broad mixed random regression |

## Main components

- `bird_if.sv`: interface with driver and monitor clocking blocks.
- `transaction.sv`: cfg fields, payload, CRC bytes, copy/print helpers.
- `generator.sv`: legal and illegal packet/fragment generation.
- `driver.sv`: valid/ready input driver; holds data/cfg stable when `in_rdy=0`.
- `monitor.sv`: observes input fragments, local bytes, remote words, and drop counter.
- `ref_model.sv`: independent spec-based golden model.
- `scoreboard.sv`: compares observed DUT outputs against expected outputs.
- `coverage.sv`: expanded functional covergroups for cfg, max values, illegal fields, drop_cnt many/wrap bins, and all backpressure combinations.
- `sequences.sv`: one sequence class per directed/random spec function.
- `test_directed.sv`: one directed test class per spec function.
- `test_random.sv`: constrained-random tests.
- `regression.sv`: runs directed tests first, then random tests, and prints coverage at the end.

## Spec interpretation notes

1. **Local traffic**: `cfg[0]=0`, single fragment only, `FRAG_NUM` must be 1. `SEQ_NUM` is legal as long as it is non-zero and has no local routing effect.
2. **Input CRC**: The drop policy does not list input CRC mismatch as a drop condition, so the reference model does not drop on bad input CRC. Local traffic forwards the input CRC bytes unchanged.
3. **Remote CRC**: Remote traffic emits merged payload plus a regenerated CRC16. The spec does not name a CRC polynomial; the model uses CRC16-CCITT (`poly=0x1021`, `init=0xFFFF`) in one function so it can be changed easily if the instructor states a different variant.
4. **Remote fragment completion**: The spec has no explicit total-fragment-count or last-fragment bit. The reference model documents the chosen assumption in `ref_model.sv`. If the instructor gives a stricter rule, update only `try_reassemble()` and the related tests.

## Coverage deliverables

- Code coverage is generated by VCS/URG into `coverage/code_coverage/`.
- Functional coverage is printed by the covergroups in `coverage.sv`; save the simulator log in `coverage/functional_coverage/`.

## Academic honesty note

This environment is organized to help discussion: every file has a clear purpose. During discussion, explain the spec rules first, then the related driver/monitor/reference-model/checker behavior.
