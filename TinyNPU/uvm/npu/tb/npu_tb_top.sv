// -----------------------------------------------------------------------------
// npu_core full-system testbench top: 100 MHz clock, 5-cycle power-on reset,
// unified fm buffer + weight ROM behavioral memories, npu_core DUT, and
// config-db publication of the three virtual interfaces.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module npu_tb_top;

  import uvm_pkg::*;
  import tinynpu_pkg::*;
  import tinynpu_npu_uvm_pkg::*;

  // 100 MHz clock
  logic clk = 1'b0;
  always #5 clk = ~clk;

  // Power-on reset: low for 5 cycles, then released
  logic rst_n;
  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // Interfaces and behavioral memories
  npu_ctrl_if u_ctrl (.clk(clk), .rst_n(rst_n));
  fm_mem_if   u_fm   (.clk(clk));
  rom_if      u_wgt  (.clk(clk));

  npu_core dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .cfg_layers     (u_ctrl.cfg_layers),
    .cfg_num_layers (u_ctrl.cfg_num_layers),
    .start          (u_ctrl.start),
    .busy           (u_ctrl.busy),
    .done           (u_ctrl.done),
    .sat_seen       (u_ctrl.sat_seen),
    .fm_re          (u_fm.re),
    .fm_raddr       (u_fm.raddr),
    .fm_rdata       (u_fm.rdata),
    .fm_wen         (u_fm.wen),
    .fm_waddr       (u_fm.waddr),
    .fm_wdata       (u_fm.wdata),
    .wgt_re         (u_wgt.re),
    .wgt_addr       (u_wgt.addr),
    .wgt_rdata      (u_wgt.rdata)
  );

  initial begin
    uvm_config_db#(virtual npu_ctrl_if)::set(null, "*", "ctrl_vif", u_ctrl);
    uvm_config_db#(virtual fm_mem_if)::set(null, "*", "fm_vif", u_fm);
    uvm_config_db#(virtual rom_if)::set(null, "*", "wgt_vif", u_wgt);
    run_test();
  end

endmodule : npu_tb_top
