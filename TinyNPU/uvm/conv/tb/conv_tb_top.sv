// -----------------------------------------------------------------------------
// conv_engine isolated testbench top: 100 MHz clock, 5-cycle power-on reset,
// behavioral ifm/wgt ROMs, an fm_mem_if used purely as an OFM write capture
// (read port tied off), the golden MAC responder's interface, and the DUT.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module conv_tb_top;

  import uvm_pkg::*;
  import tinynpu_pkg::*;
  import tinynpu_conv_uvm_pkg::*;

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
  conv_ctrl_if u_ctrl (.clk(clk), .rst_n(rst_n));
  conv_mac_if  u_mac  (.clk(clk), .rst_n(rst_n));
  rom_if #(.ADDR_W(FM_ADDR_W), .DATA_W(DATA_W)) u_ifm (.clk(clk));
  rom_if u_wgt (.clk(clk));   // default (WGT_ADDR_W, DATA_W)
  fm_mem_if u_ofm (.clk(clk));  // OFM write capture; read port unused

  assign u_ofm.re    = 1'b0;
  assign u_ofm.raddr = '0;

  conv_engine dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .cfg_img_w    (u_ctrl.cfg_img_w),
    .cfg_img_h    (u_ctrl.cfg_img_h),
    .cfg_in_ch    (u_ctrl.cfg_in_ch),
    .cfg_stride2  (u_ctrl.cfg_stride2),
    .cfg_pad      (u_ctrl.cfg_pad),
    .cfg_out_shift(u_ctrl.cfg_out_shift),
    .cfg_ifm_base (u_ctrl.cfg_ifm_base),
    .cfg_ofm_base (u_ctrl.cfg_ofm_base),
    .cfg_wgt_base (u_ctrl.cfg_wgt_base),
    .cfg_acc_init (u_ctrl.cfg_acc_init),
    .start        (u_ctrl.start),
    .busy         (u_ctrl.busy),
    .done         (u_ctrl.done),
    .sat_seen     (u_ctrl.sat_seen),
    .ifm_re       (u_ifm.re),
    .ifm_addr     (u_ifm.addr),
    .ifm_rdata    (u_ifm.rdata),
    .wgt_re       (u_wgt.re),
    .wgt_addr     (u_wgt.addr),
    .wgt_rdata    (u_wgt.rdata),
    .mac_valid    (u_mac.mac_valid),
    .mac_ready    (u_mac.mac_ready),
    .mac_act      (u_mac.mac_act),
    .mac_wgt      (u_mac.mac_wgt),
    .mac_acc_in   (u_mac.mac_acc_in),
    .mac_res_valid(u_mac.mac_res_valid),
    .mac_res_ready(u_mac.mac_res_ready),
    .mac_res_acc  (u_mac.mac_res_acc),
    .mac_res_sat  (u_mac.mac_res_sat),
    .ofm_wen      (u_ofm.wen),
    .ofm_addr     (u_ofm.waddr),
    .ofm_wdata    (u_ofm.wdata)
  );

  initial begin
    uvm_config_db#(virtual conv_ctrl_if)::set(null, "*", "ctrl_vif", u_ctrl);
    uvm_config_db#(virtual conv_mac_if)::set(null, "*", "mac_vif", u_mac);
    uvm_config_db#(virtual rom_if#(tinynpu_pkg::FM_ADDR_W, tinynpu_pkg::DATA_W))::
      set(null, "*", "ifm_vif", u_ifm);
    uvm_config_db#(virtual rom_if)::set(null, "*", "wgt_vif", u_wgt);
    uvm_config_db#(virtual fm_mem_if)::set(null, "*", "ofm_vif", u_ofm);
    run_test();
  end

endmodule : conv_tb_top
