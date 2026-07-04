// -----------------------------------------------------------------------------
// Base test: builds mac_env, provides reset-sync / objection-drain helpers
// for the concrete tests, and prints the exact pass/fail verdict string that
// the Makefile greps for. A run where the scoreboard compared nothing prints
// FAILED even with zero UVM errors.
// -----------------------------------------------------------------------------
class mac_base_test extends uvm_test;

  `uvm_component_utils(mac_base_test)

  mac_env        env;
  virtual mac_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = mac_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual mac_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "mac_base_test: virtual mac_if not found in config db under key 'vif'")
  endfunction

  // Block until the initial reset has been released, aligned to a posedge
  protected task wait_reset_release();
    if (vif.rst_n !== 1'b1)
      @(posedge vif.rst_n);
    @(posedge vif.clk);
  endtask

  // End-of-test drain: let the last accepted transaction's output be consumed
  // (out_ready is ~80% high in random mode, so 50 cycles is ample margin)
  protected task drain(int unsigned cycles = 50);
    repeat (cycles) @(posedge vif.clk);
  endtask

  function void final_phase(uvm_phase phase);
    uvm_report_server svr;
    super.final_phase(phase);
    svr = uvm_report_server::get_server();
    $display("[%s] UVM_ERROR=%0d UVM_FATAL=%0d scoreboard compared=%0d matched=%0d",
             get_type_name(),
             svr.get_severity_count(UVM_ERROR),
             svr.get_severity_count(UVM_FATAL),
             env.sb.num_compared, env.sb.num_matched);
    if (svr.get_severity_count(UVM_ERROR) == 0 &&
        svr.get_severity_count(UVM_FATAL) == 0 &&
        env.sb.num_compared > 0)
      $display("TINYNPU TEST PASSED");
    else
      $display("TINYNPU TEST FAILED");
  endfunction

endclass : mac_base_test
