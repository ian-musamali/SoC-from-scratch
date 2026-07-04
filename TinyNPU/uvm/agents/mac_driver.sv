// -----------------------------------------------------------------------------
// MAC array driver.
//  - Input side: waits idle_cycles, packs the 64 lanes into the flat act/wgt
//    buses, raises in_valid and holds it until a posedge samples in_ready
//    high, then deasserts (or immediately re-drives the next item, giving
//    back-to-back full-throughput traffic when idle_cycles == 0).
//  - Output side: models the downstream consumer by toggling out_ready every
//    cycle, weighted ~80% high, unless the out_ready_always_on config bit is
//    set (used by the directed smoke/overflow tests).
//  - Reset mid-drive: in_valid is dropped, the killed item is NOT re-driven,
//    and the driver continues with the next sequence item.
// -----------------------------------------------------------------------------
class mac_driver extends uvm_driver #(mac_txn);

  `uvm_component_utils(mac_driver)

  virtual mac_if vif;
  bit            out_ready_always_on;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mac_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "mac_driver: virtual mac_if not found in config db under key 'vif'")
    if (!uvm_config_db#(bit)::get(this, "", "out_ready_always_on", out_ready_always_on))
      out_ready_always_on = 1'b0;
  endfunction

  task run_phase(uvm_phase phase);
    mac_txn req;

    // Initialize interface outputs before reset release
    vif.in_valid  <= 1'b0;
    vif.act       <= '0;
    vif.wgt       <= '0;
    vif.acc_in    <= '0;
    vif.out_ready <= 1'b1;

    fork
      toggle_out_ready();
    join_none

    forever begin
      seq_item_port.get_next_item(req);
      drive_txn(req);
      seq_item_port.item_done();
    end
  endtask

  // Downstream consumer model: random backpressure on out_ready
  protected task toggle_out_ready();
    forever begin
      @(posedge vif.clk);
      if (out_ready_always_on)
        vif.out_ready <= 1'b1;
      else
        vif.out_ready <= ($urandom_range(99) < 80);
    end
  endtask

  protected task drive_txn(mac_txn t);
    // If we are in reset, wait it out before presenting anything
    if (vif.rst_n !== 1'b1) begin
      wait (vif.rst_n === 1'b1);
      @(posedge vif.clk);
    end

    repeat (t.idle_cycles) @(posedge vif.clk);

    // Reset during the idle gap: nothing was driven yet, so this item is
    // still valid — just wait for release and drive it normally.
    if (vif.rst_n !== 1'b1) begin
      wait (vif.rst_n === 1'b1);
      @(posedge vif.clk);
    end

    foreach (t.act[i]) begin
      vif.act[i*DATA_W +: DATA_W] <= t.act[i];
      vif.wgt[i*DATA_W +: DATA_W] <= t.wgt[i];
    end
    vif.acc_in   <= t.acc_in;
    vif.in_valid <= 1'b1;

    // Hold in_valid until a posedge samples in_ready high
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n !== 1'b1) begin
        // Reset killed this in-flight item: drop it and do NOT re-drive
        vif.in_valid <= 1'b0;
        `uvm_info("DRV", "reset asserted mid-drive; dropping in-flight item", UVM_MEDIUM)
        wait (vif.rst_n === 1'b1);
        @(posedge vif.clk);
        return;
      end
      if (vif.in_ready === 1'b1) break;
    end
    vif.in_valid <= 1'b0;
  endtask

endclass : mac_driver
