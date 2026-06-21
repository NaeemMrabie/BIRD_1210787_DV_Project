# TB race fixes

Applied fixes:

- `verif/tb/tb_top.sv`: DUT instance changed from `bird dut` to `BIRD dut`.
- `vcs.f`: enabled `design/bird.sv` in the compile file list.
- `verif/if/bird_if.sv`: monitor clocking block now samples with `default input #1ps`.
- `verif/env/environment.sv`: persistent threads are started only once; reset now calls `sb.reset()`.
- `verif/env/scoreboard.sv`: added `reset()`, guarded `run()`, and final drop counter comparison to avoid early drop_cnt races.
- `verif/tests/test.sv`: reset test now drives an incomplete remote packet before reset.
- `design/bird.sv`: reviewed version with local SEQ_NUM rule and FRAG_NUM-based remote indexing.
