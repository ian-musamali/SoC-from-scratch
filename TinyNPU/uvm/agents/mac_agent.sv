// -----------------------------------------------------------------------------
// Active MAC agent: sequencer + driver + passive monitor.
// -----------------------------------------------------------------------------
class mac_agent extends uvm_agent;

  `uvm_component_utils(mac_agent)

  mac_sequencer sqr;
  mac_driver    drv;
  mac_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = mac_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sqr = mac_sequencer::type_id::create("sqr", this);
      drv = mac_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : mac_agent
