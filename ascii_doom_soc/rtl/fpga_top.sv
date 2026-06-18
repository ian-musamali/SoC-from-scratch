// FPGA top-level wrapper for Nexys A7 (XC7A100T).
// Generates sys_clk (100 MHz) and pix_clk (25 MHz) from the 100 MHz board oscillator
// via a single MMCME2_BASE instance.  Ties off all simulation-only ports on soc_top.
module fpga_top (
    input  logic        sys_clk_in,  // 100 MHz onboard oscillator (E3)
    input  logic        cpu_resetn,  // Active-low reset (CPU_RESET button, C12)

    output logic        vga_hsync,
    output logic        vga_vsync,
    output logic [3:0]  vga_r,
    output logic [3:0]  vga_g,
    output logic [3:0]  vga_b,

    output logic        uart_tx,
    input  logic        uart_rx
);

    // -------------------------------------------------------------------------
    // Clock generation: 100 MHz → 65 MHz (sys) + 25 MHz (pix) via MMCM
    // VCO = 100 * 6.5 = 650 MHz (within Artix-7 600–1200 MHz spec)
    // CLKOUT0 = 650 / 26  = 25.000 MHz  (pix_clk)
    // CLKOUT1 = 650 / 10  =  65.000 MHz (sys_clk)
    // NOTE: DDA fixed-point arithmetic critical path ~14.5 ns; 65 MHz (15.4 ns)
    // provides positive slack. 100 MHz target requires pipelining fpmul/fpdiv.
    // -------------------------------------------------------------------------
    logic sys_clk_raw, pix_clk_raw, clkfb, pll_locked;

    MMCME2_BASE #(
        .BANDWIDTH        ("OPTIMIZED"),
        .CLKFBOUT_MULT_F  (6.5),
        .CLKFBOUT_PHASE   (0.0),
        .CLKIN1_PERIOD    (10.0),       // 100 MHz input
        .CLKOUT0_DIVIDE_F (26.0),       // 25.0 MHz  (pix_clk)
        .CLKOUT1_DIVIDE   (10),         //  65.0 MHz  (sys_clk)
        .CLKOUT0_PHASE    (0.0),
        .CLKOUT1_PHASE    (0.0),
        .DIVCLK_DIVIDE    (1),
        .REF_JITTER1      (0.01),
        .STARTUP_WAIT     ("FALSE")
    ) u_mmcm (
        .CLKIN1   (sys_clk_in),
        .CLKFBIN  (clkfb),
        .CLKOUT0  (pix_clk_raw),
        .CLKOUT1  (sys_clk_raw),
        .CLKFBOUT (clkfb),
        .LOCKED   (pll_locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0)
    );

    logic sys_clk, pix_clk;
    BUFG u_bufg_sys (.I(sys_clk_raw), .O(sys_clk));
    BUFG u_bufg_pix (.I(pix_clk_raw), .O(pix_clk));

    logic rst_n;
    assign rst_n = cpu_resetn & pll_locked;

    // -------------------------------------------------------------------------
    // SoC instantiation — simulation ports tied off
    // -------------------------------------------------------------------------
    soc_top #(
        .SIMULATION(0)
    ) u_soc (
        .sys_clk (sys_clk),
        .pix_clk (pix_clk),
        .rst_n   (rst_n),

        .vga_hsync (vga_hsync),
        .vga_vsync (vga_vsync),
        .vga_r     (vga_r),
        .vga_g     (vga_g),
        .vga_b     (vga_b),

        .uart_tx (uart_tx),
        .uart_rx (uart_rx),

        // Simulation bypass ports — constant-zero in synthesis
        .sim_cpu_awaddr  ('0), .sim_cpu_awvalid (1'b0),
        .sim_cpu_wdata   ('0), .sim_cpu_wstrb   ('0),
        .sim_cpu_wvalid  (1'b0), .sim_cpu_bready (1'b0),
        .sim_cpu_araddr  ('0), .sim_cpu_arvalid (1'b0),
        .sim_cpu_rready  (1'b0),
        .sim_map_addr    ('0), .sim_map_wdata   ('0),
        .sim_map_wen     (1'b0), .sim_map_core  ('0),

        // Output stubs (unused in synthesis)
        .sim_cpu_awready (), .sim_cpu_wready  (),
        .sim_cpu_bresp   (), .sim_cpu_bvalid  (),
        .sim_cpu_arready (), .sim_cpu_rdata   (),
        .sim_cpu_rresp   (), .sim_cpu_rvalid  ()
    );

endmodule
