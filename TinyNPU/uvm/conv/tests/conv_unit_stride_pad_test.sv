// -----------------------------------------------------------------------------
// stride_pad suite: all stride x pad combos incl. 1x1 image and rectangular images
// (the +CONV_MANIFEST plusarg selects the matching vector suite).
// -----------------------------------------------------------------------------
class conv_unit_stride_pad_test extends conv_base_test;

  `uvm_component_utils(conv_unit_stride_pad_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    `uvm_info("CONV_TEST", "conv_unit_stride_pad_test: expects the stride_pad suite manifest", UVM_LOW)
  endfunction

endclass : conv_unit_stride_pad_test
