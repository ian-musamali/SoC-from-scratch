// -----------------------------------------------------------------------------
// Top-level wrapper smoke test (Phase 7): presses the classify button and
// checks the one-hot class LEDs against the golden expected class
// (+EXP_CLASS, from fpga/mem/expected.txt — produced by the same golden run
// that generated the ROM images). Prints the TINYNPU TEST PASSED/FAILED
// banner so the regression summary can grep it like every other test.
// Paths default to running from sim/ (see Makefile target).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tinynpu_top_tb;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n = 1'b0;
  logic btn_start = 1'b0;
  logic [3:0] led_class;
  logic led_busy, led_sat;

  tinynpu_top #(
    .DEBOUNCE_CNT_W (3),  // 8-cycle stability window in sim
    .IMG_INIT       ("../fpga/mem/img_rom.memh"),
    .WGT_INIT       ("../fpga/mem/wgt_rom.memh")
  ) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .btn_start (btn_start),
    .led_class (led_class),
    .led_busy  (led_busy),
    .led_sat   (led_sat)
  );

  int exp_class, tmo, errors;

  initial begin
    errors = 0;
    if (!$value$plusargs("EXP_CLASS=%d", exp_class))
      $fatal(1, "need +EXP_CLASS=<n> (line 1 of fpga/mem/expected.txt)");

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    if (led_class !== 4'b0000) begin
      errors++;
      $display("FAIL: LEDs not clear after reset (led_class=%b)", led_class);
    end

    // Press and hold the button long enough for the debouncer, then release
    btn_start = 1'b1;
    repeat (20) @(posedge clk);
    btn_start = 1'b0;

    // Wait for busy to rise, then for the result to latch
    tmo = 0;
    while (led_busy !== 1'b1) begin
      @(posedge clk);
      tmo++;
      if (tmo > 1000) $fatal(1, "busy never rose after button press");
    end
    $display("classification running (busy high)");

    tmo = 0;
    while (led_class === 4'b0000) begin
      @(posedge clk);
      tmo++;
      if (tmo > 20_000_000) $fatal(1, "no result within cycle budget");
    end

    if (led_busy !== 1'b0) begin
      @(posedge clk);  // display latches one cycle before T_IDLE
      if (led_busy !== 1'b0) begin
        errors++;
        $display("FAIL: busy still high after result latched");
      end
    end

    if (led_class !== (4'b0001 << exp_class[1:0])) begin
      errors++;
      $display("FAIL: led_class=%b, expected one-hot of class %0d",
               led_class, exp_class);
    end
    else begin
      $display("led_class=%b matches expected class %0d (sat=%b)",
               led_class, exp_class, led_sat);
    end

    if (errors == 0) $display("TINYNPU TEST PASSED");
    else             $display("TINYNPU TEST FAILED");
    $finish;
  end

endmodule : tinynpu_top_tb
