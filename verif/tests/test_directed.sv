// ============================================================
// test_directed.sv
// ------------------------------------------------------------
// Directed tests: one test class per directed spec function.
// Each test uses the matching sequence from verif/seq/sequences.sv.
// Plain SystemVerilog, no UVM.
// ============================================================

`ifndef TEST_DIRECTED_SV
`define TEST_DIRECTED_SV

`include "sequences.sv"

class bird_directed_test_base;
  environment env;
  string      test_name;

  function new(environment env, string test_name = "bird_directed_test_base");
    this.env       = env;
    this.test_name = test_name;
  endfunction

  task pre_test();
    $display("==================================================");
    $display("[TEST] %s: START", test_name);
    env.apply_reset();
    env.run();
  endtask

  task post_test(int unsigned extra_cycles = 100);
    env.wait_drain(extra_cycles);
    $display("==================================================");
    $display("[TEST] %s COMPLETE", test_name);
    env.report();
  endtask

  virtual task run();
    $fatal(1, "[TEST] run() not implemented for %s", test_name);
  endtask
endclass

class test_reset_behavior extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_reset_behavior"); endfunction
  virtual task run();
    seq_reset_behavior s;
    pre_test();
    s = new(env); s.start();
    post_test();
  endtask
endclass

class test_basic_local_legal extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_basic_local_legal"); endfunction
  virtual task run();
    seq_local_legal s;
    pre_test();
    s = new(env, 5); s.start();
    post_test();
  endtask
endclass

class test_local_bad_frag_num extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_local_bad_frag_num"); endfunction
  virtual task run();
    seq_local_bad_frag_num s;
    pre_test();
    s = new(env); s.start();
    post_test();
  endtask
endclass

class test_local_seq_no_functional_impact extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_local_seq_no_functional_impact"); endfunction
  virtual task run();
    seq_local_seq_no_functional_impact s;
    pre_test();
    s = new(env); s.start();
    post_test();
  endtask
endclass

class test_basic_remote_inorder extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_basic_remote_inorder"); endfunction
  virtual task run();
    seq_remote_inorder s;
    pre_test();
    s = new(env, 9, 4); s.start();
    post_test();
  endtask
endclass

class test_remote_outoforder extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_remote_outoforder"); endfunction
  virtual task run();
    seq_remote_outoforder s;
    pre_test();
    s = new(env); s.start();
    post_test();
  endtask
endclass

class test_remote_seq_mismatch_drop extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_remote_seq_mismatch_drop"); endfunction
  virtual task run();
    seq_remote_seq_mismatch_drop s;
    pre_test();
    s = new(env); s.start();
    post_test();
  endtask
endclass

class test_drop_seq_zero extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_drop_seq_zero"); endfunction
  virtual task run();
    seq_drop_seq_zero s;
    pre_test();
    s = new(env); s.start();
    post_test();
  endtask
endclass

class test_drop_frag_zero extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_drop_frag_zero"); endfunction
  virtual task run();
    seq_drop_frag_zero s;
    pre_test();
    s = new(env); s.start();
    post_test();
  endtask
endclass

class test_drop_payload_len_zero extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_drop_payload_len_zero"); endfunction
  virtual task run();
    seq_drop_payload_len_zero s;
    pre_test();
    s = new(env); s.start();
    post_test();
  endtask
endclass

class test_drop_reserved_bits extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_drop_reserved_bits"); endfunction
  virtual task run();
    seq_drop_reserved_bits s;
    pre_test();
    s = new(env); s.start();
    post_test();
  endtask
endclass

class test_dropcnt_many_wrap extends bird_directed_test_base;
  int unsigned num_drops;
  function new(environment env, int unsigned num_drops = 20);
    super.new(env, "test_dropcnt_many_wrap");
    this.num_drops = num_drops;
  endfunction
  virtual task run();
    seq_dropcnt_many_wrap s;
    pre_test();
    s = new(env, num_drops); s.start();
    post_test(300);
  endtask
endclass

class test_backpressure_stability extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_backpressure_stability"); endfunction
  virtual task run();
    seq_backpressure_stability s;
    pre_test();
    s = new(env); s.start();
    post_test(200);
  endtask
endclass

class test_multi_packet_back_to_back extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_multi_packet_back_to_back"); endfunction
  virtual task run();
    seq_multi_packet_back_to_back s;
    pre_test();
    s = new(env); s.start();
    post_test(300);
  endtask
endclass

class test_boundary_max_values extends bird_directed_test_base;
  function new(environment env); super.new(env, "test_boundary_max_values"); endfunction
  virtual task run();
    seq_boundary_max_values s;
    pre_test();
    s = new(env); s.start();
    post_test(500);
  endtask
endclass

`endif // TEST_DIRECTED_SV
