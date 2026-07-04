// -----------------------------------------------------------------------------
// Passive MAC array monitor. On every posedge (outside reset):
//  - in_valid && in_ready   -> publish an input-accepted txn on ap_in
//  - out_valid && out_ready -> publish an output-completed txn on ap_out
// On every negedge of rst_n -> publish a reset notification on ap_reset so
// the scoreboard/coverage can flush in-flight expectations.
// Input events are published before output events within the same cycle, so
// the scoreboard's pending queue stays in acceptance order.
// -----------------------------------------------------------------------------
class mac_monitor extends uvm_component;

  `uvm_component_utils(mac_monitor)

  virtual mac_if vif;

  uvm_analysis_port #(mac_txn) ap_in;
  uvm_analysis_port #(mac_txn) ap_out;
  uvm_analysis_port #(bit)     ap_reset;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_in    = new("ap_in", this);
    ap_out   = new("ap_out", this);
    ap_reset = new("ap_reset", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mac_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "mac_monitor: virtual mac_if not found in config db under key 'vif'")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      watch_reset();
      watch_handshakes();
    join
  endtask

  protected task watch_reset();
    forever begin
      @(negedge vif.rst_n);
      `uvm_info("MON", "rst_n asserted; publishing reset notification", UVM_MEDIUM)
      ap_reset.write(1'b1);
    end
  endtask

  protected task watch_handshakes();
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n !== 1'b1) continue;

      if (vif.in_valid === 1'b1 && vif.in_ready === 1'b1) begin
        mac_txn t = mac_txn::type_id::create("mon_in_txn");
        foreach (t.act[i]) begin
          t.act[i] = $signed(vif.act[i*DATA_W +: DATA_W]);
          t.wgt[i] = $signed(vif.wgt[i*DATA_W +: DATA_W]);
        end
        t.acc_in = $signed(vif.acc_in);
        `uvm_info("MON", $sformatf("input accepted: acc_in=0x%08h", t.acc_in), UVM_HIGH)
        ap_in.write(t);
      end

      if (vif.out_valid === 1'b1 && vif.out_ready === 1'b1) begin
        mac_txn t = mac_txn::type_id::create("mon_out_txn");
        if ($isunknown(vif.acc_out) || $isunknown(vif.sat_flag))
          `uvm_error("MON", $sformatf("X/Z on completed output: acc_out=%h sat_flag=%b",
                                      vif.acc_out, vif.sat_flag))
        t.acc_out  = $signed(vif.acc_out);
        t.sat_flag = vif.sat_flag;
        `uvm_info("MON", $sformatf("output completed: acc_out=0x%08h sat=%0b",
                                   t.acc_out, t.sat_flag), UVM_HIGH)
        ap_out.write(t);
      end
    end
  endtask

endclass : mac_monitor
