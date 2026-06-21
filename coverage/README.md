# Coverage reports

This folder is prepared for the required reports:

```text
coverage/code_coverage/          VCS URG code coverage output
coverage/functional_coverage/    simulator log / covergroup summary
```

Run this on the EDA server after placing the RTL in `design/bird.sv` and uncommenting that line in `vcs.f`:

```bash
./scripts/run_regression.sh
```

The testbench prints covergroup summaries from `coverage.sv` at end of test. Save the final simulator log under `coverage/functional_coverage/functional_coverage.log`.
