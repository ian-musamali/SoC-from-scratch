// -----------------------------------------------------------------------------
// random suite: seeded constrained-random cases from the Python generator
// (the +CONV_MANIFEST plusarg selects the matching vector suite).
// -----------------------------------------------------------------------------
class conv_unit_random_test extends conv_base_test;

  `uvm_component_utils(conv_unit_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    `uvm_info("CONV_TEST", "conv_unit_random_test: expects the random suite manifest", UVM_LOW)
  endfunction

endclass : conv_unit_random_test
