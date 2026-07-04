// -----------------------------------------------------------------------------
// conv_engine sequencer: plain uvm_sequencer over conv_txn.
// -----------------------------------------------------------------------------
class conv_sequencer extends uvm_sequencer #(conv_txn);

  `uvm_component_utils(conv_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : conv_sequencer
