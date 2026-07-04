// -----------------------------------------------------------------------------
// npu_core agent: always-active sequencer + driver + monitor.
// -----------------------------------------------------------------------------
class npu_agent extends uvm_agent;

  `uvm_component_utils(npu_agent)

  npu_sequencer sqr;
  npu_driver    drv;
  npu_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = npu_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sqr = npu_sequencer::type_id::create("sqr", this);
      drv = npu_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : npu_agent
