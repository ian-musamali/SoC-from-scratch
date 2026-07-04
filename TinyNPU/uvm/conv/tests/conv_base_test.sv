// -----------------------------------------------------------------------------
// Base test: builds conv_env and runs the manifest suite. Prints the exact
// pass/fail banner the Makefile greps for; a run where the scoreboard
// compared nothing or the responder served nothing prints FAILED even with
// zero UVM errors (an env that silently checks nothing must fail).
// -----------------------------------------------------------------------------
class conv_base_test extends uvm_test;

  `uvm_component_utils(conv_base_test)

  conv_env             env;
  virtual conv_ctrl_if ctrl_vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = conv_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual conv_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif))
      `uvm_fatal("NOVIF", "conv_base_test: virtual conv_ctrl_if not found under key 'ctrl_vif'")
  endfunction

  task run_phase(uvm_phase phase);
    conv_manifest_seq seq;

    phase.raise_objection(this, "conv manifest suite");

    if (ctrl_vif.rst_n !== 1'b1)
      @(posedge ctrl_vif.rst_n);
    @(posedge ctrl_vif.clk);

    seq = conv_manifest_seq::type_id::create("seq");
    seq.start(env.agent.sqr);

    repeat (50) @(posedge ctrl_vif.clk);
    phase.drop_objection(this, "conv manifest suite");
  endtask

  function void final_phase(uvm_phase phase);
    uvm_report_server svr;
    super.final_phase(phase);
    svr = uvm_report_server::get_server();
    $display("[%s] UVM_ERROR=%0d UVM_FATAL=%0d scoreboard compared=%0d matched=%0d responder served=%0d",
             get_type_name(),
             svr.get_severity_count(UVM_ERROR),
             svr.get_severity_count(UVM_FATAL),
             env.sb.num_compared, env.sb.num_matched, env.responder.num_served);
    if (svr.get_severity_count(UVM_ERROR) == 0 &&
        svr.get_severity_count(UVM_FATAL) == 0 &&
        env.sb.num_compared > 0 && env.responder.num_served > 0)
      $display("TINYNPU TEST PASSED");
    else
      $display("TINYNPU TEST FAILED");
  endfunction

endclass : conv_base_test
