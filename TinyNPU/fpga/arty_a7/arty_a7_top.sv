// -----------------------------------------------------------------------------
// Digilent Arty A7-35T board shim (Phase 7). ALL board-specific decisions —
// pin names, button polarity, LED assignment — live here and in arty_a7.xdc;
// tinynpu_top and everything below it is board-agnostic.
//
//   BTN0        reset (active-high pressed -> active-low core reset)
//   BTN1        classify (runs the built-in demo image)
//   LD4..LD7    one-hot class result (cat / truck / plane / ship)
//   LD0 green   busy
//   LD0 red     saturation occurred during the last run
// -----------------------------------------------------------------------------
module arty_a7_top (
  input  logic       CLK100MHZ,
  input  logic [3:0] btn,
  output logic [3:0] led,
  output logic       led0_g,
  output logic       led0_r
);

  // 100 MHz board clock -> 50 MHz core clock (MMCM: VCO 1 GHz / 20).
  // The 64-lane single-cycle MAC adder tree does not close 100 MHz on the
  // -1L Artix-7 speed grade; 50 MHz closes with margin.
  logic clk_fb, clk_50_raw, clk_50, mmcm_locked;

  MMCME2_BASE #(
    .CLKIN1_PERIOD   (10.0),
    .CLKFBOUT_MULT_F (10.0),   // VCO = 100 MHz * 10 = 1 GHz
    .CLKOUT0_DIVIDE_F(20.0),   // 1 GHz / 20 = 50 MHz
    .DIVCLK_DIVIDE   (1)
  ) u_mmcm (
    .CLKIN1   (CLK100MHZ),
    .CLKFBIN  (clk_fb),
    .CLKFBOUT (clk_fb),
    .CLKOUT0  (clk_50_raw),
    .CLKOUT0B (),
    .CLKOUT1  (),
    .CLKOUT1B (),
    .CLKOUT2  (),
    .CLKOUT2B (),
    .CLKOUT3  (),
    .CLKOUT3B (),
    .CLKOUT4  (),
    .CLKOUT5  (),
    .CLKOUT6  (),
    .CLKFBOUTB(),
    .LOCKED   (mmcm_locked),
    .PWRDWN   (1'b0),
    .RST      (1'b0)
  );

  BUFG u_bufg (.I(clk_50_raw), .O(clk_50));

  tinynpu_top #(
    .DEBOUNCE_CNT_W (15),               // ~0.66 ms at 50 MHz
    .IMG_INIT       ("img_rom.memh"),   // resolved via read_mem in build.tcl
    .WGT_INIT       ("wgt_rom.memh")
  ) u_top (
    .clk       (clk_50),
    .rst_n     (~btn[0] & mmcm_locked),
    .btn_start (btn[1]),
    .led_class (led),
    .led_busy  (led0_g),
    .led_sat   (led0_r)
  );

endmodule : arty_a7_top
