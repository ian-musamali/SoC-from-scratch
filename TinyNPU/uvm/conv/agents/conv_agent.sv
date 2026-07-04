// -----------------------------------------------------------------------------
// conv_engine agent: sequencer + driver + monitor.
// -----------------------------------------------------------------------------
class conv_agent extends uvm_agent;

  `uvm_component_utils(conv_agent)

  conv_sequencer sqr;
  conv_driver    drv;
  conv_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = conv_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sqr = conv_sequencer::type_id::create("sqr", this);
      drv = conv_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : conv_agent
