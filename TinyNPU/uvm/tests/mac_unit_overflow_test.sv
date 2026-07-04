// -----------------------------------------------------------------------------
// Overflow test: saturation at both rails and exact boundary cases
// (vectors/overflow.txt) with directed timing — zero idle gaps, out_ready
// held high. The file expectations already encode acc_out and sat_flag for
// every saturating case; the scoreboard checks them bit-exactly.
// -----------------------------------------------------------------------------
class mac_unit_overflow_test extends mac_base_test;

  `uvm_component_utils(mac_unit_overflow_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(bit)::set(this, "env.agent.drv", "out_ready_always_on", 1'b1);
  endfunction

  task run_phase(uvm_phase phase);
    mac_file_seq seq;
    phase.raise_objection(this, "mac_unit_overflow_test main sequence");
    wait_reset_release();
    seq = mac_file_seq::type_id::create("seq");
    seq.randomize_idle = 0;
    seq.start(env.agent.sqr);
    drain();
    phase.drop_objection(this, "mac_unit_overflow_test main sequence");
  endtask

endclass : mac_unit_overflow_test
