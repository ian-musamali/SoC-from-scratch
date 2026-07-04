// -----------------------------------------------------------------------------
// Smoke test: 12 directed known-answer vectors (vectors/smoke.txt), zero idle
// gaps, out_ready held high — pure directed timing.
// -----------------------------------------------------------------------------
class mac_unit_smoke_test extends mac_base_test;

  `uvm_component_utils(mac_unit_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(bit)::set(this, "env.agent.drv", "out_ready_always_on", 1'b1);
  endfunction

  task run_phase(uvm_phase phase);
    mac_file_seq seq;
    phase.raise_objection(this, "mac_unit_smoke_test main sequence");
    wait_reset_release();
    seq = mac_file_seq::type_id::create("seq");
    seq.randomize_idle = 0;
    seq.start(env.agent.sqr);
    drain();
    phase.drop_objection(this, "mac_unit_smoke_test main sequence");
  endtask

endclass : mac_unit_smoke_test
