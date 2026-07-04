// -----------------------------------------------------------------------------
// Random test: 500 constrained-random data vectors (vectors/random.txt, data
// randomness lives in the seeded Python generator) with SV-randomized
// protocol timing: idle gaps 0..5 and ~80%-high random out_ready
// backpressure (driver default).
// -----------------------------------------------------------------------------
class mac_unit_random_test extends mac_base_test;

  `uvm_component_utils(mac_unit_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    mac_file_seq seq;
    phase.raise_objection(this, "mac_unit_random_test main sequence");
    wait_reset_release();
    seq = mac_file_seq::type_id::create("seq");
    seq.randomize_idle = 1;
    seq.start(env.agent.sqr);
    drain();
    phase.drop_objection(this, "mac_unit_random_test main sequence");
  endtask

endclass : mac_unit_random_test
