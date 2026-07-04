// -----------------------------------------------------------------------------
// npu_core driver. Per sequence item (one whole layer program):
//   1. wait out of reset;
//   2. load <case_dir>/fm_init.memh and <case_dir>/wgt.memh into the
//      behavioral memories (load() zeroes them first);
//   3. drive cfg_layers / cfg_num_layers and a 1-cycle start pulse;
//   4. wait for the done pulse with a generous cycle timeout (the
//      cifar-shaped case runs ~3400 serialized MAC transactions);
//   5. 5 idle cycles, then item_done.
// -----------------------------------------------------------------------------
class npu_driver extends uvm_driver #(npu_txn);

  `uvm_component_utils(npu_driver)

  // Cycle budget per program run before declaring the DUT hung
  localparam int unsigned DONE_TIMEOUT_CYCLES = 5_000_000;

  virtual npu_ctrl_if ctrl_vif;
  virtual fm_mem_if   fm_vif;   // default parameterization (FM_ADDR_W, DATA_W)
  virtual rom_if      wgt_vif;  // default parameterization (WGT_ADDR_W, DATA_W)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual npu_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif))
      `uvm_fatal("NOVIF", "npu_driver: virtual npu_ctrl_if not found under key 'ctrl_vif'")
    if (!uvm_config_db#(virtual fm_mem_if)::get(this, "", "fm_vif", fm_vif))
      `uvm_fatal("NOVIF", "npu_driver: virtual fm_mem_if not found under key 'fm_vif'")
    if (!uvm_config_db#(virtual rom_if)::get(this, "", "wgt_vif", wgt_vif))
      `uvm_fatal("NOVIF", "npu_driver: virtual rom_if not found under key 'wgt_vif'")
  endfunction

  task run_phase(uvm_phase phase);
    npu_txn req;

    // Initialize interface outputs before reset release
    ctrl_vif.start          <= 1'b0;
    ctrl_vif.cfg_num_layers <= '0;
    ctrl_vif.cfg_layers     <= '0;

    forever begin
      seq_item_port.get_next_item(req);
      drive_txn(req);
      seq_item_port.item_done();
    end
  endtask

  protected task drive_txn(npu_txn t);
    logic [66:0]  dval;
    int unsigned  cyc;
    bit           timed_out;

    // Wait out of reset, aligned to a posedge
    if (ctrl_vif.rst_n !== 1'b1) begin
      wait (ctrl_vif.rst_n === 1'b1);
      @(posedge ctrl_vif.clk);
    end

    // Load the case's memory images (load() zeroes the arrays first)
    fm_vif.load({t.case_dir, "/fm_init.memh"});
    wgt_vif.load({t.case_dir, "/wgt.memh"});

    // Drive the layer program; unused upper descriptor slots are '0
    for (int i = 0; i < tinynpu_pkg::MAX_LAYERS; i++) begin
      dval = (i < t.num_layers) ? t.descs[i] : '0;
      ctrl_vif.cfg_layers[i] <= dval;
    end
    ctrl_vif.cfg_num_layers <= 3'(t.num_layers);
    @(posedge ctrl_vif.clk);

    // 1-cycle start pulse
    ctrl_vif.start <= 1'b1;
    @(posedge ctrl_vif.clk);
    ctrl_vif.start <= 1'b0;

    `uvm_info("DRV", $sformatf("started program: %s", t.convert2string()), UVM_MEDIUM)

    // Wait for the done pulse with a timeout
    timed_out = 1'b1;
    for (cyc = 0; cyc < DONE_TIMEOUT_CYCLES; cyc++) begin
      @(posedge ctrl_vif.clk);
      if (ctrl_vif.done === 1'b1) begin
        timed_out = 1'b0;
        break;
      end
    end
    if (timed_out)
      `uvm_error("DRV_TIMEOUT",
        $sformatf("no done pulse within %0d cycles for case %s",
                  DONE_TIMEOUT_CYCLES, t.case_dir))
    else
      `uvm_info("DRV", $sformatf("done observed for case %s (sat_seen=%0b)",
                                 t.case_dir, ctrl_vif.sat_seen), UVM_MEDIUM)

    repeat (5) @(posedge ctrl_vif.clk);
  endtask

endclass : npu_driver
