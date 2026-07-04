// -----------------------------------------------------------------------------
// npu_core monitor. Samples at every posedge outside reset (values read in
// the active region are the stable pre-edge values, i.e. exactly what the
// interface/DUT flops sampled at that edge):
//   - fm write committed this edge  -> npu_write_txn on ap_write
//   - start accepted (start&&!busy) -> sampled program (npu_txn) on ap_start
//   - done pulse                    -> sat_seen bit on ap_done
// -----------------------------------------------------------------------------

// One committed fm-buffer write.
class npu_write_txn extends uvm_sequence_item;

  `uvm_object_utils(npu_write_txn)

  bit [tinynpu_pkg::FM_ADDR_W-1:0] addr;
  bit [tinynpu_pkg::DATA_W-1:0]    data;

  function new(string name = "npu_write_txn");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("fm write @%04h data=%02h", addr, data);
  endfunction

endclass : npu_write_txn

class npu_monitor extends uvm_monitor;

  `uvm_component_utils(npu_monitor)

  virtual npu_ctrl_if ctrl_vif;
  virtual fm_mem_if   fm_vif;

  uvm_analysis_port #(npu_write_txn) ap_write;
  uvm_analysis_port #(npu_txn)       ap_start;
  uvm_analysis_port #(bit)           ap_done;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_write = new("ap_write", this);
    ap_start = new("ap_start", this);
    ap_done  = new("ap_done", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual npu_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif))
      `uvm_fatal("NOVIF", "npu_monitor: virtual npu_ctrl_if not found under key 'ctrl_vif'")
    if (!uvm_config_db#(virtual fm_mem_if)::get(this, "", "fm_vif", fm_vif))
      `uvm_fatal("NOVIF", "npu_monitor: virtual fm_mem_if not found under key 'fm_vif'")
  endfunction

  task run_phase(uvm_phase phase);
    npu_write_txn wt;
    npu_txn       st;

    forever begin
      @(posedge ctrl_vif.clk);
      if (ctrl_vif.rst_n !== 1'b1)
        continue;

      // fm write committed at this edge
      if (fm_vif.wen === 1'b1) begin
        wt = npu_write_txn::type_id::create("wt");
        wt.addr = fm_vif.waddr;
        wt.data = fm_vif.wdata;
        ap_write.write(wt);
      end

      // start accepted at this edge: publish the sampled layer program
      if (ctrl_vif.start === 1'b1 && ctrl_vif.busy !== 1'b1) begin
        st = npu_txn::type_id::create("st");
        st.num_layers = ctrl_vif.cfg_num_layers;
        for (int i = 0; i < tinynpu_pkg::MAX_LAYERS; i++)
          st.descs[i] = ctrl_vif.cfg_layers[i];
        ap_start.write(st);
      end

      // done pulse: publish the sticky saturation flag
      if (ctrl_vif.done === 1'b1)
        ap_done.write(ctrl_vif.sat_seen);
    end
  endtask

endclass : npu_monitor
