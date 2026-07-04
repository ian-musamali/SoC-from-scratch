// -----------------------------------------------------------------------------
// Trivial mac_txn sequencer; extended (rather than typedef'd) so it is
// factory-overridable by name.
// -----------------------------------------------------------------------------
class mac_sequencer extends uvm_sequencer #(mac_txn);

  `uvm_component_utils(mac_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : mac_sequencer
