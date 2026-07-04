// -----------------------------------------------------------------------------
// Smoke: single 1-layer program (vectors/npu/smoke_manifest.txt).
// -----------------------------------------------------------------------------
class npu_smoke_test extends npu_base_test;

  `uvm_component_utils(npu_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    `uvm_info("NPU_TEST", "npu_smoke_test: expects the smoke suite manifest", UVM_LOW)
  endfunction

endclass : npu_smoke_test
