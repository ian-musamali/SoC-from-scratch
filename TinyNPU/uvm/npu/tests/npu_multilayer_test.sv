// -----------------------------------------------------------------------------
// Multilayer: 3-layer ping-pong program + CIFAR-shaped 5-layer 32x32x3 ->
// 1x1x4 program (vectors/npu/multilayer_manifest.txt).
// -----------------------------------------------------------------------------
class npu_multilayer_test extends npu_base_test;

  `uvm_component_utils(npu_multilayer_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    `uvm_info("NPU_TEST", "npu_multilayer_test: expects the multilayer suite manifest", UVM_LOW)
  endfunction

endclass : npu_multilayer_test
