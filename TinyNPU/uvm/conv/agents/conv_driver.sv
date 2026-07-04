// -----------------------------------------------------------------------------
// conv_engine driver. Per sequence item (one conv case = one output channel):
// load the case's ifm/wgt memory images, drive the configuration, pulse start
// for one cycle, wait for the done pulse (with a generous timeout), then idle
// a few cycles before item_done.
// -----------------------------------------------------------------------------
class conv_driver extends uvm_driver #(conv_txn);

  `uvm_component_utils(conv_driver)

  localparam int unsigned DONE_TIMEOUT_CYCLES = 1_000_000;

  virtual conv_ctrl_if ctrl_vif;
  virtual rom_if #(tinynpu_pkg::FM_ADDR_W, tinynpu_pkg::DATA_W) ifm_vif;
  virtual rom_if wgt_vif;  // default parameterization (WGT_ADDR_W, DATA_W)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual conv_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif))
      `uvm_fatal("NOVIF", "conv_driver: virtual conv_ctrl_if not found under key 'ctrl_vif'")
    if (!uvm_config_db#(virtual rom_if#(tinynpu_pkg::FM_ADDR_W, tinynpu_pkg::DATA_W))::
        get(this, "", "ifm_vif", ifm_vif))
      `uvm_fatal("NOVIF", "conv_driver: ifm rom_if not found under key 'ifm_vif'")
    if (!uvm_config_db#(virtual rom_if)::get(this, "", "wgt_vif", wgt_vif))
      `uvm_fatal("NOVIF", "conv_driver: wgt rom_if not found under key 'wgt_vif'")
  endfunction

  task run_phase(uvm_phase phase);
    conv_txn req;

    ctrl_vif.start         <= 1'b0;
    ctrl_vif.cfg_img_w     <= '0;
    ctrl_vif.cfg_img_h     <= '0;
    ctrl_vif.cfg_in_ch     <= '0;
    ctrl_vif.cfg_stride2   <= 1'b0;
    ctrl_vif.cfg_pad       <= 1'b0;
    ctrl_vif.cfg_out_shift <= '0;
    ctrl_vif.cfg_ifm_base  <= '0;
    ctrl_vif.cfg_ofm_base  <= '0;
    ctrl_vif.cfg_wgt_base  <= '0;
    ctrl_vif.cfg_acc_init  <= '0;

    forever begin
      seq_item_port.get_next_item(req);
      drive_txn(req);
      seq_item_port.item_done();
    end
  endtask

  protected task drive_txn(conv_txn t);
    int unsigned cyc;
    bit          timed_out;

    if (ctrl_vif.rst_n !== 1'b1) begin
      wait (ctrl_vif.rst_n === 1'b1);
      @(posedge ctrl_vif.clk);
    end

    ifm_vif.load({t.case_dir, "/ifm.memh"});
    wgt_vif.load({t.case_dir, "/wgt.memh"});

    ctrl_vif.cfg_img_w     <= t.img_w;
    ctrl_vif.cfg_img_h     <= t.img_h;
    ctrl_vif.cfg_in_ch     <= t.in_ch;
    ctrl_vif.cfg_stride2   <= t.stride2;
    ctrl_vif.cfg_pad       <= t.pad;
    ctrl_vif.cfg_out_shift <= t.out_shift;
    ctrl_vif.cfg_ifm_base  <= t.ifm_base;
    ctrl_vif.cfg_ofm_base  <= t.ofm_base;
    ctrl_vif.cfg_wgt_base  <= t.wgt_base;
    ctrl_vif.cfg_acc_init  <= t.acc_init;
    @(posedge ctrl_vif.clk);

    ctrl_vif.start <= 1'b1;
    @(posedge ctrl_vif.clk);
    ctrl_vif.start <= 1'b0;

    `uvm_info("DRV", $sformatf("started case: %s", t.convert2string()), UVM_MEDIUM)

    timed_out = 1'b1;
    for (cyc = 0; cyc < DONE_TIMEOUT_CYCLES; cyc++) begin
      @(posedge ctrl_vif.clk);
      if (ctrl_vif.done === 1'b1) begin
        timed_out = 1'b0;
        break;
      end
    end
    if (timed_out)
      `uvm_error("DRV_TIMEOUT", $sformatf(
        "no done pulse within %0d cycles for case %s",
        DONE_TIMEOUT_CYCLES, t.case_dir))
    else
      `uvm_info("DRV", $sformatf("done observed for case %s (sat_seen=%0b)",
                                 t.case_dir, ctrl_vif.sat_seen), UVM_MEDIUM)

    repeat (5) @(posedge ctrl_vif.clk);
  endtask

endclass : conv_driver
