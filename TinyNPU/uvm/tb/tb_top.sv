// -----------------------------------------------------------------------------
// TinyNPU MAC array testbench top: 100 MHz clock, 5-cycle power-on reset,
// mid-stream reset request listener (global uvm_event "tinynpu_reset_req"
// pulses rst_n low for 3 cycles, then triggers "tinynpu_reset_done"),
// mac_if + DUT instances, config-db publication of the virtual interface,
// and run_test().
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import tinynpu_pkg::*;
  import tinynpu_uvm_pkg::*;

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

  // Mid-stream reset request listener (used by mac_unit_reset_test)
  initial begin : reset_request_listener
    uvm_event ev_req;
    uvm_event ev_done;
    ev_req  = uvm_event_pool::get_global("tinynpu_reset_req");
    ev_done = uvm_event_pool::get_global("tinynpu_reset_done");
    forever begin
      ev_req.wait_trigger();
      $display("[tb_top] @%0t: mid-stream reset request received, pulsing rst_n", $time);
      rst_n = 1'b0;
      repeat (3) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);
      ev_done.trigger();
    end
  end

  // Interface and DUT
  mac_if #(
    .NUM_LANES (NUM_LANES),
    .DATA_W    (DATA_W),
    .ACC_W     (ACC_W)
  ) mif (
    .clk   (clk),
    .rst_n (rst_n)
  );

  mac_array #(
    .NUM_LANES (NUM_LANES),
    .DATA_W    (DATA_W),
    .ACC_W     (ACC_W)
  ) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_valid  (mif.in_valid),
    .in_ready  (mif.in_ready),
    .act       (mif.act),
    .wgt       (mif.wgt),
    .acc_in    (mif.acc_in),
    .out_valid (mif.out_valid),
    .out_ready (mif.out_ready),
    .acc_out   (mif.acc_out),
    .sat_flag  (mif.sat_flag)
  );

  initial begin
    uvm_config_db#(virtual mac_if)::set(null, "*", "vif", mif);
    run_test();
  end

endmodule : tb_top
