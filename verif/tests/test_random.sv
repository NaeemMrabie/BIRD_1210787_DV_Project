// ============================================================
// test_random.sv
// ------------------------------------------------------------
// Random / constrained-random tests.  Each class uses a sequence
// from verif/seq/sequences.sv.  Plain SystemVerilog, no UVM.
// ============================================================

`ifndef TEST_RANDOM_SV
`define TEST_RANDOM_SV

`include "test_directed.sv"

class bird_random_test_base extends bird_directed_test_base;
  function new(environment env, string test_name = "bird_random_test_base");
    super.new(env, test_name);
  endfunction
endclass

class test_random_local_legal extends bird_random_test_base;
  int unsigned n;
  function new(environment env, int unsigned n = 25);
    super.new(env, "test_random_local_legal");
    this.n = n;
  endfunction
  virtual task run();
    seq_random_local_legal s;
    pre_test();
    s = new(env, n); s.start();
    post_test(300);
  endtask
endclass

class test_random_remote_packets extends bird_random_test_base;
  int unsigned n_packets;
  function new(environment env, int unsigned n_packets = 10);
    super.new(env, "test_random_remote_packets");
    this.n_packets = n_packets;
  endfunction
  virtual task run();
    seq_random_remote_packets s;
    pre_test();
    s = new(env, n_packets); s.start();
    post_test(400);
  endtask
endclass

class test_random_invalid_cfg extends bird_random_test_base;
  int unsigned n;
  function new(environment env, int unsigned n = 25);
    super.new(env, "test_random_invalid_cfg");
    this.n = n;
  endfunction
  virtual task run();
    seq_random_invalid_cfg s;
    pre_test();
    s = new(env, n); s.start();
    post_test(400);
  endtask
endclass

class test_random_backpressure_matrix extends bird_random_test_base;
  function new(environment env);
    super.new(env, "test_random_backpressure_matrix");
  endfunction
  virtual task run();
    seq_random_backpressure_matrix s;
    pre_test();
    s = new(env); s.start();
    post_test(500);
  endtask
endclass

class test_random_mixed_traffic extends bird_random_test_base;
  int unsigned n;
  function new(environment env, int unsigned n = 50);
    super.new(env, "test_random_mixed_traffic");
    this.n = n;
  endfunction
  virtual task run();
    seq_random_mixed_traffic s;
    pre_test();
    s = new(env, n); s.start();
    post_test(600);
  endtask
endclass

`endif // TEST_RANDOM_SV
