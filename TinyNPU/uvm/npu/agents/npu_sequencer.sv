// -----------------------------------------------------------------------------
// npu_core sequencer: plain uvm_sequencer over npu_txn.
// -----------------------------------------------------------------------------
class npu_sequencer extends uvm_sequencer #(npu_txn);

  `uvm_component_utils(npu_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : npu_sequencer
