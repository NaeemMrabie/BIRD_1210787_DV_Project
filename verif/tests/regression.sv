// ============================================================
// regression.sv
// ------------------------------------------------------------
// Top-level plain SystemVerilog regression controller.
// Runs directed tests first, then random/constrained-random tests,
// and prints functional coverage through the scoreboard reports.
// ============================================================

`ifndef REGRESSION_SV
`define REGRESSION_SV

`include "test_directed.sv"
`include "test_random.sv"

class bird_regression;
  virtual bird_if vif;
  environment     env;

  function new(virtual bird_if vif);
    this.vif = vif;
    this.env = new(vif);
  endfunction

  task print_test_id_map();
    $display("==================================================");
    $display("[REGRESSION] TEST_ID map");
    $display("  0  : full regression = directed then random");
    $display("  1  : directed suite only");
    $display("  2  : random suite only");
    $display("  3  : test_reset_behavior");
    $display("  4  : test_basic_local_legal");
    $display("  5  : test_local_bad_frag_num");
    $display("  6  : test_local_seq_no_functional_impact");
    $display("  7  : test_basic_remote_inorder");
    $display("  8  : test_remote_outoforder");
    $display("  9  : test_remote_seq_mismatch_drop");
    $display("  10 : test_drop_seq_zero");
    $display("  11 : test_drop_frag_zero");
    $display("  12 : test_drop_payload_len_zero");
    $display("  13 : test_drop_reserved_bits");
    $display("  14 : test_dropcnt_many_wrap");
    $display("  15 : test_backpressure_stability");
    $display("  16 : test_multi_packet_back_to_back");
    $display("  17 : test_boundary_max_values");
    $display("  18 : test_random_local_legal");
    $display("  19 : test_random_remote_packets");
    $display("  20 : test_random_invalid_cfg");
    $display("  21 : test_random_backpressure_matrix");
    $display("  22 : test_random_mixed_traffic");
    $display("==================================================");
  endtask

  task run_directed();
    test_reset_behavior                    t_reset;
    test_basic_local_legal                 t_local;
    test_local_bad_frag_num                t_local_bad_frag;
    test_local_seq_no_functional_impact    t_local_seq;
    test_basic_remote_inorder              t_remote_in;
    test_remote_outoforder                 t_remote_ooo;
    test_remote_seq_mismatch_drop          t_remote_mismatch;
    test_drop_seq_zero                     t_drop_seq;
    test_drop_frag_zero                    t_drop_frag;
    test_drop_payload_len_zero             t_drop_len;
    test_drop_reserved_bits                t_drop_reserved;
    test_dropcnt_many_wrap                 t_dropcnt;
    test_backpressure_stability            t_bp;
    test_multi_packet_back_to_back         t_multi;
    test_boundary_max_values               t_boundary;

    $display("[REGRESSION] Directed suite START");

    t_reset           = new(env);     t_reset.run();
    t_local           = new(env);     t_local.run();
    t_local_bad_frag  = new(env);     t_local_bad_frag.run();
    t_local_seq       = new(env);     t_local_seq.run();
    t_remote_in       = new(env);     t_remote_in.run();
    t_remote_ooo      = new(env);     t_remote_ooo.run();
    t_remote_mismatch = new(env);     t_remote_mismatch.run();
    t_drop_seq        = new(env);     t_drop_seq.run();
    t_drop_frag       = new(env);     t_drop_frag.run();
    t_drop_len        = new(env);     t_drop_len.run();
    t_drop_reserved   = new(env);     t_drop_reserved.run();
    t_dropcnt         = new(env, 20); t_dropcnt.run();
    t_bp              = new(env);     t_bp.run();
    t_multi           = new(env);     t_multi.run();
    t_boundary        = new(env);     t_boundary.run();

    $display("[REGRESSION] Directed suite END");
  endtask

  task run_random();
    test_random_local_legal          t_rand_local;
    test_random_remote_packets       t_rand_remote;
    test_random_invalid_cfg          t_rand_invalid;
    test_random_backpressure_matrix  t_rand_bp;
    test_random_mixed_traffic        t_rand_mixed;

    $display("[REGRESSION] Random suite START");

    t_rand_local   = new(env, 25); t_rand_local.run();
    t_rand_remote  = new(env, 10); t_rand_remote.run();
    t_rand_invalid = new(env, 25); t_rand_invalid.run();
    t_rand_bp      = new(env);     t_rand_bp.run();
    t_rand_mixed   = new(env, 50); t_rand_mixed.run();

    $display("[REGRESSION] Random suite END");
  endtask

  task run_full();
    $display("[REGRESSION] FULL regression START: directed then random");
    run_directed();
    run_random();
    $display("==================================================");
    $display("[REGRESSION] FULL regression COMPLETE");
    $display("[REGRESSION] Final cumulative functional coverage snapshot:");
    env.sb.cov.report();
    $display("==================================================");
  endtask

  task run_by_id(int unsigned test_id);
    test_reset_behavior                    t_reset;
    test_basic_local_legal                 t_local;
    test_local_bad_frag_num                t_local_bad_frag;
    test_local_seq_no_functional_impact    t_local_seq;
    test_basic_remote_inorder              t_remote_in;
    test_remote_outoforder                 t_remote_ooo;
    test_remote_seq_mismatch_drop          t_remote_mismatch;
    test_drop_seq_zero                     t_drop_seq;
    test_drop_frag_zero                    t_drop_frag;
    test_drop_payload_len_zero             t_drop_len;
    test_drop_reserved_bits                t_drop_reserved;
    test_dropcnt_many_wrap                 t_dropcnt;
    test_backpressure_stability            t_bp;
    test_multi_packet_back_to_back         t_multi;
    test_boundary_max_values               t_boundary;
    test_random_local_legal                t_rand_local;
    test_random_remote_packets             t_rand_remote;
    test_random_invalid_cfg                t_rand_invalid;
    test_random_backpressure_matrix        t_rand_bp;
    test_random_mixed_traffic              t_rand_mixed;

    print_test_id_map();

    case (test_id)
      0:  run_full();
      1:  run_directed();
      2:  run_random();
      3:  begin t_reset           = new(env);     t_reset.run();           end
      4:  begin t_local           = new(env);     t_local.run();           end
      5:  begin t_local_bad_frag  = new(env);     t_local_bad_frag.run();  end
      6:  begin t_local_seq       = new(env);     t_local_seq.run();       end
      7:  begin t_remote_in       = new(env);     t_remote_in.run();       end
      8:  begin t_remote_ooo      = new(env);     t_remote_ooo.run();      end
      9:  begin t_remote_mismatch = new(env);     t_remote_mismatch.run(); end
      10: begin t_drop_seq        = new(env);     t_drop_seq.run();        end
      11: begin t_drop_frag       = new(env);     t_drop_frag.run();       end
      12: begin t_drop_len        = new(env);     t_drop_len.run();        end
      13: begin t_drop_reserved   = new(env);     t_drop_reserved.run();   end
      14: begin t_dropcnt         = new(env, 20); t_dropcnt.run();         end
      15: begin t_bp              = new(env);     t_bp.run();              end
      16: begin t_multi           = new(env);     t_multi.run();           end
      17: begin t_boundary        = new(env);     t_boundary.run();        end
      18: begin t_rand_local      = new(env, 25); t_rand_local.run();      end
      19: begin t_rand_remote     = new(env, 10); t_rand_remote.run();     end
      20: begin t_rand_invalid    = new(env, 25); t_rand_invalid.run();    end
      21: begin t_rand_bp         = new(env);     t_rand_bp.run();         end
      22: begin t_rand_mixed      = new(env, 50); t_rand_mixed.run();      end
      default: begin
        $display("[REGRESSION] Unknown TEST_ID=%0d, running full regression", test_id);
        run_full();
      end
    endcase
  endtask
endclass

`endif // REGRESSION_SV
