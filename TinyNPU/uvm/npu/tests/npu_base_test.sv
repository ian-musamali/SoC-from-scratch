// -----------------------------------------------------------------------------
// Base test: builds npu_env and runs every manifest case through npu_case_seq,
// performing the end-of-case FULL fm-buffer compare against fm_final.memh
// (task context, via fm_mem_if.compare_against). Prints the exact pass/fail
// banner the Makefile greps for; a run where the scoreboard compared nothing
// or no final check ran prints FAILED even with zero UVM errors.
// -----------------------------------------------------------------------------
class npu_base_test extends uvm_test;

  `uvm_component_utils(npu_base_test)

  npu_env             env;
  virtual npu_ctrl_if ctrl_vif;
  virtual fm_mem_if   fm_vif;

  int unsigned total_final_checks;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = npu_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual npu_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif))
      `uvm_fatal("NOVIF", "npu_base_test: virtual npu_ctrl_if not found under key 'ctrl_vif'")
    if (!uvm_config_db#(virtual fm_mem_if)::get(this, "", "fm_vif", fm_vif))
      `uvm_fatal("NOVIF", "npu_base_test: virtual fm_mem_if not found under key 'fm_vif'")
  endfunction

  task run_phase(uvm_phase phase);
    string       dir, mfile, names[$];
    npu_case_seq seq;
    int          mismatches;

    phase.raise_objection(this, "npu test case loop");

    if (!$value$plusargs("NPU_DIR=%s", dir))
      `uvm_fatal("NPU_TEST", "+NPU_DIR plusarg is required")
    if (!$value$plusargs("NPU_MANIFEST=%s", mfile))
      `uvm_fatal("NPU_TEST", "+NPU_MANIFEST plusarg is required")
    if (!npu_parse_manifest(mfile, names) || names.size() == 0)
      `uvm_fatal("NPU_TEST", {"cannot read manifest: ", mfile})

    // Wait for power-on reset release, aligned to a posedge
    if (ctrl_vif.rst_n !== 1'b1)
      @(posedge ctrl_vif.rst_n);
    @(posedge ctrl_vif.clk);

    foreach (names[i]) begin
      seq = npu_case_seq::type_id::create($sformatf("seq_%0d", i));
      seq.case_dir = {dir, "/", names[i]};
      seq.start(env.agent.sqr);

      repeat (5) @(posedge ctrl_vif.clk);

      fm_vif.compare_against({dir, "/", names[i], "/fm_final.memh"}, mismatches);
      if (mismatches != 0)
        `uvm_error("NPU_TEST", $sformatf(
          "case %s: final fm image differs from golden in %0d location(s)",
          names[i], mismatches))
      else
        `uvm_info("NPU_TEST", $sformatf("case %s: final fm image matches golden",
                                        names[i]), UVM_LOW)
      total_final_checks++;
    end

    repeat (20) @(posedge ctrl_vif.clk);
    phase.drop_objection(this, "npu test case loop");
  endtask

  function void final_phase(uvm_phase phase);
    uvm_report_server svr;
    super.final_phase(phase);
    svr = uvm_report_server::get_server();
    $display("[%s] UVM_ERROR=%0d UVM_FATAL=%0d scoreboard compared=%0d matched=%0d final_checks=%0d",
             get_type_name(),
             svr.get_severity_count(UVM_ERROR),
             svr.get_severity_count(UVM_FATAL),
             env.sb.num_compared, env.sb.num_matched, total_final_checks);
    if (svr.get_severity_count(UVM_ERROR) == 0 &&
        svr.get_severity_count(UVM_FATAL) == 0 &&
        env.sb.num_compared > 0 && total_final_checks > 0)
      $display("TINYNPU TEST PASSED");
    else
      $display("TINYNPU TEST FAILED");
  endfunction

endclass : npu_base_test
