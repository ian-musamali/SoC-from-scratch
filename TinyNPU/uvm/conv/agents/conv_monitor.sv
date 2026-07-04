// -----------------------------------------------------------------------------
// conv_engine monitor. Samples at every posedge outside reset:
//  - ofm write committed this edge (via the capture fm_mem_if's write port)
//      -> conv_write_txn on ap_write
//  - start accepted (start && !busy) -> sampled cfg snapshot (conv_txn) on
//      ap_start (case_dir unknown here; coverage does not need it)
//  - done pulse -> sat_seen bit on ap_done
// -----------------------------------------------------------------------------
class conv_monitor extends uvm_monitor;

  `uvm_component_utils(conv_monitor)

  virtual conv_ctrl_if ctrl_vif;
  virtual fm_mem_if    ofm_vif;

  uvm_analysis_port #(conv_write_txn) ap_write;
  uvm_analysis_port #(conv_txn)       ap_start;
  uvm_analysis_port #(bit)            ap_done;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_write = new("ap_write", this);
    ap_start = new("ap_start", this);
    ap_done  = new("ap_done", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual conv_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif))
      `uvm_fatal("NOVIF", "conv_monitor: virtual conv_ctrl_if not found under key 'ctrl_vif'")
    if (!uvm_config_db#(virtual fm_mem_if)::get(this, "", "ofm_vif", ofm_vif))
      `uvm_fatal("NOVIF", "conv_monitor: virtual fm_mem_if not found under key 'ofm_vif'")
  endfunction

  task run_phase(uvm_phase phase);
    conv_write_txn wt;
    conv_txn       st;

    forever begin
      @(posedge ctrl_vif.clk);
      if (ctrl_vif.rst_n !== 1'b1)
        continue;

      if (ofm_vif.wen === 1'b1) begin
        wt = conv_write_txn::type_id::create("wt");
        wt.addr = ofm_vif.waddr;
        wt.data = ofm_vif.wdata;
        ap_write.write(wt);
      end

      if (ctrl_vif.start === 1'b1 && ctrl_vif.busy !== 1'b1) begin
        st = conv_txn::type_id::create("st");
        st.img_w     = ctrl_vif.cfg_img_w;
        st.img_h     = ctrl_vif.cfg_img_h;
        st.in_ch     = ctrl_vif.cfg_in_ch;
        st.stride2   = ctrl_vif.cfg_stride2;
        st.pad       = ctrl_vif.cfg_pad;
        st.out_shift = ctrl_vif.cfg_out_shift;
        st.ifm_base  = ctrl_vif.cfg_ifm_base;
        st.ofm_base  = ctrl_vif.cfg_ofm_base;
        st.wgt_base  = ctrl_vif.cfg_wgt_base;
        st.acc_init  = $signed(ctrl_vif.cfg_acc_init);
        ap_start.write(st);
      end

      if (ctrl_vif.done === 1'b1)
        ap_done.write(ctrl_vif.sat_seen);
    end
  endtask

endclass : conv_monitor
